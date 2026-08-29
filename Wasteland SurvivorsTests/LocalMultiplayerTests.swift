import CoreGraphics
import SpriteKit
import Testing
@testable import Wasteland_Survivors

@MainActor
private final class FakeMultiplayerSession: MultiplayerTransport {
    weak var delegate: MultiplayerTransportDelegate?
    let localPeerID: String
    private(set) var state: MultiplayerTransportState = .idle
    var connectedPeerIDs: Set<String> = []
    private(set) var started = false
    private(set) var sentData: [Data] = []
    private(set) var deliveryPolicies: [MultiplayerDeliveryPolicy] = []

    init(localPlayerID: String) {
        self.localPeerID = localPlayerID
    }

    func connect() {
        started = true
        state = .connected
        connectedPeerIDs = [localPeerID]
        delegate?.transport(self, didChange: state)
    }

    func disconnect() {
        state = .disconnected
        connectedPeerIDs.removeAll()
        delegate?.transport(self, didChange: state)
    }

    func peerDisconnected(_ peerID: String) {
        connectedPeerIDs.remove(peerID)
        delegate?.transport(self, didChangePeer: peerID, state: .disconnected)
    }

    func send(_ data: Data, to peerID: String) throws { sentData.append(data) }
    func broadcast(_ data: Data) throws { sentData.append(data) }

    func broadcast(_ data: Data, delivery: MultiplayerDeliveryPolicy) throws {
        deliveryPolicies.append(delivery)
        try broadcast(data)
    }

    func deliver(_ data: Data, from peerID: String? = nil) {
        guard let message = try? MultiplayerWireMessage.decode(data) else { return }
        let senderID: String
        switch message {
        case let .hello(value): senderID = value.peerID
        case let .hostAnnouncement(value): senderID = value.hostID
        case let .joinRequest(value): senderID = value.peerID
        case let .joinAccepted(value): senderID = value.hostID
        case let .playerUpdate(value): senderID = value.id
        case let .boardSnapshot(value): senderID = value.hostID
        case let .playerInput(value): senderID = value.playerID
        case let .gameplayEvent(value): senderID = value.hostID
        }
        delegate?.transport(self, didReceive: data, from: peerID ?? senderID)
    }
}

@Suite("Local Multiplayer")
struct LocalMultiplayerTests {
    @Test("Assigns a distinct color to each player slot")
    func assignsDistinctColorsToPlayerSlots() {
        let colors = MultiplayerPlayerColor.allCases.map { $0.rawValue }

        #expect(Set(colors).count == colors.count)
        #expect(colors.count >= 4)
    }

    @Test("Elects one blue host and one red joining player consistently")
    func playerColorsAreConsistentAcrossPeers() {
        let firstColor = MultiplayerSpawnPlanner.color(localID: "a", remoteID: "b")
        let secondColor = MultiplayerSpawnPlanner.color(localID: "b", remoteID: "a")

        #expect(firstColor == .blue)
        #expect(secondColor == .red)
    }

    @Test("The earliest advertiser remains authoritative")
    func earliestAdvertiserIsHost() {
        let later = MultiplayerPlayerState(id: "first-alphabetically", position: .zero, color: .blue, sessionStartedAt: 20)
        let earlier = MultiplayerPlayerState(id: "second-alphabetically", position: .zero, color: .red, sessionStartedAt: 10)

        #expect(MultiplayerHostSelector.hostID(for: [later, earlier]) == "second-alphabetically")
    }

    @Test("Spawns a joining player near the host")
    func spawnPositionIsNearHost() {
        let hostPosition = CGPoint(x: 120, y: -80)
        let joiningPosition = MultiplayerSpawnPlanner.position(
            forPlayerIndex: 1,
            hostPosition: hostPosition
        )

        let distance = hypot(
            joiningPosition.x - hostPosition.x,
            joiningPosition.y - hostPosition.y
        )

        #expect(distance == MultiplayerSpawnPlanner.spawnRadius)
        #expect(joiningPosition != hostPosition)
    }

    @Test("Wraps and unwraps player updates through the network message")
    func playerUpdateRoundTripsThroughWireMessage() throws {
        let state = MultiplayerPlayerState(
            id: "player-2",
            position: CGPoint(x: 42, y: -18),
            color: .green
        )

        let data = try MultiplayerWireMessage.playerUpdate(state).encoded()
        let decoded = try MultiplayerWireMessage.decode(data)

        #expect(decoded == .playerUpdate(state))
    }

    @Test("Round-trips the complete authoritative board snapshot")
    func boardSnapshotRoundTripsThroughWireMessage() throws {
        let board = MultiplayerBoardState(
            hostID: "host",
            players: [MultiplayerPlayerState(id: "host", position: .zero, color: .blue, health: 84, weapon: .rifle, powerUps: [.damage], rotation: 1.2)],
            zombies: [MultiplayerZombieState(id: "zombie-1", x: 10, y: 20, health: 42, rotation: 0.5)],
            chests: [MultiplayerChestState(id: "chest-1", x: 30, y: 40)],
            powerUps: [MultiplayerPowerUpState(id: "powerup-1", x: 50, y: 60, type: .range)],
            projectiles: [MultiplayerProjectileState(id: "projectile-1", x: 70, y: 80, angle: 0.4, weapon: .pistol, damage: 30)],
            killCount: 7
        )

        let data = try MultiplayerWireMessage.boardSnapshot(board).encoded()
        let decoded = try MultiplayerWireMessage.decode(data)

        #expect(decoded == .boardSnapshot(board))
    }

    @Test("The main menu exposes local multiplayer")
    @MainActor
    func mainMenuExposesLocalMultiplayer() {
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)

        let menu = scene.cameraNode.childNode(withName: "mainMenu")
        #expect(menu?.childNode(withName: "multiplayerButton") != nil)
    }

    @Test("New multiplayer scenes receive distinct session identities")
    func newMultiplayerScenesReceiveDistinctSessionIdentities() {
        let first = GameScene.newGameScene(size: CGSize(width: 800, height: 600))
        let second = GameScene.newGameScene(size: CGSize(width: 800, height: 600))

        #expect(!first.multiplayerSessionID.isEmpty)
        #expect(first.multiplayerSessionID != second.multiplayerSessionID)
    }

    @Test("Tapping local multiplayer starts the game")
    @MainActor
    func tappingLocalMultiplayerStartsTheGame() {
        // Given a newly presented main menu.
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)

        // When the multiplayer button is tapped at its rendered position.
        scene.handleMenuInput(at: CGPoint(x: 0, y: -70))

        // Then the menu is dismissed and gameplay starts.
        #expect(scene.hasStartedGame)
        #expect(scene.menuState == .playing)
        #expect(scene.cameraNode.childNode(withName: "mainMenu") == nil)
    }

    @Test("Remote player nodes use their assigned colors")
    @MainActor
    func playerNodeAppliesMultiplayerColor() {
        let player = PlayerNode()

        player.apply(multiplayerColor: .purple)

        #expect(player.multiplayerColor == .purple)
    }

    @Test("Host publishes the complete live board to the network")
    @MainActor
    func hostPublishesBoardSnapshot() throws {
        let session = FakeMultiplayerSession(localPlayerID: "host")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "wasteland-survivors-local",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.connectedPeerIDs.insert("client")
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "wasteland-survivors-local",
            peerID: "client",
            startedAt: 9_999_999_999,
            protocolVersion: 1
        )).encoded())

        scene.update(0)
        scene.update(1)
        scene.update(2)
        scene.update(3)

        let snapshotData = try #require(session.sentData.compactMap { data -> MultiplayerBoardState? in
            guard case let .boardSnapshot(board) = try? MultiplayerWireMessage.decode(data) else { return nil }
            return board
        }.last)

        #expect(session.started)
        #expect(snapshotData.hostID == "host")
        #expect(snapshotData.players.contains { $0.id == "host" })
        #expect(!snapshotData.zombies.isEmpty)
        #expect(!snapshotData.chests.isEmpty)
        #expect(snapshotData.killCount == 0)
        #expect(snapshotData.simulationTick == scene.authoritativeSimulationTick)
        #expect(session.deliveryPolicies.contains(.replaceable))
    }

    @Test("Host transfers the current board immediately after accepting a late joiner")
    @MainActor
    func hostTransfersCurrentBoardToLateJoinerImmediately() throws {
        let session = FakeMultiplayerSession(localPlayerID: "host")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "match",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        scene.update(0)
        scene.update(1)
        scene.update(2)
        scene.update(3)
        session.connectedPeerIDs.insert("late-client")

        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "late-client", startedAt: 9_999_999_999, protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match", peerID: "late-client", protocolVersion: 1
        )).encoded(), from: "late-client")

        let transferredBoard = try #require(session.sentData.compactMap { data -> MultiplayerBoardState? in
            guard case let .boardSnapshot(board) = try? MultiplayerWireMessage.decode(data) else { return nil }
            return board
        }.last)


        #expect(transferredBoard.hostID == "host")
        #expect(transferredBoard.players.contains { $0.id == "host" })
        #expect(!transferredBoard.chests.isEmpty)
    }

    @Test("Host renders and simulates a joined player on the shared world canvas")
    @MainActor
    func hostRendersJoinedPlayerOnSharedWorldCanvas() throws {
        let session = FakeMultiplayerSession(localPlayerID: "host")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "match",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.connectedPeerIDs.insert("client")

        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "client", startedAt: 9_999_999_999, protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match", peerID: "client", protocolVersion: 1
        )).encoded(), from: "client")
        session.deliver(try MultiplayerWireMessage.playerInput(.init(
            playerID: "client", sequence: 1, movement: .zero, aimAngle: 0, wantsToAttack: false
        )).encoded(), from: "client")

        scene.update(0)
        scene.update(1.0 / 60.0)

        #expect(scene.remotePlayers["client"]?.parent === scene.worldNode)
        let snapshot = try #require(session.sentData.compactMap { data -> MultiplayerBoardState? in
            guard case let .boardSnapshot(board) = try? MultiplayerWireMessage.decode(data) else { return nil }
            return board
        }.last)
        #expect(snapshot.players.contains { $0.id == "client" })
    }

    @Test("Authoritative simulation is independent of render frame partitioning")
    @MainActor
    func authoritativeSimulationIsIndependentOfRenderFramePartitioning() throws {
        let splitSession = FakeMultiplayerSession(localPlayerID: "host-split")
        let splitScene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "wasteland-survivors-local",
            multiplayerSessionFactory: { splitSession }
        )
        let splitView = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        splitScene.didMove(to: splitView)
        splitScene.startLocalMultiplayer()
        splitSession.connectedPeerIDs.insert("client")
        splitSession.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "wasteland-survivors-local",
            peerID: "client",
            startedAt: 9_999_999_999,
            protocolVersion: 1
        )).encoded())
        splitScene.update(0.001)
        splitScene.update(0.001 + 1.0 / 120.0)
        splitScene.update(0.001 + 2.0 / 120.0)

        let wholeSession = FakeMultiplayerSession(localPlayerID: "host-whole")
        let wholeScene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "wasteland-survivors-local",
            multiplayerSessionFactory: { wholeSession }
        )
        let wholeView = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        wholeScene.didMove(to: wholeView)
        wholeScene.startLocalMultiplayer()
        wholeSession.connectedPeerIDs.insert("client")
        wholeSession.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "wasteland-survivors-local",
            peerID: "client",
            startedAt: 9_999_999_999,
            protocolVersion: 1
        )).encoded())
        wholeScene.update(0.001)
        wholeScene.update(0.001 + 1.0 / 60.0)

        #expect(splitScene.authoritativeSimulationTick > 0)
        #expect(splitScene.authoritativeSimulationTick == wholeScene.authoritativeSimulationTick)
        #expect(splitScene.playerNode.position == wholeScene.playerNode.position)
    }

    @Test("Restarting a multiplayer match resets authoritative tick state")
    @MainActor
    func restartingMultiplayerMatchResetsAuthoritativeTickState() throws {
        let session = FakeMultiplayerSession(localPlayerID: "host")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "wasteland-survivors-local",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.connectedPeerIDs.insert("client")
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "wasteland-survivors-local",
            peerID: "client",
            startedAt: 9_999_999_999,
            protocolVersion: 1
        )).encoded())

        scene.update(0.001)
        scene.update(0.001 + 1.0 / 60.0)
        #expect(scene.authoritativeSimulationTick == 1)

        scene.restartGame()
        scene.update(0.001)
        scene.update(0.001 + 1.0 / 60.0)

        #expect(scene.authoritativeSimulationTick == 1)
    }

    @Test("Client applies the host board snapshot to its real scene")
    @MainActor
    func clientAppliesBoardSnapshot() async throws {
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "wasteland-survivors-local",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "wasteland-survivors-local",
            hostID: "host",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())

        let board = MultiplayerBoardState(
            hostID: "host",
            players: [
                MultiplayerPlayerState(id: "host", position: CGPoint(x: 100, y: 100), color: .blue, health: 70, weapon: .rifle),
                MultiplayerPlayerState(id: "client", position: CGPoint(x: 20, y: 30), color: .red, health: 80, weapon: .shotgun)
            ],
            zombies: [MultiplayerZombieState(id: "zombie-1", x: 40, y: 50, health: 45, rotation: 0)],
            chests: [MultiplayerChestState(id: "chest-1", x: 60, y: 70)],
            powerUps: [MultiplayerPowerUpState(id: "powerup-1", x: 80, y: 90, type: .damage)],
            projectiles: [MultiplayerProjectileState(id: "projectile-1", ownerID: "host", x: 100, y: 110, angle: 0, weapon: .pistol, damage: 30)],
            killCount: 12
        )

        session.deliver(try MultiplayerWireMessage.boardSnapshot(board).encoded())
        try await Task.sleep(for: .milliseconds(50))

        #expect(scene.killCount == 12)
        #expect(scene.playerNode.position == CGPoint(x: 20, y: 30))
        #expect(scene.playerNode.currentWeapon == WeaponType.shotgun)
        #expect(scene.playerNode.currentHealth == 80)
        #expect(scene.remotePlayers["host"]?.position == CGPoint(x: 100, y: 100))
        #expect(scene.zombies.count == 1)
        #expect(scene.chests.count == 1)
        #expect(scene.powerUps.count == 1)
        #expect(scene.worldNode.children.contains { $0 is ProjectileNode })

        // Full snapshots are replacement messages: omitting an entity is an
        // authoritative removal, not an instruction to retain the old node.
        let clearedBoard = MultiplayerBoardState(
            sequence: 1,
            simulationTick: 1,
            hostID: "host",
            players: board.players,
            zombies: [],
            chests: board.chests,
            powerUps: board.powerUps,
            projectiles: [],
            killCount: board.killCount
        )
        session.deliver(try MultiplayerWireMessage.boardSnapshot(clearedBoard).encoded())
        try await Task.sleep(for: .milliseconds(50))
        #expect(scene.zombies.isEmpty)
        #expect(scene.worldNode.children.contains { $0 is ProjectileNode } == false)
    }

    @Test("Client applies replicated remote player rotation to its real scene")
    @MainActor
    func clientAppliesReplicatedRemotePlayerRotationToRealScene() async throws {
        // Given a client that has accepted the host and receives a rotated host state.
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "wasteland-survivors-local",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "wasteland-survivors-local",
            hostID: "host",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())

        let expectedRotation = CGFloat.pi / 2
        let board = MultiplayerBoardState(
            sequence: 1,
            simulationTick: 1,
            hostID: "host",
            players: [
                MultiplayerPlayerState(
                    id: "host",
                    position: CGPoint(x: 100, y: 100),
                    color: .blue,
                    rotation: expectedRotation
                ),
                MultiplayerPlayerState(
                    id: "client",
                    position: .zero,
                    color: .red
                )
            ],
            zombies: [],
            chests: [],
            powerUps: [],
            projectiles: [],
            killCount: 0
        )

        // When the authoritative board snapshot is delivered.
        session.deliver(try MultiplayerWireMessage.boardSnapshot(board).encoded())
        try await Task.sleep(for: .milliseconds(50))

        // Then the remote player faces the replicated direction.
        #expect(abs((scene.remotePlayers["host"]?.zRotation ?? 0) - expectedRotation) < 0.001)
    }

    @Test("Client keeps the remote player in the shared world after camera and interpolation updates")
    @MainActor
    func clientKeepsRemotePlayerInSharedWorldAfterRenderUpdates() async throws {
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "match",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "match", hostID: "host", hostStartedAt: 1, protocolVersion: 1
        )).encoded())

        for tick in 1...4 {
            let board = MultiplayerBoardState(
                sequence: UInt64(tick),
                simulationTick: UInt64(tick),
                hostID: "host",
                players: [
                    MultiplayerPlayerState(id: "host", position: CGPoint(x: 100 + tick * 10, y: 100), color: .blue),
                    MultiplayerPlayerState(id: "client", position: CGPoint(x: 0, y: 0), color: .red)
                ],
                zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0
            )
            session.deliver(try MultiplayerWireMessage.boardSnapshot(board).encoded())
            scene.update(Double(tick) / 60.0)
        }

        let remotePlayer = try #require(scene.remotePlayers["host"])
        #expect(remotePlayer.parent === scene.worldNode)
        #expect(scene.playerNode.parent === scene.worldNode)
        #expect(scene.cameraNode.position == scene.playerNode.position)
        #expect(scene.worldNode.convert(remotePlayer.position, to: scene) != scene.cameraNode.position)
    }

    @Test("Host advances a joined player's authoritative position from peer input")
    @MainActor
    func hostAdvancesJoinedPlayerFromPeerInput() throws {
        let session = FakeMultiplayerSession(localPlayerID: "host")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "match",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.connectedPeerIDs.insert("client")
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "client", startedAt: 9_999_999_999, protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match", peerID: "client", protocolVersion: 1
        )).encoded(), from: "client")

        let initialPosition = try #require(scene.remotePlayers["client"]?.position)
        session.deliver(try MultiplayerWireMessage.playerInput(.init(
            playerID: "client", sequence: 1, movement: CGVector(dx: 1, dy: 0), aimAngle: 0, wantsToAttack: false
        )).encoded(), from: "client")
        scene.update(0)
        scene.update(1.0 / 60.0)

        let movedPosition = try #require(scene.remotePlayers["client"]?.position)
        #expect(movedPosition.x > initialPosition.x)
    }

    @Test("Client applies an authorized match-ended event to its presentation")
    @MainActor
    func clientAppliesMatchEndedGameplayEvent() throws {
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "wasteland-survivors-local",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "wasteland-survivors-local", hostID: "host", hostStartedAt: 1, protocolVersion: 1
        )).encoded())
        let event = MultiplayerGameplayEvent(
            event: .matchEnded,
            sessionID: "wasteland-survivors-local",
            sequence: 1,
            tick: 1,
            hostID: "host"
        )

        session.deliver(try MultiplayerWireMessage.gameplayEvent(event).encoded(), from: "host")

        #expect(scene.isGameOver)
    }

    @Test("Client presents game over when the authoritative host disconnects")
    @MainActor
    func clientPresentsGameOverOnHostLoss() throws {
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "wasteland-survivors-local",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "wasteland-survivors-local", hostID: "host", hostStartedAt: 1, protocolVersion: 1
        )).encoded())

        session.peerDisconnected("host")

        #expect(scene.isGameOver)
    }

    @Test("Client reconciliation replays only inputs not acknowledged by the host")
    @MainActor
    func clientReconcilesUnacknowledgedPrediction() throws {
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "wasteland-survivors-local",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "wasteland-survivors-local", hostID: "host", hostStartedAt: 1, protocolVersion: 1
        )).encoded())
        scene.keysPressed.insert(13)
        scene.update(0.001)
        scene.update(0.001 + 1.0 / 60.0)

        let board = MultiplayerBoardState(
            sequence: 1, simulationTick: 0, hostID: "host",
            players: [MultiplayerPlayerState(id: "client", position: .zero, color: .red)],
            zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0,
            acknowledgedInputSequences: [:]
        )
        session.deliver(try MultiplayerWireMessage.boardSnapshot(board).encoded(), from: "host")

        #expect(scene.playerNode.position.y > 0)
    }

    @Test("Client does not replay an input already acknowledged by the host")
    @MainActor
    func clientDropsAcknowledgedPrediction() throws {
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "wasteland-survivors-local",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "wasteland-survivors-local", hostID: "host", hostStartedAt: 1, protocolVersion: 1
        )).encoded())
        scene.keysPressed.insert(13)
        scene.update(0.001)
        scene.update(0.001 + 1.0 / 60.0)

        let board = MultiplayerBoardState(
            sequence: 1, simulationTick: 0, hostID: "host",
            players: [MultiplayerPlayerState(id: "client", position: .zero, color: .red)],
            zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0,
            acknowledgedInputSequences: ["client": 1]
        )
        session.deliver(try MultiplayerWireMessage.boardSnapshot(board).encoded(), from: "host")

        #expect(scene.playerNode.position == .zero)
    }

    @Test("Client preserves projectile node identity across snapshot updates")
    @MainActor
    func clientPreservesProjectileNodeIdentityAcrossSnapshots() async throws {
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600), multiplayerSessionID: "wasteland-survivors-local", multiplayerSessionFactory: { session })
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(sessionID: "wasteland-survivors-local", hostID: "host", hostStartedAt: 1, protocolVersion: 1)).encoded())

        let first = MultiplayerBoardState(sequence: 1, hostID: "host", players: [], zombies: [], chests: [], powerUps: [], projectiles: [MultiplayerProjectileState(id: "projectile", ownerID: "host", x: 10, y: 20, angle: 0, weapon: .pistol, damage: 30)], killCount: 0)
        let second = MultiplayerBoardState(sequence: 2, hostID: "host", players: [], zombies: [], chests: [], powerUps: [], projectiles: [MultiplayerProjectileState(id: "projectile", ownerID: "host", x: 30, y: 40, angle: 0.5, weapon: .pistol, damage: 30)], killCount: 0)
        session.deliver(try MultiplayerWireMessage.boardSnapshot(first).encoded())
        try await Task.sleep(for: .milliseconds(20))
        let projectile = try #require(scene.worldNode.children.compactMap { $0 as? ProjectileNode }.first)
        session.deliver(try MultiplayerWireMessage.boardSnapshot(second).encoded())
        try await Task.sleep(for: .milliseconds(20))

        #expect(scene.worldNode.children.compactMap { $0 as? ProjectileNode }.first === projectile)
        #expect(projectile.position == CGPoint(x: 30, y: 40))
    }

    @Test("Rotation interpolation follows the shortest angular path")
    func rotationInterpolationUsesShortestPath() {
        let current = CGFloat.pi - 0.1
        let target = -CGFloat.pi + 0.1

        let next = MultiplayerInterpolation.angle(
            current: current,
            target: target,
            deltaTime: 0.1,
            responsiveness: 1
        )

        #expect(next > current)
        #expect(next < CGFloat.pi + 0.2)
    }

    @Test("Interpolation moves toward the host target without teleporting")
    func interpolationMovesTowardTarget() {
        let current = CGPoint(x: 0, y: 0)
        let target = CGPoint(x: 100, y: 0)

        let next = MultiplayerInterpolation.position(
            current: current,
            target: target,
            deltaTime: 1.0 / 60.0,
            responsiveness: 10
        )

        #expect(next.x > current.x)
        #expect(next.x < target.x)
    }

    @Test("Interpolation converges to nearby authoritative positions")
    func interpolationConvergesToTarget() {
        var position = CGPoint.zero
        let target = CGPoint(x: 10, y: -20)

        for _ in 0..<120 {
            position = MultiplayerInterpolation.position(
                current: position,
                target: target,
                deltaTime: 1.0 / 60.0,
                responsiveness: 12
            )
        }

        #expect(hypot(position.x - target.x, position.y - target.y) < 0.1)
    }

    @Test("Interpolation snaps large divergence while smoothing small correction")
    func interpolationRecoversFromLargeDivergence() {
        let small = MultiplayerInterpolation.position(
            current: .zero, target: CGPoint(x: 20, y: 0), deltaTime: 1.0 / 60.0, responsiveness: 10
        )
        let large = MultiplayerInterpolation.position(
            current: .zero, target: CGPoint(x: 1_000, y: 0), deltaTime: 1.0 / 60.0, responsiveness: 10
        )

        #expect(small.x > 0 && small.x < 20)
        #expect(large == CGPoint(x: 1_000, y: 0))
    }

    @Test("Player input round-trips with its sequence number")
    func playerInputRoundTrips() throws {
        let input = MultiplayerPlayerInput(
            playerID: "client",
            sequence: 17,
            movement: CGVector(dx: 1, dy: -1),
            aimAngle: 0.75,
            wantsToAttack: true,
            wantsToOpenChestID: "chest-1",
            wantsToCollectPowerUpID: "power-up-1"
        )

        let decoded = try MultiplayerWireMessage.decode(
            MultiplayerWireMessage.playerInput(input).encoded()
        )

        #expect(decoded == .playerInput(input))
    }

    @Test("A multiplayer client publishes intent instead of authoritative player state")
    @MainActor
    func clientPublishesIntentInsteadOfPlayerState() throws {
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "match",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "match", hostID: "host", hostStartedAt: 1, protocolVersion: 1
        )).encoded())
        let chest = try #require(scene.chests.first)
        scene.openChest(chest)
        scene.movementVector = CGVector(dx: 1, dy: 0)
        scene.update(0.001)
        scene.update(0.2)

        let messages = session.sentData.compactMap { try? MultiplayerWireMessage.decode($0) }
        let input = try #require(messages.compactMap { message -> MultiplayerPlayerInput? in
            guard case let .playerInput(input) = message else { return nil }
            return input
        }.last)
        #expect(input.wantsToOpenChestID == chest.multiplayerID)
        #expect(!messages.contains {
            if case .playerUpdate = $0 { return true }
            return false
        })
    }

    @Test("Reliable gameplay events round-trip every event field and use reliable delivery")
    func gameplayEventRoundTripsWithReliableDelivery() throws {
        let replicated = MultiplayerGameplayEvent(
            event: .chestOpened(id: "chest-event", playerID: "client", weapon: .rifle),
            sessionID: "match",
            sequence: 9,
            tick: 42,
            hostID: "host"
        )
        let message = MultiplayerWireMessage.gameplayEvent(replicated)

        #expect(try MultiplayerWireMessage.decode(message.encoded()) == message)
        #expect(message.deliveryPolicy == .reliable)
    }

    @Test("Every supported gameplay event preserves its payload over the wire")
    func everyGameplayEventRoundTrips() throws {
        let events: [GameplayEvent] = [
            .projectileSpawned(id: "projectile", ownerID: "host"),
            .meleeAttack(id: "attack", ownerID: "host"),
            .zombieDamaged(id: "zombie", amount: 4),
            .zombieKilled(id: "zombie", ownerID: "host"),
            .chestOpened(id: "chest", playerID: "client", weapon: .rifle),
            .powerUpCollected(id: "powerup", playerID: "client", type: .range),
            .playerDamaged(id: "client", amount: 3),
            .playerEliminated(id: "client"),
            .matchEnded
        ]

        for (index, event) in events.enumerated() {
            let envelope = MultiplayerGameplayEvent(
                event: event, sessionID: "match", sequence: UInt64(index + 1), tick: UInt64(index + 1), hostID: "host"
            )
            let message = MultiplayerWireMessage.gameplayEvent(envelope)
            #expect(try MultiplayerWireMessage.decode(message.encoded()) == message)
        }
    }

    @Test("Gameplay events reject a foreign host identity")
    func gameplayEventRejectsForeignHost() throws {
        let event = MultiplayerGameplayEvent(
            event: .matchEnded,
            sessionID: "match",
            sequence: 1,
            tick: 2,
            hostID: "attacker"
        )

        #expect(throws: ReplicationError.unauthorizedOwner) {
            try event.validate(expectedHostID: "host")
        }
    }

    @Test("Gameplay events reject impossible semantic payloads")
    func gameplayEventRejectsImpossiblePayloads() {
        let invalidDamage = MultiplayerGameplayEvent(
            event: .zombieDamaged(id: "zombie-1", amount: -1),
            sessionID: "match",
            sequence: 1,
            tick: 1,
            hostID: "host"
        )

        #expect(throws: ReplicationError.malformedPayload) {
            try invalidDamage.validate(expectedHostID: "host")
        }
    }

    @Test("Gameplay events reject replay from a different session")
    func gameplayEventRejectsDifferentSession() {
        let event = MultiplayerGameplayEvent(
            event: .matchEnded,
            sessionID: "old-match",
            sequence: 1,
            tick: 1,
            hostID: "host"
        )

        #expect(throws: ReplicationError.unauthorizedOwner) {
            try event.validate(expectedHostID: "host", expectedSessionID: "current-match")
        }
    }

    @Test("Gameplay events reject zero sequence or simulation tick")
    func gameplayEventRejectsMissingOrderingMetadata() {
        let zeroSequence = MultiplayerGameplayEvent(
            event: .matchEnded,
            sessionID: "match",
            sequence: 0,
            tick: 1,
            hostID: "host"
        )
        let zeroTick = MultiplayerGameplayEvent(
            event: .matchEnded,
            sessionID: "match",
            sequence: 1,
            tick: 0,
            hostID: "host"
        )

        #expect(throws: ReplicationError.malformedPayload) {
            try zeroSequence.validate(expectedHostID: "host", expectedSessionID: "match")
        }
        #expect(throws: ReplicationError.malformedPayload) {
            try zeroTick.validate(expectedHostID: "host", expectedSessionID: "match")
        }
    }

    @Test("Snapshot buffer inserts delayed snapshots in sequence order")
    func snapshotBufferInsertsDelayedSnapshots() {
        var buffer = MultiplayerSnapshotBuffer(capacity: 3)
        for sequence in [1, 3, 2] {
            let accepted = buffer.append(MultiplayerBoardState.empty(hostID: "host", sequence: UInt64(sequence)))
            #expect(accepted)
        }

        #expect(buffer.snapshots.map { $0.sequence } == [1, 2, 3])
        let acceptedDuplicate = buffer.append(MultiplayerBoardState.empty(hostID: "host", sequence: 2))
        #expect(!acceptedDuplicate)
    }

    @Test("Snapshot buffer rejects stale snapshots")
    func snapshotBufferRejectsStaleSnapshots() {
        var buffer = MultiplayerSnapshotBuffer()
        let first = MultiplayerBoardState.empty(hostID: "host", sequence: 10)
        let stale = MultiplayerBoardState.empty(hostID: "host", sequence: 9)

        let acceptedFirst = buffer.append(first)
        let acceptedStale = buffer.append(stale)

        #expect(acceptedFirst)
        #expect(!acceptedStale)
        #expect(buffer.latest?.sequence == 10)
    }

    @Test("Snapshot interpolation lookup uses simulation ticks rather than packet sequences")
    func snapshotBufferUsesSimulationTicksForSurroundingSnapshots() {
        var buffer = MultiplayerSnapshotBuffer()
        let before = MultiplayerBoardState(sequence: 100, simulationTick: 10, hostID: "host", players: [], zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0)
        let after = MultiplayerBoardState(sequence: 200, simulationTick: 20, hostID: "host", players: [], zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0)
        _ = buffer.append(before)
        _ = buffer.append(after)

        let surrounding = buffer.surrounding(tick: 15)

        #expect(surrounding?.before == before)
        #expect(surrounding?.after == after)
    }

    @Test("Snapshot interpolation remains correct when sequence and tick order differ")
    func snapshotBufferOrdersInterpolationBySimulationTick() {
        var buffer = MultiplayerSnapshotBuffer(capacity: 4)
        let lateTick = MultiplayerBoardState(sequence: 1, simulationTick: 20, hostID: "host", players: [], zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0)
        let earlyTick = MultiplayerBoardState(sequence: 2, simulationTick: 10, hostID: "host", players: [], zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0)
        let acceptedLateTick = buffer.append(lateTick)
        let acceptedEarlyTick = buffer.append(earlyTick)
        #expect(acceptedLateTick)
        #expect(acceptedEarlyTick)

        let surrounding = buffer.surrounding(tick: 15)

        #expect(surrounding?.before == earlyTick)
        #expect(surrounding?.after == lateTick)
    }

    @Test("Snapshot buffer samples with an explicit delay and bounded extrapolation")
    func snapshotBufferSamplesDelayedAndBounded() {
        var buffer = MultiplayerSnapshotBuffer(capacity: 4)
        let first = MultiplayerBoardState(sequence: 1, simulationTick: 10, hostID: "host", players: [
            MultiplayerPlayerState(id: "player", position: CGPoint(x: 0, y: 0), color: .blue)
        ], zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0)
        let second = MultiplayerBoardState(sequence: 2, simulationTick: 20, hostID: "host", players: [
            MultiplayerPlayerState(id: "player", position: CGPoint(x: 100, y: 0), color: .blue)
        ], zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0)
        _ = buffer.append(first)
        _ = buffer.append(second)

        #expect(buffer.position(for: "player", renderTick: 25, delayTicks: 5, maxExtrapolationTicks: 3) == CGPoint(x: 100, y: 0))
        #expect(buffer.position(for: "player", renderTick: 20, delayTicks: 5, maxExtrapolationTicks: 3) == CGPoint(x: 50, y: 0))
    }

    @Test("Client ignores snapshots from a different host")
    @MainActor
    func clientIgnoresSnapshotsFromDifferentHost() async throws {
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600), multiplayerSessionID: "wasteland-survivors-local", multiplayerSessionFactory: { session })
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()
        session.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "wasteland-survivors-local",
            hostID: "host-a",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())

        let first = MultiplayerBoardState.empty(hostID: "host-a", sequence: 1)
        let second = MultiplayerBoardState(sequence: 2, hostID: "host-b", players: [], zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 99)
        session.deliver(try MultiplayerWireMessage.boardSnapshot(first).encoded())
        try await Task.sleep(for: .milliseconds(50))
        session.deliver(try MultiplayerWireMessage.boardSnapshot(second).encoded())
        try await Task.sleep(for: .milliseconds(50))

        #expect(scene.killCount == 0)
    }

    @Test("Every networked gameplay entity receives a unique stable ID")
    func gameplayEntitiesHaveStableIDs() {
        let zombie = ZombieNode()
        let chest = ChestNode()
        let powerUp = PowerUpNode(powerUp: .damage)
        let projectile = ProjectileNode(weapon: .pistol, directionAngle: 0)

        let ids = [zombie.multiplayerID, chest.multiplayerID, powerUp.multiplayerID, projectile.multiplayerID]
        #expect(ids.allSatisfy { !$0.isEmpty })
        #expect(Set(ids).count == ids.count)
    }

    @Test("An entity keeps its ID when it is serialized into a snapshot")
    func snapshotUsesEntityIDs() {
        let zombie = ZombieNode()
        let chest = ChestNode()
        let powerUp = PowerUpNode(powerUp: .range)
        let projectile = ProjectileNode(weapon: .rifle, directionAngle: 0.2)

        #expect(MultiplayerSnapshotEntityIDs.zombie(zombie) == zombie.multiplayerID)
        #expect(MultiplayerSnapshotEntityIDs.chest(chest) == chest.multiplayerID)
        #expect(MultiplayerSnapshotEntityIDs.powerUp(powerUp) == powerUp.multiplayerID)
        #expect(MultiplayerSnapshotEntityIDs.projectile(projectile) == projectile.multiplayerID)
    }

    @Test("Host does not reflect legacy client player updates")
    @MainActor
    func hostDoesNotReflectClientPlayerUpdates() async throws {
        let session = FakeMultiplayerSession(localPlayerID: "host")
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600), multiplayerSessionID: "wasteland-survivors-local", multiplayerSessionFactory: { session })
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()

        let first = MultiplayerPlayerState(id: "client", position: CGPoint(x: 10, y: 0), color: .red, sessionStartedAt: 10)
        session.deliver(try MultiplayerWireMessage.playerUpdate(first).encoded())
        try await Task.sleep(for: .milliseconds(50))
        scene.update(1)

        let second = MultiplayerPlayerState(id: "client", position: CGPoint(x: 100, y: 0), color: .red, sessionStartedAt: 10)
        session.deliver(try MultiplayerWireMessage.playerUpdate(second).encoded())
        try await Task.sleep(for: .milliseconds(50))
        scene.update(1.016)

        #expect(scene.remotePlayers["client"] == nil)
    }

    @Test("MultipeerConnectivity uses the transport identity in peer callbacks")
    func multipeerConnectivityUsesTransportIdentityInPeerCallbacks() {
        let session = MultipeerConnectivitySession(playerName: "Test Player")

        #expect(session.peerDisplayName == session.localPeerID)
    }

    @Test("MultipeerConnectivity remains connecting until a peer actually connects")
    func multipeerConnectivityDoesNotReportPrematureConnection() {
        let session = MultipeerConnectivitySession(playerName: "Test Player")

        session.connect()
        defer { session.disconnect() }

        #expect(session.state == .connecting)
        #expect(session.connectedPeerIDs.isEmpty)
    }
}
