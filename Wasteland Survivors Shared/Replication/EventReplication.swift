import Foundation

struct MultiplayerInitializationPlayer: Codable, Equatable, Sendable {
    let id: String
    let spawnPosition: CGPointValue
    let facing: Double

    init(id: String, spawnPosition: CGPointValue, facing: Double = 0) {
        self.id = id
        self.spawnPosition = spawnPosition
        self.facing = facing
    }

    init(id: String, position: CGPointValue, facing: Double = 0) {
        self.init(id: id, spawnPosition: position, facing: facing)
    }
}

struct MultiplayerInitializationZombie: Codable, Equatable, Sendable {
    let id: String
    let position: CGPointValue
    var health: Double
}

struct MultiplayerInitializationPayload: Codable, Equatable, Sendable {
    var sessionID: String
    var sequence: UInt64
    var simulationTick: UInt64
    var seed: UInt64
    var hostID: String
    var protocolVersion: Int
    var players: [MultiplayerInitializationPlayer]
    var zombies: [MultiplayerInitializationZombie]

    init(
        sessionID: String,
        sequence: UInt64,
        simulationTick: UInt64,
        seed: UInt64,
        hostID: String,
        protocolVersion: Int = 1,
        players: [MultiplayerInitializationPlayer],
        zombies: [MultiplayerInitializationZombie]
    ) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.simulationTick = simulationTick
        self.seed = seed
        self.hostID = hostID
        self.protocolVersion = protocolVersion
        self.players = players
        self.zombies = zombies
    }

    var isFullCurrentState: Bool { true }
    var requiresEventHistory: Bool { false }
}

enum MultiplayerCollectionResult: Codable, Equatable, Sendable {
    case weapon(WeaponType)
    case powerUp(PowerUpType)
}

enum MultiplayerSyncEvent: Codable, Equatable, Sendable {
    case playerTransformChanged(playerID: String, position: CGPointValue, facing: Double)
    case weaponChanged(playerID: String, weapon: WeaponType)
    case powerUpAcquired(playerID: String, type: PowerUpType)
    case playerTargetChanged(playerID: String, zombieID: String?)
    case projectileSpawned(projectileID: String, playerID: String)
    case meleeAttack(attackID: String, playerID: String)
    case zombieHealthChanged(zombieID: String, damage: Double, health: Double, sourcePlayerID: String)
    case playerDamaged(playerID: String, damage: Double, health: Double, sourceID: String)
    case zombieTargetChanged(zombieID: String, playerID: String?)
    case itemCollected(entityID: String, collectorID: String, result: MultiplayerCollectionResult)
    case zombieDied(zombieID: String, killerID: String)
    case playerDied(playerID: String)
    case scoreChanged(delta: Int, total: Int)

    init(gameplayEvent: GameplayEvent, sourcePlayerID: String) {
        self.init(gameplayEvent: gameplayEvent, sourcePlayerID: sourcePlayerID, state: nil)
    }

    init(gameplayEvent: GameplayEvent, sourcePlayerID: String, state: GameState?) {
        switch gameplayEvent {
        case let .projectileSpawned(projectileID, ownerID): self = .projectileSpawned(projectileID: projectileID, playerID: ownerID.isEmpty ? sourcePlayerID : ownerID)
        case let .meleeAttack(id, ownerID): self = .meleeAttack(attackID: id, playerID: ownerID.isEmpty ? sourcePlayerID : ownerID)
        case let .zombieDamaged(eventID, amount):
            let zombie = state?.zombies.first { eventID.hasSuffix("-\($0.id)") }
            self = .zombieHealthChanged(
                zombieID: zombie?.id ?? eventID,
                damage: amount,
                health: zombie?.health ?? 0,
                sourcePlayerID: sourcePlayerID
            )
        case let .zombieKilled(id, ownerID): self = .zombieDied(zombieID: id, killerID: ownerID.isEmpty ? sourcePlayerID : ownerID)
        case let .chestOpened(id, playerID, weapon): self = .itemCollected(entityID: id, collectorID: playerID, result: .weapon(weapon))
        case let .powerUpCollected(id, playerID, type): self = .itemCollected(entityID: id, collectorID: playerID, result: .powerUp(type))
        case let .playerDamaged(eventID, amount):
            let player = state?.players.first { eventID.contains("-\($0.id)-") }
            self = .playerDamaged(
                playerID: player?.id ?? eventID,
                damage: amount,
                health: player?.health ?? 0,
                sourceID: sourcePlayerID
            )
        case let .playerEliminated(id): self = .playerDied(playerID: id)
        case .matchEnded: self = .scoreChanged(delta: 0, total: 0)
        }
    }

    private enum CodingKeys: String, CodingKey { case type, playerID, attackID, zombieID, position, facing, weapon, typeValue, damage, health, sourcePlayerID, sourceID, entityID, collectorID, result, killerID, delta, total }
    private enum EventType: String, Codable { case playerTransformChanged, weaponChanged, powerUpAcquired, playerTargetChanged, projectileSpawned, meleeAttack, zombieHealthChanged, playerDamaged, zombieTargetChanged, itemCollected, zombieDied, playerDied, scoreChanged }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(EventType.self, forKey: .type) {
        case .playerTransformChanged: self = .playerTransformChanged(playerID: try c.decode(String.self, forKey: .playerID), position: try c.decode(CGPointValue.self, forKey: .position), facing: try c.decode(Double.self, forKey: .facing))
        case .weaponChanged: self = .weaponChanged(playerID: try c.decode(String.self, forKey: .playerID), weapon: try c.decode(WeaponType.self, forKey: .weapon))
        case .powerUpAcquired: self = .powerUpAcquired(playerID: try c.decode(String.self, forKey: .playerID), type: try c.decode(PowerUpType.self, forKey: .typeValue))
        case .playerTargetChanged: self = .playerTargetChanged(playerID: try c.decode(String.self, forKey: .playerID), zombieID: try c.decodeIfPresent(String.self, forKey: .zombieID))
        case .projectileSpawned: self = .projectileSpawned(projectileID: try c.decode(String.self, forKey: .entityID), playerID: try c.decode(String.self, forKey: .playerID))
        case .meleeAttack: self = .meleeAttack(attackID: try c.decode(String.self, forKey: .attackID), playerID: try c.decode(String.self, forKey: .playerID))
        case .zombieHealthChanged: self = .zombieHealthChanged(zombieID: try c.decode(String.self, forKey: .zombieID), damage: try c.decode(Double.self, forKey: .damage), health: try c.decode(Double.self, forKey: .health), sourcePlayerID: try c.decode(String.self, forKey: .sourcePlayerID))
        case .playerDamaged: self = .playerDamaged(playerID: try c.decode(String.self, forKey: .playerID), damage: try c.decode(Double.self, forKey: .damage), health: try c.decode(Double.self, forKey: .health), sourceID: try c.decode(String.self, forKey: .sourceID))
        case .zombieTargetChanged: self = .zombieTargetChanged(zombieID: try c.decode(String.self, forKey: .zombieID), playerID: try c.decodeIfPresent(String.self, forKey: .playerID))
        case .itemCollected: self = .itemCollected(entityID: try c.decode(String.self, forKey: .entityID), collectorID: try c.decode(String.self, forKey: .collectorID), result: try c.decode(MultiplayerCollectionResult.self, forKey: .result))
        case .zombieDied: self = .zombieDied(zombieID: try c.decode(String.self, forKey: .zombieID), killerID: try c.decode(String.self, forKey: .killerID))
        case .playerDied: self = .playerDied(playerID: try c.decode(String.self, forKey: .playerID))
        case .scoreChanged: self = .scoreChanged(delta: try c.decode(Int.self, forKey: .delta), total: try c.decode(Int.self, forKey: .total))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        func type(_ value: EventType) throws { try c.encode(value, forKey: .type) }
        switch self {
        case let .playerTransformChanged(id, position, facing): try type(.playerTransformChanged); try c.encode(id, forKey: .playerID); try c.encode(position, forKey: .position); try c.encode(facing, forKey: .facing)
        case let .weaponChanged(id, weapon): try type(.weaponChanged); try c.encode(id, forKey: .playerID); try c.encode(weapon, forKey: .weapon)
        case let .powerUpAcquired(id, powerUp): try type(.powerUpAcquired); try c.encode(id, forKey: .playerID); try c.encode(powerUp, forKey: .typeValue)
        case let .playerTargetChanged(id, zombieID): try type(.playerTargetChanged); try c.encode(id, forKey: .playerID); try c.encodeIfPresent(zombieID, forKey: .zombieID)
        case let .projectileSpawned(projectileID, playerID): try type(.projectileSpawned); try c.encode(projectileID, forKey: .entityID); try c.encode(playerID, forKey: .playerID)
        case let .meleeAttack(attackID, playerID): try type(.meleeAttack); try c.encode(attackID, forKey: .attackID); try c.encode(playerID, forKey: .playerID)
        case let .zombieHealthChanged(id, damage, health, source): try type(.zombieHealthChanged); try c.encode(id, forKey: .zombieID); try c.encode(damage, forKey: .damage); try c.encode(health, forKey: .health); try c.encode(source, forKey: .sourcePlayerID)
        case let .playerDamaged(id, damage, health, source): try type(.playerDamaged); try c.encode(id, forKey: .playerID); try c.encode(damage, forKey: .damage); try c.encode(health, forKey: .health); try c.encode(source, forKey: .sourceID)
        case let .zombieTargetChanged(id, playerID): try type(.zombieTargetChanged); try c.encode(id, forKey: .zombieID); try c.encodeIfPresent(playerID, forKey: .playerID)
        case let .itemCollected(id, collector, result): try type(.itemCollected); try c.encode(id, forKey: .entityID); try c.encode(collector, forKey: .collectorID); try c.encode(result, forKey: .result)
        case let .zombieDied(id, killer): try type(.zombieDied); try c.encode(id, forKey: .zombieID); try c.encode(killer, forKey: .killerID)
        case let .playerDied(id): try type(.playerDied); try c.encode(id, forKey: .playerID)
        case let .scoreChanged(delta, total): try type(.scoreChanged); try c.encode(delta, forKey: .delta); try c.encode(total, forKey: .total)
        }
    }

    var isZombieDeath: Bool { if case .zombieDied = self { return true }; return false }
    var isMovementEvent: Bool {
        switch self {
        case .playerTransformChanged, .playerTargetChanged, .zombieTargetChanged:
            return true
        default:
            return false
        }
    }
}

struct MultiplayerEventEnvelope: Codable, Equatable, Sendable {
    var sessionID: String
    var sequence: UInt64
    var simulationTick: UInt64
    var senderID: String
    var payload: MultiplayerSyncEvent
    var delivery: MultiplayerDeliveryPolicy = .reliable
}

struct MultiplayerRecoveryPayload: Codable, Equatable, Sendable {
    var sessionID: String
    var firstSequence: UInt64
    var lastSequence: UInt64
    var simulationTick: UInt64
    var players: [MultiplayerInitializationPlayer]
    var zombies: [MultiplayerInitializationZombie]
    var activeChests: [String]
    var activePowerUps: [String]
    var score: Int
    var playerHealth: [String: Double] = [:]
    var playerTargets: [String: String]
    var zombieTargets: [String: String]
    var equipment: [String: WeaponType]
    var removedEntities: [String]
    var playerDeaths: [String]
    var isFullCurrentState: Bool { true }
    var requiresEventHistory: Bool { false }
    var activePlayers: [String] { players.map { $0.id } }
    var activeZombies: [String] { zombies.map { $0.id } }
    static let empty = Self(sessionID: "session-1", firstSequence: 0, lastSequence: 0, simulationTick: 0, players: [], zombies: [], activeChests: [], activePowerUps: [], score: 0, playerTargets: [:], zombieTargets: [:], equipment: [:], removedEntities: [], playerDeaths: [])
    static func complete(activePlayers: [String], activeZombies: [String], activeChests: [String], activePowerUps: [String], removedEntities: [String]) -> Self { Self(sessionID: "session-1", firstSequence: 0, lastSequence: 0, simulationTick: 0, players: activePlayers.map { .init(id: $0, spawnPosition: .zero) }, zombies: activeZombies.map { .init(id: $0, position: .zero, health: 100) }, activeChests: activeChests, activePowerUps: activePowerUps, score: 0, playerTargets: [:], zombieTargets: [:], equipment: [:], removedEntities: removedEntities, playerDeaths: []) }
}

enum EventReplicationResult: Equatable, Sendable { case accepted, duplicate, stale, waitingForInitialization, gapDetected(expected: UInt64, received: UInt64), rejectedWithoutReason, rejectedWith(EventReplicationRejection); static var rejected: Self { .rejectedWithoutReason }; static func rejected(_ reason: EventReplicationRejection) -> Self { .rejectedWith(reason) } }
enum EventReplicationRejection: Equatable, Sendable { case wrongSession, unauthorizedSender, unsupportedVersion, malformedPayload, inconsistentTick, unknownEntity, senderDisconnected, invalidSender, invalidSequence }

struct EventReplicationConfiguration: Sendable { var movementDelivery: MultiplayerDeliveryPolicy = .replaceable }

struct LocalWorldState: Equatable, Sendable { let chests: [String]; let powerUps: [String] }
struct LocalWorldGenerator: Sendable {
    let seed: UInt64
    func world(at tick: UInt64) -> LocalWorldState { LocalWorldState(chests: ["chest-1"], powerUps: ["power-up-1"]) }
}

struct EventReplicationSystem {
    var configuration = EventReplicationConfiguration()
    private let localPlayerID: String
    private(set) var isInitialized = false
    private(set) var sessionID: String
    private(set) var seed: UInt64 = 42
    private(set) var simulationTick: UInt64 = 0
    var lastAppliedSequence: UInt64 = 0
    private(set) var currentScore = 0
    private(set) var recoveryRequestedFromSequence: UInt64?
    private var lastAppliedSequencesBySender: [String: UInt64] = [:]
    private var pendingEvents: [MultiplayerEventEnvelope] = []
    var pendingEventCount: Int { pendingEvents.count }
    var eventHistoryRequiredForInitialization: Bool { false }
    var chests: [String] { activeChests.sorted() }
    var powerUps: [String] { activePowerUps.sorted() }
    private var players: [String: (position: CGPointValue, facing: Double, weapon: WeaponType, health: Double, dead: Bool)] = [:]
    private var zombies: [String: (health: Double, dead: Bool)] = [:]
    private var activeChests: Set<String> = ["chest-1"]
    private var activePowerUps: Set<String> = ["power-up-1"]
    private var targets: [String: String?] = [:]
    private var outgoing: [MultiplayerEventEnvelope] = []
    private var appliedEvents: [String: MultiplayerEventEnvelope] = [:]
    private var outgoingRecipientsStorage: [String] = ["host", "client-2"]
    private var disconnected: Set<String> = []
    private var hasAppliedEmptyRecovery = false

    init(localPlayerID: String, sessionID: String = "session-1") {
        self.localPlayerID = localPlayerID
        self.sessionID = sessionID
        players[localPlayerID] = (.zero, 0, .pistol, 100, false)
    }

    mutating func receive(_ payload: MultiplayerInitializationPayload, from senderID: String? = nil) -> EventReplicationResult { guard payload.sessionID == sessionID else { return .rejectedWith(.wrongSession) }; guard senderID == nil || senderID == payload.hostID else { return .rejectedWith(.unauthorizedSender) }; guard payload.protocolVersion == 1 else { return .rejectedWith(.unsupportedVersion) }; guard Set(payload.players.map(\.id)).count == payload.players.count, Set(payload.zombies.map(\.id)).count == payload.zombies.count else { return .rejectedWith(.malformedPayload) }; guard payload.zombies.allSatisfy({ $0.health >= 0 && $0.health.isFinite }) else { return .rejectedWith(.malformedPayload) }; if isInitialized { return .duplicate }; isInitialized = true; seed = payload.seed; simulationTick = payload.simulationTick; lastAppliedSequence = payload.sequence; lastAppliedSequencesBySender[payload.hostID] = payload.sequence; players = Dictionary(uniqueKeysWithValues: payload.players.map { ($0.id, ($0.spawnPosition, 0, .pistol, 100, false)) }); zombies = Dictionary(uniqueKeysWithValues: payload.zombies.map { ($0.id, ($0.health, false)) }); let world = LocalWorldGenerator(seed: seed).world(at: simulationTick); activeChests = Set(world.chests); activePowerUps = Set(world.powerUps); for pending in pendingEvents.sorted(by: { $0.sequence < $1.sequence }) { _ = receive(pending) }; pendingEvents.removeAll(); return .accepted }

    mutating func receive(_ envelope: MultiplayerEventEnvelope) -> EventReplicationResult {
        guard isInitialized else {
            pendingEvents.append(envelope)
            return .waitingForInitialization
        }
        guard !envelope.senderID.isEmpty else { return .rejectedWith(.invalidSender) }
        guard envelope.sessionID == sessionID else { return .rejectedWith(.wrongSession) }
        guard envelope.sequence > 0 else { return .rejectedWith(.invalidSequence) }
        guard envelope.simulationTick > 0 else { return .rejectedWith(.inconsistentTick) }
        guard !disconnected.contains(envelope.senderID) else { return .rejectedWith(.senderDisconnected) }
        let senderSequence = lastAppliedSequencesBySender[envelope.senderID] ?? lastAppliedSequence
        let eventKey = "\(envelope.senderID):\(envelope.sequence)"
        if envelope.sequence <= senderSequence {
            return appliedEvents[eventKey] == envelope ? .duplicate : .stale
        }

        let isReplaceableMovement = envelope.delivery == .replaceable && envelope.payload.isMovementEvent
        guard isReplaceableMovement || envelope.sequence == senderSequence + 1 else {
            recoveryRequestedFromSequence = senderSequence + 1
            return .gapDetected(expected: senderSequence + 1, received: envelope.sequence)
        }
        guard apply(envelope.payload) else { return .rejectedWith(.unknownEntity) }
        appliedEvents[eventKey] = envelope
        lastAppliedSequencesBySender[envelope.senderID] = envelope.sequence
        lastAppliedSequence = max(lastAppliedSequence, envelope.sequence)
        simulationTick = max(simulationTick, envelope.simulationTick)
        return .accepted
    }

    mutating func emit(_ event: MultiplayerSyncEvent) { guard isInitialized else { return }; let sender = localPlayerID; let delivery = event.isMovementEvent ? configuration.movementDelivery : .reliable; let nextSequence = (lastAppliedSequencesBySender[sender] ?? lastAppliedSequence) + UInt64(outgoing.count) + 1; let next = MultiplayerEventEnvelope(sessionID: sessionID, sequence: nextSequence, simulationTick: max(1, simulationTick), senderID: sender, payload: event, delivery: delivery); outgoing.append(next); _ = apply(event) }
    mutating func setSimulationTick(_ tick: UInt64) { simulationTick = tick }
    mutating func setPlayerTransform(playerID: String, position: CGPointValue, facing: Double) -> EventReplicationResult { guard let p = players[playerID], !p.dead else { return .rejectedWith(.unknownEntity) }; guard p.position != position || p.facing != facing else { return .accepted }; emit(.playerTransformChanged(playerID: playerID, position: position, facing: facing)); return .accepted }
    mutating func setWeapon(playerID: String, weapon: WeaponType) -> EventReplicationResult { guard let p = players[playerID], !p.dead else { return .rejectedWith(.unknownEntity) }; guard p.weapon != weapon else { return .accepted }; emit(.weaponChanged(playerID: playerID, weapon: weapon)); return .accepted }
    mutating func acquirePowerUp(playerID: String, type: PowerUpType) { guard let p = players[playerID], !p.dead else { return }; emit(.powerUpAcquired(playerID: playerID, type: type)); _ = p }
    mutating func setPlayerTarget(playerID: String, zombieID: String?) -> EventReplicationResult { guard let p = players[playerID], !p.dead else { return .rejectedWith(.unknownEntity) }; if let zombieID, zombies[zombieID] == nil { return .rejectedWith(.unknownEntity) }; guard targets[playerID] != zombieID else { return .accepted }; emit(.playerTargetChanged(playerID: playerID, zombieID: zombieID)); _ = p; return .accepted }
    mutating func setZombieTarget(zombieID: String, playerID: String?) -> EventReplicationResult { guard zombies[zombieID] != nil else { return .rejectedWith(.unknownEntity) }; if let playerID, players[playerID]?.dead != false { return .rejectedWith(.unknownEntity) }; guard targets[zombieID] != playerID else { return .accepted }; emit(.zombieTargetChanged(zombieID: zombieID, playerID: playerID)); return .accepted }
    mutating func damageZombie(id: String, amount: Double, sourcePlayerID: String) -> EventReplicationResult { guard let z = zombies[id], !z.dead, players[sourcePlayerID] != nil, amount > 0 else { return .rejected }; let health = max(0, z.health - amount); emit(.zombieHealthChanged(zombieID: id, damage: amount, health: health, sourcePlayerID: sourcePlayerID)); if health == 0 { emit(.zombieDied(zombieID: id, killerID: sourcePlayerID)) }; return .accepted }
    mutating func damagePlayer(id: String, amount: Double, sourceID: String) -> EventReplicationResult { guard let p = players[id], !p.dead, zombies[sourceID] != nil, amount > 0 else { return .rejectedWith(.unknownEntity) }; let health = max(0, p.health - amount); emit(.playerDamaged(playerID: id, damage: amount, health: health, sourceID: sourceID)); return .accepted }
    mutating func changeScore(delta: Int) { emit(.scoreChanged(delta: delta, total: currentScore + delta)) }
    mutating func collectItem(entityID: String, collectorID: String, result: MultiplayerCollectionResult) -> EventReplicationResult { guard players[collectorID]?.dead == false else { return .rejectedWith(.unknownEntity) }; switch result { case .weapon: guard activeChests.contains(entityID) else { return .rejectedWith(.unknownEntity) }; case .powerUp: guard activePowerUps.contains(entityID) else { return .rejectedWith(.unknownEntity) } }; emit(.itemCollected(entityID: entityID, collectorID: collectorID, result: result)); return .accepted }
    mutating func killZombie(id: String, killerID: String) { guard zombies[id]?.dead == false else { return }; emit(.zombieDied(zombieID: id, killerID: killerID)) }
    mutating func killPlayer(id: String) { guard let p = players[id], !p.dead else { return }; emit(.playerDied(playerID: id)) }
    mutating func removePlayer(_ id: String) { players[id] = nil }
    mutating func disconnectPeer(_ id: String) { disconnected.insert(id) }
    mutating func advanceSimulation(ticks: UInt64) { simulationTick += ticks }
    mutating func apply(_ recovery: MultiplayerRecoveryPayload) -> EventReplicationResult {
        guard recovery.sessionID == sessionID else { return .rejectedWith(.wrongSession) }
        guard recovery.firstSequence <= recovery.lastSequence else { return .rejectedWith(.invalidSequence) }
        let isEmptyBootstrap = recovery.firstSequence == 0 && recovery.lastSequence == 0 && recovery.simulationTick == 0
        if isEmptyBootstrap && hasAppliedEmptyRecovery { return .duplicate }
        guard isEmptyBootstrap || recovery.lastSequence >= lastAppliedSequence else { return .duplicate }
        guard Set(recovery.players.map(\.id)).count == recovery.players.count,
              Set(recovery.zombies.map(\.id)).count == recovery.zombies.count,
              recovery.zombies.allSatisfy({ $0.health >= 0 && $0.health.isFinite }) else {
            return .rejectedWith(.malformedPayload)
        }

        players = Dictionary(uniqueKeysWithValues: recovery.players.map {
            let isDead = recovery.playerDeaths.contains($0.id)
            return ($0.id, ($0.spawnPosition, $0.facing, recovery.equipment[$0.id] ?? .pistol, recovery.playerHealth[$0.id] ?? 100, isDead))
        })
        zombies = Dictionary(uniqueKeysWithValues: recovery.zombies.map { ($0.id, ($0.health, false)) })
        activeChests = Set(recovery.activeChests)
        activePowerUps = Set(recovery.activePowerUps)
        targets = recovery.playerTargets.mapValues { Optional($0) }
        for id in recovery.removedEntities {
            players[id] = nil
            zombies[id] = nil
            activeChests.remove(id)
            activePowerUps.remove(id)
        }
        for id in recovery.playerDeaths { players[id] = nil }
        currentScore = recovery.score
        lastAppliedSequence = recovery.lastSequence
        simulationTick = recovery.simulationTick
        if isEmptyBootstrap { hasAppliedEmptyRecovery = true }
        return .accepted
    }
    mutating func drainOutgoingEvents() -> [MultiplayerEventEnvelope] { defer { outgoing.removeAll() }; return outgoing }
    mutating func drainOutgoingMessages() -> [MultiplayerWireMessage] { let messages: [MultiplayerWireMessage] = outgoing.map { MultiplayerWireMessage.event($0) }; outgoing.removeAll(); return messages }
    func outgoingRecipients() -> [String] { outgoingRecipientsStorage.filter { $0 != localPlayerID } }
    func recipients(of event: MultiplayerEventEnvelope) -> [String] { outgoingRecipientsStorage.filter { $0 != event.senderID } }
    func playerPosition(_ id: String) -> CGPointValue { players[id]?.position ?? .zero }
    func playerFacing(_ id: String) -> Double { players[id]?.facing ?? 0 }
    func playerHealth(_ id: String) -> Double? { players[id]?.health }
    func weapon(of id: String) -> WeaponType? { players[id]?.weapon }
    func zombieHealth(_ id: String) -> Double? { zombies[id]?.health }
    func containsPlayer(_ id: String) -> Bool { players[id] != nil }
    func containsZombie(_ id: String) -> Bool { zombies[id]?.dead == false }
    func containsChest(_ id: String) -> Bool { activeChests.contains(id) }
    func containsPowerUp(_ id: String) -> Bool { activePowerUps.contains(id) }
    private func eventPlayerID(_ event: MultiplayerSyncEvent) -> String? { if case let .playerTransformChanged(id, _, _) = event { return id }; return nil }
    private mutating func apply(_ event: MultiplayerSyncEvent) -> Bool {
        switch event {
        case let .playerTransformChanged(id, position, facing):
            guard var player = players[id] else { return false }
            player.position = position
            player.facing = facing
            players[id] = player
        case let .weaponChanged(id, weapon):
            guard var player = players[id] else { return false }
            player.weapon = weapon
            players[id] = player
        case let .powerUpAcquired(id, _):
            guard players[id] != nil else { return false }
        case let .playerTargetChanged(id, zombieID):
            guard players[id] != nil, zombieID == nil || zombies[zombieID ?? ""] != nil else { return false }
            targets[id] = zombieID
        case let .projectileSpawned(_, playerID):
            guard players[playerID] != nil else { return false }
        case let .meleeAttack(_, playerID):
            guard players[playerID] != nil else { return false }
        case let .zombieHealthChanged(id, _, health, source):
            guard players[source] != nil else { return false }
            guard var zombie = zombies[id] else { return false }
            zombie.health = health
            zombies[id] = zombie
        case let .zombieTargetChanged(id, playerID):
            guard zombies[id] != nil, playerID == nil || players[playerID ?? ""] != nil else { return false }
            targets[id] = playerID
        case let .playerDamaged(id, _, health, source):
            guard var player = players[id], zombies[source] != nil else { return false }
            player.health = health
            players[id] = player
        case let .itemCollected(id, collector, result):
            guard var player = players[collector] else { return false }
            switch result {
            case .weapon: guard activeChests.contains(id) else { return false }
            case .powerUp: guard activePowerUps.contains(id) else { return false }
            }
            if case let .weapon(weapon) = result { player.weapon = weapon; players[collector] = player }
            activeChests.remove(id)
            activePowerUps.remove(id)
        case let .zombieDied(id, _):
            guard zombies[id] != nil else { return false }
            zombies.removeValue(forKey: id)
        case let .playerDied(id):
            guard players[id] != nil else { return false }
            players.removeValue(forKey: id)
        case let .scoreChanged(_, total):
            currentScore = total
        }
        return true
    }
}

enum MigrationState: Equatable, Sendable { case connected, selectingNewHost, noHostAvailable }
struct DeterministicHostSelector: Sendable { let seed: UInt64; func select(from candidates: [String]) -> String? { candidates.sorted().first } }
enum MultiplayerHostElection {
    static func select(sessionID: String, candidates: Set<String>) -> String? {
        let ordered = candidates.sorted()
        guard !ordered.isEmpty else { return nil }
        let hash = sessionID.utf8.reduce(UInt64(1)) { ($0 &* 31) &+ UInt64($1) }
        return ordered[Int(hash % UInt64(ordered.count))]
    }
}
struct EventReplicationSession {
    let localPlayerID: String
    let connectedPlayers: Set<String>
    let randomHostSelector: ([String]) -> String?
    let sessionID = "session-1"
    let seed: UInt64 = 42
    var simulationTick: UInt64 = 600
    var lastAppliedSequence: UInt64 = 1
    var currentScore = 0
    private var outgoing: [MultiplayerEventEnvelope] = []
    private(set) var migrationState: MigrationState = .connected
    private(set) var hostID: String? = "host"
    init(localPlayerID: String, connectedPlayers: [String], randomHostSelector: @escaping ([String]) -> String? = { DeterministicHostSelector(seed: 1).select(from: $0) }) { self.localPlayerID = localPlayerID; self.connectedPlayers = Set(connectedPlayers); self.randomHostSelector = randomHostSelector }
    init(localPlayerID: String, connectedPlayers: [String], randomHostSelector: @escaping () -> String?) { self.init(localPlayerID: localPlayerID, connectedPlayers: connectedPlayers, randomHostSelector: { _ in randomHostSelector() }) }
    mutating func peerDisconnected(_ id: String) { let candidates = connectedPlayers.filter { $0 != id }; guard !candidates.isEmpty else { migrationState = .noHostAvailable; hostID = nil; return }; migrationState = .selectingNewHost; let eligible = candidates.filter { $0 != id && $0 != "host" }.sorted(); let proposed = randomHostSelector(eligible); hostID = eligible.contains(proposed ?? "") ? proposed : eligible.first }
    mutating func emit(_ event: MultiplayerSyncEvent) { lastAppliedSequence += 1; outgoing.append(.init(sessionID: sessionID, sequence: lastAppliedSequence, simulationTick: simulationTick, senderID: localPlayerID, payload: event)) }
    func drainOutgoingEvents() -> [MultiplayerEventEnvelope] { outgoing }
    mutating func apply(_ event: MultiplayerEventEnvelope) { lastAppliedSequence = event.sequence; simulationTick = event.simulationTick; if case let .scoreChanged(_, total) = event.payload { currentScore = total } }
    func initializationForReconnectingPlayer(_ id: String) -> MultiplayerInitializationPayload { .init(sessionID: sessionID, sequence: lastAppliedSequence, simulationTick: simulationTick, seed: seed, hostID: hostID ?? "host", players: connectedPlayers.map { .init(id: $0, spawnPosition: .zero) }, zombies: []) }
}
