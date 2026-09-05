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

enum MultiplayerSpawnPlanner {
    static let spawnRadius: CGFloat = 80

    static func color(localID: String, remoteID: String) -> MultiplayerPlayerColor {
        localID < remoteID ? .blue : .red
    }

    static func position(forPlayerIndex index: Int, hostPosition: CGPoint) -> CGPoint {
        CGPoint(x: hostPosition.x + spawnRadius * CGFloat(index), y: hostPosition.y)
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

extension MultiplayerWireMessage {
    var deliveryPolicy: MultiplayerDeliveryPolicy {
        switch self {
        case .playerInput:
            return .replaceable
        case .gameplayEvent, .hello, .hostAnnouncement, .joinRequest, .joinAccepted, .initialization, .event, .recovery:
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
    let attackTargetID: String?
    let wantsToOpenChestID: String?
    let wantsToCollectPowerUpID: String?

    init(
        playerID: String,
        sequence: UInt64,
        movement: CGVector,
        aimAngle: CGFloat,
        wantsToAttack: Bool,
        attackTargetID: String? = nil,
        wantsToOpenChestID: String? = nil,
        wantsToCollectPowerUpID: String? = nil
    ) {
        self.playerID = playerID
        self.sequence = sequence
        movementX = Double(movement.dx)
        movementY = Double(movement.dy)
        self.aimAngle = Double(aimAngle)
        self.wantsToAttack = wantsToAttack
        self.attackTargetID = attackTargetID
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

enum MultiplayerWireMessage: Codable, Equatable, Sendable {
    case hello(MultiplayerHello)
    case hostAnnouncement(MultiplayerHostAnnouncement)
    case joinRequest(MultiplayerJoinRequest)
    case joinAccepted(MultiplayerJoinAccepted)
    case playerInput(MultiplayerPlayerInput)
    case gameplayEvent(MultiplayerGameplayEvent)
    case initialization(MultiplayerInitializationPayload)
    case event(MultiplayerEventEnvelope)
    case recovery(MultiplayerRecoveryPayload)

    private enum CodingKeys: String, CodingKey {
        case type
        case hello
        case announcement
        case request
        case accepted
        case input
        case gameplayEvent
        case initialization
        case event
        case recovery
    }

    private enum MessageType: String, Codable {
        case hello
        case hostAnnouncement
        case joinRequest
        case joinAccepted
        case playerInput
        case gameplayEvent
        case initialization
        case event
        case recovery
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
        case .playerInput:
            self = .playerInput(try container.decode(MultiplayerPlayerInput.self, forKey: .input))
        case .gameplayEvent:
            self = .gameplayEvent(try container.decode(MultiplayerGameplayEvent.self, forKey: .gameplayEvent))
        case .initialization:
            self = .initialization(try container.decode(MultiplayerInitializationPayload.self, forKey: .initialization))
        case .event:
            self = .event(try container.decode(MultiplayerEventEnvelope.self, forKey: .event))
        case .recovery:
            self = .recovery(try container.decode(MultiplayerRecoveryPayload.self, forKey: .recovery))
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
        case let .playerInput(input):
            try container.encode(MessageType.playerInput, forKey: .type)
            try container.encode(input, forKey: .input)
        case let .gameplayEvent(event):
            try container.encode(MessageType.gameplayEvent, forKey: .type)
            try container.encode(event, forKey: .gameplayEvent)
        case let .initialization(payload):
            try container.encode(MessageType.initialization, forKey: .type)
            try container.encode(payload, forKey: .initialization)
        case let .event(envelope):
            try container.encode(MessageType.event, forKey: .type)
            try container.encode(envelope, forKey: .event)
        case let .recovery(payload):
            try container.encode(MessageType.recovery, forKey: .type)
            try container.encode(payload, forKey: .recovery)
        }
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
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
        if let appleAdapter {
            appleAdapter.delegate = self
            appleAdapter.connect()
            return
        }
        isDisconnecting = false
        state = .connecting
        delegate?.transport(self, didChange: state)
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["game": "wasteland-survivors"],
            serviceType: serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func disconnect() {
        if let appleAdapter {
            appleAdapter.disconnect()
            return
        }
        isDisconnecting = true
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
        if let appleAdapter {
            try appleAdapter.send(data, to: peerID, delivery: delivery)
            return
        }
        guard state == .connected else {
            throw MultiplayerTransportError.notConnected
        }
        guard let session,
              let peer = session.connectedPeers.first(where: { $0.displayName == peerID }) else {
            throw MultiplayerTransportError.peerUnavailable
        }
        let mode: MCSessionSendDataMode = delivery == .reliable ? .reliable : .unreliable
        try session.send(data, toPeers: [peer], with: mode)
    }

    func broadcast(_ data: Data) throws {
        try broadcast(data, delivery: .reliable)
    }

    func broadcast(_ data: Data, delivery: MultiplayerDeliveryPolicy) throws {
        if let appleAdapter {
            try appleAdapter.broadcast(data, delivery: delivery)
            return
        }
        guard state == .connected else {
            throw MultiplayerTransportError.notConnected
        }
        guard let session, !session.connectedPeers.isEmpty else {
            throw MultiplayerTransportError.peerUnavailable
        }
        let mode: MCSessionSendDataMode = delivery == .reliable ? .reliable : .unreliable
        try session.send(data, toPeers: session.connectedPeers, with: mode)
    }
}

extension MultipeerConnectivitySession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
    }
}

extension MultipeerConnectivitySession: MCNearbyServiceBrowserDelegate {
    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard peerID != self.peerID, let session else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
    }
}

extension MultipeerConnectivitySession: AppleMultipeerConnectivityAdapterDelegate {
    func appleAdapter(_ adapter: AppleMultipeerConnectivityAdapter, didChange state: MultiplayerTransportState) {
        guard adapter === appleAdapter else { return }
        self.state = state
        delegate?.transport(self, didChange: state)
    }

    func appleAdapter(_ adapter: AppleMultipeerConnectivityAdapter, didChangePeer peerID: String, state: MultiplayerPeerState) {
        guard adapter === appleAdapter else { return }
        delegate?.transport(self, didChangePeer: peerID, state: state)
    }

    func appleAdapter(_ adapter: AppleMultipeerConnectivityAdapter, didReceive data: Data, from peerID: String) {
        guard adapter === appleAdapter,
              let message = try? MultiplayerWireMessage.decode(data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.transport(self, didReceive: message, from: peerID)
        }
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
            delegate?.transport(self, didChangePeer: peerID.displayName, state: .connected)
        case .connecting:
            self.state = .connecting
        case .notConnected:
            self.state = session.connectedPeers.isEmpty ? .connecting : .connected
            delegate?.transport(self, didChangePeer: peerID.displayName, state: .disconnected)
        @unknown default:
            self.state = .failed
        }
        delegate?.transport(self, didChange: self.state)
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard self.session === session,
              !isDisconnecting,
              let message = try? MultiplayerWireMessage.decode(data) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.transport(self, didReceive: message, from: peerID.displayName)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
#endif
