import CoreGraphics
import SpriteKit
import Testing
@testable import Wasteland_Survivors

@MainActor
private final class FakeMultiplayerSession: LocalMultiplayerNetworkSession {
    weak var delegate: LocalMultiplayerNetworkSessionDelegate?
    let localPlayerID: String
    private(set) var started = false
    private(set) var sentData: [Data] = []

    init(localPlayerID: String) {
        self.localPlayerID = localPlayerID
    }

    func start() { started = true }
    func stop() {}
    func send(_ data: Data) { sentData.append(data) }

    func deliver(_ data: Data) {
        delegate?.networkSession(self, didReceive: data)
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
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()

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
    }

    @Test("Client applies the host board snapshot to its real scene")
    @MainActor
    func clientAppliesBoardSnapshot() async throws {
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()

        let board = MultiplayerBoardState(
            hostID: "host",
            players: [
                MultiplayerPlayerState(id: "host", position: CGPoint(x: 100, y: 100), color: .blue, health: 70, weapon: .rifle),
                MultiplayerPlayerState(id: "client", position: CGPoint(x: 20, y: 30), color: .red, health: 80, weapon: .shotgun)
            ],
            zombies: [MultiplayerZombieState(id: "zombie-1", x: 40, y: 50, health: 45, rotation: 0)],
            chests: [MultiplayerChestState(id: "chest-1", x: 60, y: 70)],
            powerUps: [MultiplayerPowerUpState(id: "powerup-1", x: 80, y: 90, type: .damage)],
            projectiles: [MultiplayerProjectileState(id: "projectile-1", x: 100, y: 110, angle: 0, weapon: .pistol, damage: 30)],
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

    @Test("Player input round-trips with its sequence number")
    func playerInputRoundTrips() throws {
        let input = MultiplayerPlayerInput(
            playerID: "client",
            sequence: 17,
            movement: CGVector(dx: 1, dy: -1),
            aimAngle: 0.75,
            wantsToAttack: true
        )

        let decoded = try MultiplayerWireMessage.decode(
            MultiplayerWireMessage.playerInput(input).encoded()
        )

        #expect(decoded == .playerInput(input))
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

    @Test("Client ignores snapshots from a different host")
    @MainActor
    func clientIgnoresSnapshotsFromDifferentHost() async throws {
        let session = FakeMultiplayerSession(localPlayerID: "client")
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600), multiplayerSessionFactory: { session })
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()

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

    @Test("Host reflects client movement through the remote player target")
    @MainActor
    func hostReflectsClientMovement() async throws {
        let session = FakeMultiplayerSession(localPlayerID: "host")
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600), multiplayerSessionFactory: { session })
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

        let reflectedX = try #require(scene.remotePlayers["client"]?.position.x)
        #expect(reflectedX > 10)
        #expect(reflectedX < 100)
    }
}
