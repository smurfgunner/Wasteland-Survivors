import Foundation

enum ReplicationDelivery: String, Codable, Sendable {
    case replaceable
    case reliable
}

struct ReplicationEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let type: String
    let ownerID: String
    let sequence: UInt64
    let tick: UInt64
    let serverTime: TimeInterval
    let stateHash: UInt64
    let delivery: ReplicationDelivery
    let payload: Data

    init(
        type: String,
        ownerID: String,
        sequence: UInt64,
        tick: UInt64,
        serverTime: TimeInterval = 0,
        stateHash: UInt64 = 0,
        delivery: ReplicationDelivery,
        payload: Data
    ) {
        self.version = Self.currentVersion
        self.type = type
        self.ownerID = ownerID
        self.sequence = sequence
        self.tick = tick
        self.serverTime = serverTime
        self.stateHash = stateHash
        self.delivery = delivery
        self.payload = payload
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        let envelope = try JSONDecoder().decode(Self.self, from: data)
        try envelope.validate()
        return envelope
    }

    func validate(expectedOwnerID: String? = nil, latestSequence: UInt64? = nil) throws {
        guard version == Self.currentVersion else { throw ReplicationError.unsupportedVersion(version) }
        guard !type.isEmpty, !ownerID.isEmpty else { throw ReplicationError.invalidIdentity }
        if let expectedOwnerID, ownerID != expectedOwnerID {
            throw ReplicationError.unauthorizedOwner
        }
        if let latestSequence, sequence <= latestSequence {
            throw ReplicationError.staleSequence
        }
    }
}

enum ReplicationError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case invalidIdentity
    case unauthorizedOwner
    case staleSequence
    case malformedPayload
    case inconsistentState
}

enum ReplicationStateHasher {
    static func hash(_ state: GameState) throws -> UInt64 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return hash(try encoder.encode(state))
    }

    static func hash(_ data: Data) -> UInt64 {
        data.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

struct AuthoritativeSnapshot: Codable, Equatable, Sendable {
    let sequence: UInt64
    let tick: UInt64
    let serverTime: TimeInterval
    let hostID: String
    let state: GameState

    func envelope() throws -> ReplicationEnvelope {
        let payload = try JSONEncoder().encode(state)
        return ReplicationEnvelope(
            type: "authoritativeSnapshot",
            ownerID: hostID,
            sequence: sequence,
            tick: tick,
            serverTime: serverTime,
            stateHash: try ReplicationStateHasher.hash(state),
            delivery: .replaceable,
            payload: payload
        )
    }

    static func from(_ envelope: ReplicationEnvelope, expectedHostID: String) throws -> Self {
        try envelope.validate(expectedOwnerID: expectedHostID)
        guard envelope.type == "authoritativeSnapshot" else { throw ReplicationError.malformedPayload }
        guard let state = try? JSONDecoder().decode(GameState.self, from: envelope.payload) else {
            throw ReplicationError.malformedPayload
        }
        guard state.tick == envelope.tick else { throw ReplicationError.inconsistentState }
        guard envelope.stateHash == (try? ReplicationStateHasher.hash(state)) else { throw ReplicationError.inconsistentState }
        return Self(
            sequence: envelope.sequence,
            tick: envelope.tick,
            serverTime: envelope.serverTime,
            hostID: envelope.ownerID,
            state: state
        )
    }
}

struct SnapshotHistory: Sendable {
    private(set) var snapshots: [AuthoritativeSnapshot] = []
    let capacity: Int

    init(capacity: Int = 32) {
        self.capacity = max(2, capacity)
    }

    mutating func append(_ snapshot: AuthoritativeSnapshot) -> Bool {
        guard !snapshots.contains(where: { $0.sequence == snapshot.sequence }) else { return false }
        snapshots.append(snapshot)
        snapshots.sort { $0.sequence < $1.sequence }
        if snapshots.count > capacity {
            snapshots.removeFirst(snapshots.count - capacity)
        }
        return true
    }

    func surrounding(tick: UInt64) -> (before: AuthoritativeSnapshot, after: AuthoritativeSnapshot)? {
        guard let afterIndex = snapshots.firstIndex(where: { $0.tick >= tick }),
              afterIndex > 0 else { return nil }
        return (snapshots[afterIndex - 1], snapshots[afterIndex])
    }
}

struct AppliedEventStore: Sendable {
    private var ids: Set<String> = []
    private var insertionOrder: [String] = []
    let capacity: Int

    init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    mutating func insertIfNew(_ event: GameplayEvent, key: String? = nil) -> Bool {
        let eventKey = key ?? event.id
        guard !ids.contains(eventKey) else { return false }
        if insertionOrder.count >= capacity, let oldestID = insertionOrder.first {
            ids.remove(oldestID)
            insertionOrder.removeFirst()
        }
        ids.insert(eventKey)
        insertionOrder.append(eventKey)
        return true
    }
}

struct LocalPredictionReconciler {
    static func reconcile(
        authoritativeState: GameState,
        acknowledgedInputSequence: UInt64,
        pendingInputs: [PlayerInput],
        simulation: GameSimulation,
        targetTick: UInt64? = nil
    ) -> GameState {
        var state = authoritativeState
        let replayInputs = pendingInputs
            .filter { $0.sequence > acknowledgedInputSequence }
            .sorted { $0.sequence < $1.sequence }
        let ticksToReplay = targetTick.map {
            $0 > state.tick ? $0 - state.tick : 0
        } ?? UInt64(replayInputs.count)

        // Input sequence numbers identify client inputs, not simulation ticks.
        // A delayed snapshot may leave many inputs pending, but replaying all of
        // them would advance prediction into the future. Only replay enough
        // inputs to reach the client's current simulation tick.
        for input in replayInputs.prefix(Int(min(UInt64(replayInputs.count), ticksToReplay))) {
            state = simulation.advance(state, inputs: [input], tick: state.tick + 1).state
        }
        return state
    }
}

struct LocalPredictionInputHistory {
    private(set) var pendingInputs: [PlayerInput] = []
    let capacity: Int

    init(capacity: Int = 128) {
        self.capacity = max(1, capacity)
    }

    mutating func record(_ input: PlayerInput) {
        pendingInputs.removeAll {
            $0.playerID == input.playerID && $0.sequence == input.sequence
        }
        pendingInputs.append(input)
        pendingInputs.sort {
            if $0.playerID == $1.playerID { return $0.sequence < $1.sequence }
            return $0.playerID < $1.playerID
        }
        if pendingInputs.count > capacity {
            pendingInputs.removeFirst(pendingInputs.count - capacity)
        }
    }

    mutating func acknowledge(sequence: UInt64, for playerID: String? = nil) {
        pendingInputs.removeAll {
            (playerID == nil || $0.playerID == playerID) && $0.sequence <= sequence
        }
    }
}

enum MultiplayerSnapshotTiming {
    static let hostSnapshotInterval: TimeInterval = 1.0 / 30.0

    static func interpolationDelayTicks(snapshotIntervalTicks: UInt64) -> UInt64 {
        min(12, max(2, snapshotIntervalTicks * 2))
    }
}
