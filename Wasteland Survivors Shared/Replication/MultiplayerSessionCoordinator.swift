import Foundation

struct MultiplayerHello: Codable, Equatable, Sendable {
    let sessionID: String
    let peerID: String
    let startedAt: TimeInterval
    let protocolVersion: Int
}

struct MultiplayerHostAnnouncement: Codable, Equatable, Sendable {
    let sessionID: String
    let hostID: String
    let hostStartedAt: TimeInterval
    let protocolVersion: Int
}

struct MultiplayerJoinRequest: Codable, Equatable, Sendable {
    let sessionID: String
    let peerID: String
    let protocolVersion: Int
}

struct MultiplayerJoinAccepted: Codable, Equatable, Sendable {
    let sessionID: String
    let peerID: String
    let hostID: String
    let protocolVersion: Int
}

enum MultiplayerSessionRole: Equatable, Sendable {
    case idle
    case negotiating
    case host
    case client
    case disconnected
}

@MainActor
final class MultiplayerSessionCoordinator: MultiplayerTransportDelegate {
    private let transport: MultiplayerTransport
    private var sessionID: String
    private let startedAt: TimeInterval
    private let protocolVersion: Int
    private var acceptedPeerIDs: Set<String> = []
    private var latestInputSequences: [String: UInt64] = [:]
    private var latestSnapshotSequence: UInt64?
    private var latestAcknowledgedInputSequences: [String: UInt64] = [:]
    private var acknowledgedInputSequencesStorage: [String: UInt64] = [:]
    private var queuedInputs: [MultiplayerPlayerInput] = []
    private var latestInputs: [String: MultiplayerPlayerInput] = [:]
    private var lastInputReceiveLogTime: TimeInterval = 0
    private var lastInputConsumeLogTime: TimeInterval = 0
    private var appliedEvents = AppliedEventStore()
    private var hasSentHello = false

    private(set) var role: MultiplayerSessionRole = .idle
    private(set) var hostID: String?
    var acknowledgedInputSequences: [String: UInt64] {
        acknowledgedInputSequencesStorage
    }
    var onRoleChanged: ((MultiplayerSessionRole) -> Void)?
    /// Called after a host has accepted a peer, allowing the gameplay layer to
    /// immediately send the complete authoritative state for late join-in.
    var onPeerJoined: ((String) -> Void)?
    var onHostLost: ((String) -> Void)?
    var onInput: ((MultiplayerPlayerInput) -> Void)?
    var onGameplayEvent: ((MultiplayerGameplayEvent) -> Void)?
    var onMessage: ((MultiplayerWireMessage) -> Void)?
    var onTransportError: ((MultiplayerTransportError) -> Void)?

    init(
        transport: MultiplayerTransport,
        sessionID: String,
        startedAt: TimeInterval,
        protocolVersion: Int = 1
    ) {
        self.transport = transport
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.protocolVersion = protocolVersion
    }

    func start() {
        guard role == .idle || role == .disconnected else { return }
        hasSentHello = false
        transport.delegate = self
        updateRole(.negotiating)
        transport.connect()
        if transport.state == .connected {
            sendHello()
        }
    }

    private func sendHello() {
        guard !hasSentHello else { return }
        hasSentHello = true
        send(.hello(MultiplayerHello(
            sessionID: sessionID,
            peerID: transport.localPeerID,
            startedAt: startedAt,
            protocolVersion: protocolVersion
        )))
    }

    func stop() {
        transport.disconnect()
        updateRole(.disconnected)
        hostID = nil
        acceptedPeerIDs.removeAll()
        latestInputSequences.removeAll()
        latestSnapshotSequence = nil
        latestAcknowledgedInputSequences.removeAll()
        acknowledgedInputSequencesStorage.removeAll()
        queuedInputs.removeAll()
        latestInputs.removeAll()
        appliedEvents = AppliedEventStore()
    }

    func consumeQueuedInputs() -> [MultiplayerPlayerInput] {
        let inputsByPlayer = Dictionary(
            queuedInputs.map { ($0.playerID, $0) },
            uniquingKeysWith: { current, replacement in
                isNewer(current.sequence, than: replacement.sequence) ? current : replacement
            }
        )
        latestInputs.merge(inputsByPlayer) { current, replacement in
            isNewer(current.sequence, than: replacement.sequence) ? current : replacement
        }
        let inputsToApply = latestInputs.values.sorted { $0.playerID < $1.playerID }
        for input in inputsToApply {
            acknowledgedInputSequencesStorage[input.playerID] = input.sequence
            latestInputs[input.playerID] = MultiplayerPlayerInput(
                playerID: input.playerID,
                sequence: input.sequence,
                movement: input.movement,
                aimAngle: input.aimAngle,
                wantsToAttack: input.wantsToAttack,
                attackTargetID: input.attackTargetID,
                wantsToOpenChestID: nil,
                wantsToCollectPowerUpID: nil
            )
        }
        queuedInputs.removeAll()
        return inputsToApply
    }

    func broadcastGameplayEvent(_ event: GameplayEvent, sequence: UInt64, tick: UInt64) {
        guard role == .host else { return }
        send(.gameplayEvent(MultiplayerGameplayEvent(
            event: event,
            sessionID: sessionID,
            sequence: sequence,
            tick: tick,
            hostID: transport.localPeerID
        )))
    }

    func sendPlayerInput(_ input: MultiplayerPlayerInput) {
        guard role == .client,
              input.playerID == transport.localPeerID,
              let hostID else { return }
        send(.playerInput(input), to: hostID)
    }

    func transport(_ transport: MultiplayerTransport, didChange state: MultiplayerTransportState) {
        if state == .connected {
            sendHello()
        }
        if state == .disconnected || state == .failed {
            updateRole(.disconnected)
            hostID = nil
            acceptedPeerIDs.removeAll()
            latestInputSequences.removeAll()
            latestSnapshotSequence = nil
            latestAcknowledgedInputSequences.removeAll()
            queuedInputs.removeAll()
            latestInputs.removeAll()
            appliedEvents = AppliedEventStore()
        }
    }

    func transport(_ transport: MultiplayerTransport, didChangePeer peerID: String, state: MultiplayerPeerState) {
        guard state == .disconnected else { return }

        acceptedPeerIDs.remove(peerID)
        latestInputSequences[peerID] = nil
        latestInputs[peerID] = nil
        acknowledgedInputSequencesStorage[peerID] = nil
        queuedInputs.removeAll { $0.playerID == peerID }

        if hostID == peerID, role == .client {
            onHostLost?(peerID)
            hostID = nil
            latestAcknowledgedInputSequences.removeAll()
            appliedEvents = AppliedEventStore()
            updateRole(.disconnected)
        }
    }

    func transport(_ transportService: MultiplayerTransport, didReceive data: Data, from peerID: String) {
        guard let message = try? MultiplayerWireMessage.decode(data) else {
            return
        }
        self.transport(transportService, didReceive: message, from: peerID)
    }

    func transport(_ transportService: MultiplayerTransport, didReceive message: MultiplayerWireMessage, from peerID: String) {
        guard senderMatches(message, peerID: peerID) else {
            return
        }
        guard isAuthorized(message, from: peerID) else {
            return
        }
        if handle(message) {
            onMessage?(message)
        }
    }

    private func isAuthorized(_ message: MultiplayerWireMessage, from peerID: String) -> Bool {
        switch message {
        case let .playerUpdate(state):
            // Player updates are a compatibility path from older builds. They
            // are host-to-client only and can never mutate host authority.
            return role == .client && hostID == peerID && state.id == peerID
        case let .boardSnapshot(board):
            guard role == .client, hostID == peerID, board.hostID == hostID else { return false }
            guard (try? board.validate(expectedHostID: peerID)) != nil else { return false }
            guard board.acknowledgedInputSequences.allSatisfy({ playerID, sequence in
                latestAcknowledgedInputSequences[playerID].map { sequence >= $0 } ?? true
            }) else { return false }
            guard latestSnapshotSequence.map({ board.sequence > $0 }) ?? true else { return false }
            latestSnapshotSequence = board.sequence
            latestAcknowledgedInputSequences.merge(board.acknowledgedInputSequences) { _, incoming in incoming }
            return true
        case let .gameplayEvent(event):
            guard role == .client, hostID == peerID else { return false }
            do {
                try event.validate(expectedHostID: peerID, expectedSessionID: sessionID)
                return true
            } catch {
                return false
            }
        default:
            return true
        }
    }

    private func senderMatches(_ message: MultiplayerWireMessage, peerID: String) -> Bool {
        switch message {
        case let .hello(hello): return hello.peerID == peerID
        case let .hostAnnouncement(announcement): return announcement.hostID == peerID
        case let .joinRequest(request): return request.peerID == peerID
        case let .joinAccepted(accepted): return accepted.hostID == peerID
        case let .playerUpdate(state): return state.id == peerID
        case let .boardSnapshot(board): return board.hostID == peerID
        case let .compactSnapshot(snapshot): return snapshot.hostID == peerID
        case let .playerInput(input): return input.playerID == peerID
        case let .gameplayEvent(event): return event.hostID == peerID
        }
    }

    @discardableResult
    private func handle(_ message: MultiplayerWireMessage) -> Bool {
        switch message {
        case let .hello(hello): handle(hello)
        case let .hostAnnouncement(announcement): handle(announcement)
        case let .joinRequest(request): handle(request)
        case let .joinAccepted(accepted): handle(accepted)
        case let .playerInput(input): handle(input)
        case .playerUpdate, .boardSnapshot, .compactSnapshot: return true
        case let .gameplayEvent(event):
            guard appliedEvents.insertIfNew(
                event.event,
                key: "\(event.sessionID):\(event.sequence)"
            ) else { return false }
            onGameplayEvent?(event)
            return true
        }
        return true
    }

    private func handle(_ hello: MultiplayerHello) {
        guard hello.peerID != transport.localPeerID else {
            return
        }
        guard hello.protocolVersion == protocolVersion else {
            return
        }

        guard hasPriority(over: hello) else {
            sessionID = hello.sessionID
            becomeClient(hostID: hello.peerID)
            send(.joinRequest(MultiplayerJoinRequest(
                sessionID: sessionID,
                peerID: transport.localPeerID,
                protocolVersion: protocolVersion
            )), to: hello.peerID)
            return
        }

        becomeHost()
        send(.hostAnnouncement(MultiplayerHostAnnouncement(
            sessionID: sessionID,
            hostID: transport.localPeerID,
            hostStartedAt: startedAt,
            protocolVersion: protocolVersion
        )))
    }

    private func handle(_ announcement: MultiplayerHostAnnouncement) {
        guard announcement.protocolVersion == protocolVersion else {
            return
        }
        guard announcement.hostID != transport.localPeerID else {
            return
        }

        sessionID = announcement.sessionID
        becomeClient(hostID: announcement.hostID)
        send(.joinRequest(MultiplayerJoinRequest(
            sessionID: sessionID,
            peerID: transport.localPeerID,
            protocolVersion: protocolVersion
        )), to: announcement.hostID)
    }

    private func handle(_ request: MultiplayerJoinRequest) {
        guard role == .host,
              isCompatible(sessionID: request.sessionID, version: request.protocolVersion),
              request.peerID != transport.localPeerID,
              transport.connectedPeerIDs.contains(request.peerID),
              acceptedPeerIDs.insert(request.peerID).inserted else { return }

        send(.joinAccepted(MultiplayerJoinAccepted(
            sessionID: sessionID,
            peerID: request.peerID,
            hostID: transport.localPeerID,
            protocolVersion: protocolVersion
        )), to: request.peerID)
        onPeerJoined?(request.peerID)
    }

    private func handle(_ accepted: MultiplayerJoinAccepted) {
        guard isCompatible(sessionID: accepted.sessionID, version: accepted.protocolVersion),
              accepted.peerID == transport.localPeerID else { return }
        becomeClient(hostID: accepted.hostID)
    }

    private func handle(_ input: MultiplayerPlayerInput) {
        guard role == .host,
              input.playerID != transport.localPeerID,
              acceptedPeerIDs.contains(input.playerID),
              transport.connectedPeerIDs.contains(input.playerID),
              isValid(input),
              latestInputSequences[input.playerID].map({ isNewer(input.sequence, than: $0) }) ?? true else { return }
        latestInputSequences[input.playerID] = input.sequence
        latestInputs[input.playerID] = input
        queuedInputs.append(input)
        onInput?(input)
    }

    private func isValid(_ input: MultiplayerPlayerInput) -> Bool {
        input.movementX.isFinite &&
        input.movementY.isFinite &&
        input.aimAngle.isFinite &&
        hypot(input.movementX, input.movementY) <= 1
    }

    private func isNewer(_ incoming: UInt64, than latest: UInt64) -> Bool {
        let distance = incoming &- latest
        return distance > 0 && distance < UInt64.max / 2
    }

    private func hasPriority(over peer: MultiplayerHello) -> Bool {
        startedAt < peer.startedAt || (startedAt == peer.startedAt && transport.localPeerID < peer.peerID)
    }

    private func isCompatible(sessionID otherSessionID: String, version: Int) -> Bool {
        otherSessionID == sessionID && version == protocolVersion
    }

    private func becomeHost() {
        hostID = transport.localPeerID
        updateRole(.host)
    }

    private func becomeClient(hostID: String) {
        self.hostID = hostID
        updateRole(.client)
    }

    private func updateRole(_ role: MultiplayerSessionRole) {
        guard self.role != role else { return }
        self.role = role
        onRoleChanged?(role)
    }

    private func send(_ message: MultiplayerWireMessage, to peerID: String? = nil) {
        guard let data = try? message.encoded() else { return }
        do {
            if let peerID {
                try transport.send(data, to: peerID, delivery: message.deliveryPolicy)
            } else {
                try transport.broadcast(data, delivery: message.deliveryPolicy)
            }
        } catch let error as MultiplayerTransportError {
            onTransportError?(error)
        } catch {
            // Unknown transport failures do not have a stable protocol representation.
        }
    }
}
