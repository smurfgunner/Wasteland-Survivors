import Foundation
import CoreGraphics
#if canImport(SpriteKit)
import SpriteKit
#endif
#if canImport(MultipeerConnectivity)
import MultipeerConnectivity
#endif

enum MultiplayerPlayerColor: Int, CaseIterable, Codable, Sendable {
    case blue
    case red
    case green
    case purple

    #if canImport(SpriteKit)
    var spriteColor: SKColor {
        switch self {
        case .blue: return SKColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        case .red: return .systemRed
        case .green: return .systemGreen
        case .purple: return .systemPurple
        }
    }
    #endif
}

struct MultiplayerPlayerState: Codable, Equatable, Sendable {
    let id: String
    let x: Double
    let y: Double
    let color: MultiplayerPlayerColor
    let health: Double
    let weapon: WeaponType
    let powerUps: [PowerUpType]
    let rotation: Double
    let sessionStartedAt: Double

    init(id: String, position: CGPoint, color: MultiplayerPlayerColor, health: CGFloat = 100, weapon: WeaponType = .pistol, powerUps: [PowerUpType] = [], rotation: CGFloat = 0, sessionStartedAt: TimeInterval = 0) {
        self.id = id
        x = Double(position.x)
        y = Double(position.y)
        self.color = color
        self.health = Double(health)
        self.weapon = weapon
        self.powerUps = powerUps
        self.rotation = Double(rotation)
        self.sessionStartedAt = sessionStartedAt
    }

    var position: CGPoint {
        CGPoint(x: x, y: y)
    }

    var rotationAngle: CGFloat { CGFloat(rotation) }
}

enum MultiplayerHostSelector {
    static func hostID(for players: [MultiplayerPlayerState]) -> String? {
        players.min {
            if $0.sessionStartedAt == $1.sessionStartedAt { return $0.id < $1.id }
            return $0.sessionStartedAt < $1.sessionStartedAt
        }?.id
    }
}

struct MultiplayerZombieState: Codable, Equatable, Sendable {
    let id: String
    let x: Double
    let y: Double
    let health: Double
    let rotation: Double
}

struct MultiplayerChestState: Codable, Equatable, Sendable {
    let id: String
    let x: Double
    let y: Double
    let isOpened: Bool

    init(id: String, x: Double, y: Double, isOpened: Bool = false) {
        self.id = id
        self.x = x
        self.y = y
        self.isOpened = isOpened
    }
}

struct MultiplayerPowerUpState: Codable, Equatable, Sendable {
    let id: String
    let x: Double
    let y: Double
    let type: PowerUpType
}

struct MultiplayerProjectileState: Codable, Equatable, Sendable {
    let id: String
    let ownerID: String
    let x: Double
    let y: Double
    let angle: Double
    let weapon: WeaponType
    let damage: Double
    let spawnedTick: UInt64

    init(id: String, ownerID: String = "", x: Double, y: Double, angle: Double, weapon: WeaponType, damage: Double, spawnedTick: UInt64 = 0) {
        self.id = id
        self.ownerID = ownerID
        self.x = x
        self.y = y
        self.angle = angle
        self.weapon = weapon
        self.damage = damage
        self.spawnedTick = spawnedTick
    }
}

struct MultiplayerBoardState: Codable, Equatable, Sendable {
    let sequence: UInt64
    let simulationTick: UInt64
    let seed: UInt64
    let timestamp: TimeInterval
    let serverTime: TimeInterval
    let hostID: String
    var stateHash: UInt64
    let players: [MultiplayerPlayerState]
    let zombies: [MultiplayerZombieState]
    let chests: [MultiplayerChestState]
    let powerUps: [MultiplayerPowerUpState]
    let projectiles: [MultiplayerProjectileState]
    let killCount: Int
    let isGameOver: Bool
    let acknowledgedInputSequences: [String: UInt64]
    let lastAttackTickByPlayer: [String: UInt64]
    let lastDamageTickByPlayer: [String: UInt64]

    init(sequence: UInt64 = 0, simulationTick: UInt64 = 0, seed: UInt64 = 0, timestamp: TimeInterval = 0, serverTime: TimeInterval = 0, hostID: String, stateHash: UInt64 = 0, players: [MultiplayerPlayerState], zombies: [MultiplayerZombieState], chests: [MultiplayerChestState], powerUps: [MultiplayerPowerUpState], projectiles: [MultiplayerProjectileState], killCount: Int, isGameOver: Bool = false, acknowledgedInputSequences: [String: UInt64] = [:], lastAttackTickByPlayer: [String: UInt64] = [:], lastDamageTickByPlayer: [String: UInt64] = [:]) {
        self.sequence = sequence
        self.simulationTick = simulationTick
        self.seed = seed
        self.timestamp = timestamp
        self.serverTime = serverTime
        self.hostID = hostID
        self.stateHash = stateHash
        self.players = players
        self.zombies = zombies
        self.chests = chests
        self.powerUps = powerUps
        self.projectiles = projectiles
        self.killCount = killCount
        self.isGameOver = isGameOver
        self.acknowledgedInputSequences = acknowledgedInputSequences
        self.lastAttackTickByPlayer = lastAttackTickByPlayer
        self.lastDamageTickByPlayer = lastDamageTickByPlayer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequence = try container.decodeIfPresent(UInt64.self, forKey: .sequence) ?? 0
        simulationTick = try container.decodeIfPresent(UInt64.self, forKey: .simulationTick) ?? 0
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed) ?? 0
        timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timestamp) ?? 0
        serverTime = try container.decodeIfPresent(TimeInterval.self, forKey: .serverTime) ?? timestamp
        hostID = try container.decode(String.self, forKey: .hostID)
        stateHash = try container.decodeIfPresent(UInt64.self, forKey: .stateHash) ?? 0
        players = try container.decode([MultiplayerPlayerState].self, forKey: .players)
        zombies = try container.decode([MultiplayerZombieState].self, forKey: .zombies)
        chests = try container.decode([MultiplayerChestState].self, forKey: .chests)
        powerUps = try container.decode([MultiplayerPowerUpState].self, forKey: .powerUps)
        projectiles = try container.decode([MultiplayerProjectileState].self, forKey: .projectiles)
        killCount = try container.decode(Int.self, forKey: .killCount)
        isGameOver = try container.decodeIfPresent(Bool.self, forKey: .isGameOver) ?? false
        acknowledgedInputSequences = try container.decodeIfPresent([String: UInt64].self, forKey: .acknowledgedInputSequences) ?? [:]
        lastAttackTickByPlayer = try container.decodeIfPresent([String: UInt64].self, forKey: .lastAttackTickByPlayer) ?? [:]
        lastDamageTickByPlayer = try container.decodeIfPresent([String: UInt64].self, forKey: .lastDamageTickByPlayer) ?? [:]
    }

    func validate(expectedHostID: String? = nil) throws {
        guard !hostID.isEmpty, expectedHostID.map({ hostID == $0 }) ?? true,
              killCount >= 0,
              players.allSatisfy({
                  !$0.id.isEmpty && $0.x.isFinite && $0.y.isFinite &&
                  $0.health.isFinite && $0.health >= 0 && $0.rotation.isFinite
              }),
              zombies.allSatisfy({
                  !$0.id.isEmpty && $0.x.isFinite && $0.y.isFinite &&
                  $0.health.isFinite && $0.health >= 0 && $0.rotation.isFinite
              }),
              chests.allSatisfy({
                  !$0.id.isEmpty && $0.x.isFinite && $0.y.isFinite
              }),
              powerUps.allSatisfy({
                  !$0.id.isEmpty && $0.x.isFinite && $0.y.isFinite
              }),
              projectiles.allSatisfy({
                  !$0.id.isEmpty && !$0.ownerID.isEmpty && $0.x.isFinite && $0.y.isFinite &&
                  $0.angle.isFinite && $0.damage.isFinite && $0.damage > 0
              }),
              acknowledgedInputSequences.keys.allSatisfy({ acknowledgedID in
                  !acknowledgedID.isEmpty && players.contains(where: { player in player.id == acknowledgedID })
              }) else {
            throw ReplicationError.malformedPayload
        }
        if stateHash != 0, stateHash != contentHash {
            throw ReplicationError.inconsistentState
        }
    }

    /// Hashes the complete wire representation without the hash field itself.
    /// This permits clients to detect tampering or partial snapshots without
    /// needing private simulation-only bookkeeping such as cooldown maps.
    var contentHash: UInt64 {
        var canonical = self
        canonical.stateHash = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(canonical) else { return 0 }
        return ReplicationStateHasher.hash(data)
    }

    static func empty(hostID: String, sequence: UInt64) -> Self {
        Self(sequence: sequence, timestamp: 0, hostID: hostID, players: [], zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0)
    }
}

extension MultiplayerWireMessage {
    var deliveryPolicy: MultiplayerDeliveryPolicy {
        switch self {
        case .playerUpdate, .boardSnapshot:
            return .replaceable
        case .playerInput, .gameplayEvent, .hello, .hostAnnouncement, .joinRequest, .joinAccepted:
            return .reliable
        }
    }
}

struct MultiplayerPlayerInput: Codable, Equatable, Sendable {
    let playerID: String
    let sequence: UInt64
    let movementX: Double
    let movementY: Double
    let aimAngle: Double
    let wantsToAttack: Bool
    let wantsToOpenChestID: String?
    let wantsToCollectPowerUpID: String?

    init(
        playerID: String,
        sequence: UInt64,
        movement: CGVector,
        aimAngle: CGFloat,
        wantsToAttack: Bool,
        wantsToOpenChestID: String? = nil,
        wantsToCollectPowerUpID: String? = nil
    ) {
        self.playerID = playerID
        self.sequence = sequence
        movementX = Double(movement.dx)
        movementY = Double(movement.dy)
        self.aimAngle = Double(aimAngle)
        self.wantsToAttack = wantsToAttack
        self.wantsToOpenChestID = wantsToOpenChestID
        self.wantsToCollectPowerUpID = wantsToCollectPowerUpID
    }

    var movement: CGVector { CGVector(dx: movementX, dy: movementY) }
}

struct MultiplayerGameplayEvent: Codable, Equatable, Sendable {
    let event: GameplayEvent
    let sessionID: String
    let sequence: UInt64
    let tick: UInt64
    let hostID: String

    init(event: GameplayEvent, sessionID: String, sequence: UInt64, tick: UInt64, hostID: String) {
        self.event = event
        self.sessionID = sessionID
        self.sequence = sequence
        self.tick = tick
        self.hostID = hostID
    }

    func validate(expectedHostID: String, expectedSessionID: String? = nil) throws {
        guard sequence > 0, tick > 0 else {
            throw ReplicationError.malformedPayload
        }
        guard !sessionID.isEmpty, !hostID.isEmpty, hostID == expectedHostID, !event.id.isEmpty,
              expectedSessionID.map({ sessionID == $0 }) ?? true else {
            throw ReplicationError.unauthorizedOwner
        }
        switch event {
        case let .projectileSpawned(id, ownerID), let .meleeAttack(id, ownerID), let .zombieKilled(id, ownerID):
            guard !id.isEmpty, !ownerID.isEmpty else { throw ReplicationError.malformedPayload }
        case let .zombieDamaged(id, amount), let .playerDamaged(id, amount):
            guard !id.isEmpty, amount.isFinite, amount > 0 else { throw ReplicationError.malformedPayload }
        case let .chestOpened(id, playerID, _), let .powerUpCollected(id, playerID, _):
            guard !id.isEmpty, !playerID.isEmpty else { throw ReplicationError.malformedPayload }
        case let .playerEliminated(id):
            guard !id.isEmpty else { throw ReplicationError.malformedPayload }
        case .matchEnded:
            break
        }
    }
}

struct MultiplayerSnapshotBuffer {
    private(set) var snapshots: [MultiplayerBoardState] = []
    let capacity: Int

    var latest: MultiplayerBoardState? {
        snapshots.last
    }

    init(capacity: Int = 32) {
        self.capacity = max(2, capacity)
    }

    mutating func append(_ snapshot: MultiplayerBoardState) -> Bool {
        guard !snapshots.contains(where: { $0.sequence == snapshot.sequence }),
              snapshots.first.map({ snapshot.sequence > $0.sequence }) ?? true else { return false }

        snapshots.append(snapshot)
        snapshots.sort { $0.sequence < $1.sequence }
        if snapshots.count > capacity {
            snapshots.removeFirst(snapshots.count - capacity)
        }
        return true
    }

    func surrounding(tick: UInt64) -> (before: MultiplayerBoardState, after: MultiplayerBoardState)? {
        let snapshotsByTick = snapshots.sorted {
            if $0.simulationTick == $1.simulationTick {
                return $0.sequence < $1.sequence
            }
            return $0.simulationTick < $1.simulationTick
        }
        guard let afterIndex = snapshotsByTick.firstIndex(where: { $0.simulationTick >= tick }),
              afterIndex > 0 else {
            return nil
        }
        return (snapshotsByTick[afterIndex - 1], snapshotsByTick[afterIndex])
    }

    func position(
        for entityID: String,
        renderTick: UInt64,
        delayTicks: UInt64,
        maxExtrapolationTicks: UInt64
    ) -> CGPoint? {
        guard !snapshots.isEmpty else { return nil }
        let targetTick = renderTick > delayTicks ? renderTick - delayTicks : 0
        let ordered = snapshots.sorted {
            if $0.simulationTick == $1.simulationTick { return $0.sequence < $1.sequence }
            return $0.simulationTick < $1.simulationTick
        }
        func point(in snapshot: MultiplayerBoardState) -> CGPoint? {
            if let player = snapshot.players.first(where: { $0.id == entityID }) { return player.position }
            if let zombie = snapshot.zombies.first(where: { $0.id == entityID }) { return CGPoint(x: zombie.x, y: zombie.y) }
            if let chest = snapshot.chests.first(where: { $0.id == entityID }) { return CGPoint(x: chest.x, y: chest.y) }
            if let powerUp = snapshot.powerUps.first(where: { $0.id == entityID }) { return CGPoint(x: powerUp.x, y: powerUp.y) }
            return nil
        }
        guard let first = ordered.first, let firstPoint = point(in: first) else { return nil }
        if targetTick <= first.simulationTick { return firstPoint }
        if let afterIndex = ordered.firstIndex(where: { $0.simulationTick >= targetTick }) {
            guard afterIndex > 0, let beforePoint = point(in: ordered[afterIndex - 1]), let afterPoint = point(in: ordered[afterIndex]) else {
                return point(in: ordered[afterIndex])
            }
            let beforeTick = ordered[afterIndex - 1].simulationTick
            let span = max(1, ordered[afterIndex].simulationTick - beforeTick)
            let factor = CGFloat(targetTick - beforeTick) / CGFloat(span)
            return CGPoint(
                x: beforePoint.x + (afterPoint.x - beforePoint.x) * factor,
                y: beforePoint.y + (afterPoint.y - beforePoint.y) * factor
            )
        }
        guard let latest = ordered.last, let latestPoint = point(in: latest), ordered.count >= 2,
              let previousPoint = point(in: ordered[ordered.count - 2]) else { return firstPoint }
        let previous = ordered[ordered.count - 2]
        let span = max(1, latest.simulationTick - previous.simulationTick)
        let extrapolation = min(maxExtrapolationTicks, targetTick - latest.simulationTick)
        let factor = CGFloat(extrapolation) / CGFloat(span)
        return CGPoint(
            x: latestPoint.x + (latestPoint.x - previousPoint.x) * factor,
            y: latestPoint.y + (latestPoint.y - previousPoint.y) * factor
        )
    }
}

enum MultiplayerWireMessage: Codable, Equatable, Sendable {
    case hello(MultiplayerHello)
    case hostAnnouncement(MultiplayerHostAnnouncement)
    case joinRequest(MultiplayerJoinRequest)
    case joinAccepted(MultiplayerJoinAccepted)
    case playerUpdate(MultiplayerPlayerState)
    case boardSnapshot(MultiplayerBoardState)
    case playerInput(MultiplayerPlayerInput)
    case gameplayEvent(MultiplayerGameplayEvent)

    private enum CodingKeys: String, CodingKey {
        case type
        case hello
        case announcement
        case request
        case accepted
        case player
        case board
        case input
        case gameplayEvent
    }

    private enum MessageType: String, Codable {
        case hello
        case hostAnnouncement
        case joinRequest
        case joinAccepted
        case playerUpdate
        case boardSnapshot
        case playerInput
        case gameplayEvent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .hello:
            self = .hello(try container.decode(MultiplayerHello.self, forKey: .hello))
        case .hostAnnouncement:
            self = .hostAnnouncement(try container.decode(MultiplayerHostAnnouncement.self, forKey: .announcement))
        case .joinRequest:
            self = .joinRequest(try container.decode(MultiplayerJoinRequest.self, forKey: .request))
        case .joinAccepted:
            self = .joinAccepted(try container.decode(MultiplayerJoinAccepted.self, forKey: .accepted))
        case .playerUpdate:
            self = .playerUpdate(try container.decode(MultiplayerPlayerState.self, forKey: .player))
        case .boardSnapshot:
            self = .boardSnapshot(try container.decode(MultiplayerBoardState.self, forKey: .board))
        case .playerInput:
            self = .playerInput(try container.decode(MultiplayerPlayerInput.self, forKey: .input))
        case .gameplayEvent:
            self = .gameplayEvent(try container.decode(MultiplayerGameplayEvent.self, forKey: .gameplayEvent))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .hello(message):
            try container.encode(MessageType.hello, forKey: .type)
            try container.encode(message, forKey: .hello)
        case let .hostAnnouncement(message):
            try container.encode(MessageType.hostAnnouncement, forKey: .type)
            try container.encode(message, forKey: .announcement)
        case let .joinRequest(message):
            try container.encode(MessageType.joinRequest, forKey: .type)
            try container.encode(message, forKey: .request)
        case let .joinAccepted(message):
            try container.encode(MessageType.joinAccepted, forKey: .type)
            try container.encode(message, forKey: .accepted)
        case let .playerUpdate(player):
            try container.encode(MessageType.playerUpdate, forKey: .type)
            try container.encode(player, forKey: .player)
        case let .boardSnapshot(board):
            try container.encode(MessageType.boardSnapshot, forKey: .type)
            try container.encode(board, forKey: .board)
        case let .playerInput(input):
            try container.encode(MessageType.playerInput, forKey: .type)
            try container.encode(input, forKey: .input)
        case let .gameplayEvent(event):
            try container.encode(MessageType.gameplayEvent, forKey: .type)
            try container.encode(event, forKey: .gameplayEvent)
        }
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

enum MultiplayerSpawnPlanner {
    static let spawnRadius: CGFloat = 90

    static func color(localID: String, remoteID: String) -> MultiplayerPlayerColor {
        localID < remoteID ? .blue : .red
    }

    static func position(forPlayerIndex index: Int, hostPosition: CGPoint) -> CGPoint {
        let angle = CGFloat(index) * (.pi / 2)
        return CGPoint(
            x: hostPosition.x + cos(angle) * spawnRadius,
            y: hostPosition.y + sin(angle) * spawnRadius
        )
    }
}

#if canImport(MultipeerConnectivity)
final class MultipeerConnectivitySession: NSObject, MultiplayerTransport {
    weak var delegate: MultiplayerTransportDelegate?
    let localPeerID: String
    let sessionStartedAt: TimeInterval
    var peerDisplayName: String { peerID.displayName }
    private(set) var state: MultiplayerTransportState = .idle
    var connectedPeerIDs: Set<String> {
        appleAdapter?.connectedPeerIDs ?? Set(session?.connectedPeers.map(\.displayName) ?? [])
    }

    private let serviceType = "wasteland-surv"
    private let peerID: MCPeerID
    private let appleAdapter: AppleMultipeerConnectivityAdapter?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var isDisconnecting = false
    var diagnosticHandler: ((String) -> Void)?

    private func diagnostic(_ message: String) {
        print("[Multiplayer] \(message)")
        diagnosticHandler?(message)
    }

    init(playerName: String = "Wasteland Player") {
        localPeerID = UUID().uuidString
        sessionStartedAt = Date().timeIntervalSince1970
        peerID = MCPeerID(displayName: localPeerID)
        appleAdapter = nil
        super.init()
    }

    init(adapter: AppleMultipeerConnectivityAdapter) {
        localPeerID = adapter.localPeerID
        sessionStartedAt = adapter.sessionStartedAt
        peerID = MCPeerID(displayName: adapter.localPeerID)
        appleAdapter = adapter
        super.init()
        adapter.delegate = self
    }

    func connect() {
        diagnostic("connecting localPeerID=\(localPeerID)")
        if let appleAdapter {
            diagnostic("using injected Apple Multipeer Connectivity adapter")
            appleAdapter.delegate = self
            appleAdapter.connect()
            return
        }
        isDisconnecting = false
        state = .connecting
        diagnostic("transport state=connecting")
        delegate?.transport(self, didChange: state)
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        diagnostic("MCSession created encryption=required")

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["game": "wasteland-survivors"],
            serviceType: serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        diagnostic("advertising started serviceType=\(serviceType)")

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        diagnostic("browsing started serviceType=\(serviceType)")
    }

    func disconnect() {
        diagnostic("disconnecting localPeerID=\(localPeerID)")
        if let appleAdapter {
            appleAdapter.disconnect()
            return
        }
        isDisconnecting = true
        diagnostic("disconnect requested")
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        state = .disconnected
        delegate?.transport(self, didChange: state)
    }

    func send(_ data: Data, to peerID: String) throws {
        try send(data, to: peerID, delivery: .reliable)
    }

    func send(_ data: Data, to peerID: String, delivery: MultiplayerDeliveryPolicy) throws {
        diagnostic("sending bytes=\(data.count) to=\(peerID) delivery=\(delivery)")
        if let appleAdapter {
            try appleAdapter.send(data, to: peerID, delivery: delivery)
            return
        }
        guard state == .connected else {
            diagnostic("send skipped reason=notConnected state=\(state) peer=\(peerID)")
            throw MultiplayerTransportError.notConnected
        }
        guard let session,
              let peer = session.connectedPeers.first(where: { $0.displayName == peerID }) else {
            diagnostic("send skipped reason=peerUnavailable peer=\(peerID) connectedPeers=\(connectedPeerIDs.sorted())")
            throw MultiplayerTransportError.peerUnavailable
        }
        let mode: MCSessionSendDataMode = delivery == .reliable ? .reliable : .unreliable
        try session.send(data, toPeers: [peer], with: mode)
        diagnostic("send completed to=\(peerID)")
    }

    func broadcast(_ data: Data) throws {
        try broadcast(data, delivery: .reliable)
    }

    func broadcast(_ data: Data, delivery: MultiplayerDeliveryPolicy) throws {
        diagnostic("broadcasting bytes=\(data.count) delivery=\(delivery)")
        if let appleAdapter {
            try appleAdapter.broadcast(data, delivery: delivery)
            return
        }
        guard state == .connected else {
            diagnostic("broadcast skipped reason=notConnected state=\(state)")
            throw MultiplayerTransportError.notConnected
        }
        guard let session, !session.connectedPeers.isEmpty else {
            diagnostic("broadcast skipped reason=peerUnavailable connectedPeers=\(connectedPeerIDs.sorted())")
            throw MultiplayerTransportError.peerUnavailable
        }
        let mode: MCSessionSendDataMode = delivery == .reliable ? .reliable : .unreliable
        try session.send(data, toPeers: session.connectedPeers, with: mode)
        diagnostic("broadcast completed peers=\(session.connectedPeers.map(\.displayName).sorted())")
    }
}

extension MultipeerConnectivitySession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        diagnostic("invitation received from peer=\(peerID.displayName) hasSession=\(session != nil)")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        diagnostic("advertising failed error=\(error.localizedDescription)")
    }
}

extension MultipeerConnectivitySession: MCNearbyServiceBrowserDelegate {
    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        diagnostic("peer discovered peer=\(peerID.displayName) info=\(info ?? [:]) hasSession=\(session != nil)")
        guard peerID != self.peerID, let session else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        diagnostic("invitation sent to peer=\(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        diagnostic("browsing failed error=\(error.localizedDescription)")
    }
}

extension MultipeerConnectivitySession: AppleMultipeerConnectivityAdapterDelegate {
    func appleAdapter(_ adapter: AppleMultipeerConnectivityAdapter, didChange state: MultiplayerTransportState) {
        guard adapter === appleAdapter else { return }
        self.state = state
        diagnostic("state=\(state)")
        delegate?.transport(self, didChange: state)
    }

    func appleAdapter(_ adapter: AppleMultipeerConnectivityAdapter, didChangePeer peerID: String, state: MultiplayerPeerState) {
        guard adapter === appleAdapter else { return }
        diagnostic("peer=\(peerID) state=\(state)")
        delegate?.transport(self, didChangePeer: peerID, state: state)
    }

    func appleAdapter(_ adapter: AppleMultipeerConnectivityAdapter, didReceive data: Data, from peerID: String) {
        guard adapter === appleAdapter else { return }
        diagnostic("received bytes=\(data.count) from=\(peerID)")
        delegate?.transport(self, didReceive: data, from: peerID)
    }
}

extension MultipeerConnectivitySession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard self.session === session else { return }
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.session(session, peer: peerID, didChange: state)
            }
            return
        }
        guard !isDisconnecting else { return }

        switch state {
        case .connected:
            self.state = .connected
            diagnostic("peer=\(peerID.displayName) state=connected")
            delegate?.transport(self, didChangePeer: peerID.displayName, state: .connected)
        case .connecting:
            self.state = .connecting
        case .notConnected:
            self.state = session.connectedPeers.isEmpty ? .connecting : .connected
            diagnostic("peer=\(peerID.displayName) state=disconnected")
            delegate?.transport(self, didChangePeer: peerID.displayName, state: .disconnected)
        @unknown default:
            self.state = .failed
        }
        diagnostic("state=\(self.state)")
        delegate?.transport(self, didChange: self.state)
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard self.session === session else { return }
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.session(session, didReceive: data, fromPeer: peerID)
            }
            return
        }
        guard !isDisconnecting else { return }
        diagnostic("received bytes=\(data.count) from=\(peerID.displayName)")
        delegate?.transport(self, didReceive: data, from: peerID.displayName)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
#endif
