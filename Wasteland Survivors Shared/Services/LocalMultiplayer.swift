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
}

struct MultiplayerPowerUpState: Codable, Equatable, Sendable {
    let id: String
    let x: Double
    let y: Double
    let type: PowerUpType
}

struct MultiplayerProjectileState: Codable, Equatable, Sendable {
    let id: String
    let x: Double
    let y: Double
    let angle: Double
    let weapon: WeaponType
    let damage: Double
}

struct MultiplayerBoardState: Codable, Equatable, Sendable {
    let sequence: UInt64
    let timestamp: TimeInterval
    let hostID: String
    let players: [MultiplayerPlayerState]
    let zombies: [MultiplayerZombieState]
    let chests: [MultiplayerChestState]
    let powerUps: [MultiplayerPowerUpState]
    let projectiles: [MultiplayerProjectileState]
    let killCount: Int

    init(sequence: UInt64 = 0, timestamp: TimeInterval = 0, hostID: String, players: [MultiplayerPlayerState], zombies: [MultiplayerZombieState], chests: [MultiplayerChestState], powerUps: [MultiplayerPowerUpState], projectiles: [MultiplayerProjectileState], killCount: Int) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.hostID = hostID
        self.players = players
        self.zombies = zombies
        self.chests = chests
        self.powerUps = powerUps
        self.projectiles = projectiles
        self.killCount = killCount
    }

    static func empty(hostID: String, sequence: UInt64) -> Self {
        Self(sequence: sequence, timestamp: 0, hostID: hostID, players: [], zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0)
    }
}

struct MultiplayerPlayerInput: Codable, Equatable, Sendable {
    let playerID: String
    let sequence: UInt64
    let movementX: Double
    let movementY: Double
    let aimAngle: Double
    let wantsToAttack: Bool

    init(playerID: String, sequence: UInt64, movement: CGVector, aimAngle: CGFloat, wantsToAttack: Bool) {
        self.playerID = playerID
        self.sequence = sequence
        movementX = Double(movement.dx)
        movementY = Double(movement.dy)
        self.aimAngle = Double(aimAngle)
        self.wantsToAttack = wantsToAttack
    }

    var movement: CGVector { CGVector(dx: movementX, dy: movementY) }
}

struct MultiplayerSnapshotBuffer {
    private(set) var latest: MultiplayerBoardState?

    mutating func append(_ snapshot: MultiplayerBoardState) -> Bool {
        guard latest.map({ $0.sequence < snapshot.sequence }) ?? true else { return false }
        latest = snapshot
        return true
    }
}

enum MultiplayerWireMessage: Codable, Equatable, Sendable {
    case playerUpdate(MultiplayerPlayerState)
    case boardSnapshot(MultiplayerBoardState)
    case playerInput(MultiplayerPlayerInput)

    private enum CodingKeys: String, CodingKey {
        case type
        case player
        case board
        case input
    }

    private enum MessageType: String, Codable {
        case playerUpdate
        case boardSnapshot
        case playerInput
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .playerUpdate:
            self = .playerUpdate(try container.decode(MultiplayerPlayerState.self, forKey: .player))
        case .boardSnapshot:
            self = .boardSnapshot(try container.decode(MultiplayerBoardState.self, forKey: .board))
        case .playerInput:
            self = .playerInput(try container.decode(MultiplayerPlayerInput.self, forKey: .input))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .playerUpdate(player):
            try container.encode(MessageType.playerUpdate, forKey: .type)
            try container.encode(player, forKey: .player)
        case let .boardSnapshot(board):
            try container.encode(MessageType.boardSnapshot, forKey: .type)
            try container.encode(board, forKey: .board)
        case let .playerInput(input):
            try container.encode(MessageType.playerInput, forKey: .type)
            try container.encode(input, forKey: .input)
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

protocol LocalMultiplayerNetworkSessionDelegate: AnyObject {
    func networkSession(_ session: LocalMultiplayerNetworkSession, didReceive data: Data)
}

protocol LocalMultiplayerNetworkSession: AnyObject {
    var delegate: LocalMultiplayerNetworkSessionDelegate? { get set }
    var localPlayerID: String { get }
    func start()
    func stop()
    func send(_ data: Data)
}

#if canImport(MultipeerConnectivity)
final class MultipeerConnectivitySession: NSObject, LocalMultiplayerNetworkSession {
    weak var delegate: LocalMultiplayerNetworkSessionDelegate?
    let localPlayerID: String
    let sessionStartedAt: TimeInterval

    private let serviceType = "wasteland-surv"
    private let peerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    init(playerName: String = "Wasteland Player") {
        localPlayerID = UUID().uuidString
        sessionStartedAt = Date().timeIntervalSince1970
        peerID = MCPeerID(displayName: "\(playerName)-\(localPlayerID.prefix(4))")
        super.init()
    }

    func start() {
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

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
    }

    func send(_ data: Data) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
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

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
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
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
}

extension MultipeerConnectivitySession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {}

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        delegate?.networkSession(self, didReceive: data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
#endif
