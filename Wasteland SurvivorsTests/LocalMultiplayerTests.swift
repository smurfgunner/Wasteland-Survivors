import CoreGraphics
import SpriteKit
import Testing
@testable import Wasteland_Survivors

@MainActor
final class FakeMultiplayerSession: MultiplayerTransport {
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
        case let .playerInput(value): senderID = value.playerID
        case let .gameplayEvent(value): senderID = value.hostID
        case let .initialization(value): senderID = value.hostID
        case let .event(value): senderID = value.senderID
        case .recovery: senderID = peerID ?? "recovery"
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

    @Test("Host local player moves on the host screen while the remote client sees the same movement")
    @MainActor
    func hostLocalPlayerMovesOnHostScreenDuringMultiplayer() throws {
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
            sessionID: "match",
            peerID: "client",
            startedAt: 9_999_999_999,
            protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match",
            peerID: "client",
            protocolVersion: 1
        )).encoded(), from: "client")

        let initialWorldPosition = scene.playerNode.position
        let initialScreenPosition = scene.cameraNode.convert(
            scene.playerNode.position,
            from: scene.worldNode
        )
        scene.movementVector = CGVector(dx: 1, dy: 0)

        scene.update(0)
        scene.update(1.0 / 60.0)

        let currentScreenPosition = scene.cameraNode.convert(
            scene.playerNode.position,
            from: scene.worldNode
        )
        #expect(scene.playerNode.position.x > initialWorldPosition.x)
        #expect(currentScreenPosition.x > initialScreenPosition.x)
    }

    @Test("A host renders every independently joined client")
    @MainActor
    func hostRendersEveryJoinedClient() throws {
        let session = FakeMultiplayerSession(localPlayerID: "host")
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "match",
            multiplayerSessionFactory: { session }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startLocalMultiplayer()

        for clientID in ["client-1", "client-2"] {
            session.connectedPeerIDs.insert(clientID)
            session.deliver(try MultiplayerWireMessage.hello(.init(
                sessionID: "match",
                peerID: clientID,
                startedAt: clientID == "client-1" ? 9_999_999_999 : 10_000_000_000,
                protocolVersion: 1
            )).encoded())
            session.deliver(try MultiplayerWireMessage.joinRequest(.init(
                sessionID: "match",
                peerID: clientID,
                protocolVersion: 1
            )).encoded(), from: clientID)
        }

        #expect(Set(scene.remotePlayers.keys) == ["client-1", "client-2"])
        #expect(scene.remotePlayers.values.allSatisfy { $0.parent === scene.worldNode })
    }

    @Test("A late client receives the active host world after gameplay has advanced")
    @MainActor
    func lateClientReceivesActiveWorldAfterGameplayHasAdvanced() throws {
        let hostSession = FakeMultiplayerSession(localPlayerID: "host")
        let hostScene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "match",
            multiplayerSessionFactory: { hostSession }
        )
        let hostView = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        hostScene.didMove(to: hostView)
        hostScene.startLocalMultiplayer()
        hostScene.movementVector = CGVector(dx: 1, dy: 0)
        hostScene.update(0)
        hostScene.update(1.0 / 60.0)
        hostScene.update(2.0 / 60.0)

        hostSession.connectedPeerIDs.insert("client")
        hostSession.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "client",
            startedAt: 9_999_999_999,
            protocolVersion: 1
        )).encoded())
        hostSession.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match",
            peerID: "client",
            protocolVersion: 1
        )).encoded(), from: "client")

        let initialization = try #require(hostSession.sentData.compactMap { data -> MultiplayerInitializationPayload? in
            guard case let .initialization(payload) = try? MultiplayerWireMessage.decode(data) else {
                return nil
            }
            return payload
        }.last)

        let clientSession = FakeMultiplayerSession(localPlayerID: "client")
        let clientScene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            multiplayerSessionID: "match",
            multiplayerSessionFactory: { clientSession }
        )
        let clientView = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        clientScene.didMove(to: clientView)
        clientScene.startLocalMultiplayer()
        clientSession.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "match",
            hostID: "host",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())
        clientSession.deliver(try MultiplayerWireMessage.initialization(initialization).encoded(), from: "host")

        #expect(clientScene.remotePlayers["host"]?.position == hostScene.playerNode.position)
        #expect(clientScene.zombies.map(\.multiplayerID) == hostScene.zombies.map(\.multiplayerID))
        #expect(clientScene.chests.map(\.multiplayerID) == hostScene.chests.map(\.multiplayerID))
        #expect(clientScene.powerUps.map(\.multiplayerID) == hostScene.powerUps.map(\.multiplayerID))
    }

    @Test("Repeated initialization does not duplicate client world entities")
    @MainActor
    func repeatedInitializationDoesNotDuplicateClientWorldEntities() throws {
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
            sessionID: "match",
            hostID: "host",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())

        let payload = MultiplayerInitializationPayload(
            sessionID: "match",
            sequence: 1,
            simulationTick: 12,
            seed: 42,
            hostID: "host",
            players: [
                MultiplayerInitializationPlayer(id: "host", position: .zero),
                MultiplayerInitializationPlayer(id: "client", position: CGPointValue(x: 80, y: 0))
            ],
            zombies: [
                MultiplayerInitializationZombie(
                    id: "zombie-1",
                    position: CGPointValue(x: 120, y: 0),
                    health: 100
                )
            ]
        )
        let message = try MultiplayerWireMessage.initialization(payload).encoded()

        session.deliver(message, from: "host")
        let firstCounts = (scene.zombies.count, scene.chests.count, scene.powerUps.count)
        session.deliver(message, from: "host")

        #expect((scene.zombies.count, scene.chests.count, scene.powerUps.count) == firstCounts)
        #expect(Set(scene.zombies.map(\.multiplayerID)).count == scene.zombies.count)
        #expect(Set(scene.chests.map(\.multiplayerID)).count == scene.chests.count)
        #expect(Set(scene.powerUps.map(\.multiplayerID)).count == scene.powerUps.count)
    }

    @Test("Disconnecting a client removes its host-side player visual")
    @MainActor
    func disconnectingClientRemovesHostSidePlayerVisual() throws {
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
            sessionID: "match",
            peerID: "client",
            startedAt: 9_999_999_999,
            protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match",
            peerID: "client",
            protocolVersion: 1
        )).encoded(), from: "client")

        let player = try #require(scene.remotePlayers["client"])
        #expect(player.parent === scene.worldNode)
        session.peerDisconnected("client")

        #expect(scene.remotePlayers["client"] == nil)
        #expect(player.parent == nil)
    }

    @Test("A client renders a host melee attack from the replicated event")
    @MainActor
    func clientRendersHostMeleeAttackFromReplicatedEvent() throws {
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
            sessionID: "match",
            hostID: "host",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())
        let initialization = MultiplayerInitializationPayload(
            sessionID: "match",
            sequence: 1,
            simulationTick: 1,
            seed: 42,
            hostID: "host",
            players: [
                MultiplayerInitializationPlayer(id: "host", position: CGPointValue(x: 20, y: 0)),
                MultiplayerInitializationPlayer(id: "client", position: .zero)
            ],
            zombies: [
                MultiplayerInitializationZombie(
                    id: "zombie-1",
                    position: CGPointValue(x: 60, y: 0),
                    health: 100
                )
            ]
        )
        session.deliver(try MultiplayerWireMessage.initialization(initialization).encoded(), from: "host")

        let event = MultiplayerEventEnvelope(
            sessionID: "match",
            sequence: 2,
            simulationTick: 2,
            senderID: "host",
            payload: .meleeAttack(attackID: "attack-1", playerID: "host")
        )
        session.deliver(try MultiplayerWireMessage.event(event).encoded(), from: "host")

        #expect(scene.worldNode.children.contains { $0 is MeleeSlashNode })
    }

    @Test("Client ignores deprecated match-ended messages outside the event contract")
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

        #expect(scene.isGameOver == false)
    }

    @Test("Client migrates when the authoritative host disconnects")
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

        #expect(scene.isGameOver == false)
        #expect(session.sentData.contains { data in
            guard case let .hostAnnouncement(announcement) = try? MultiplayerWireMessage.decode(data) else {
                return false
            }
            return announcement.hostID == "client"
        })
    }

    @Test("Client keeps local rendering close to predicted movement during sustained input")
    @MainActor
    func clientKeepsLocalRenderingCloseToPredictedMovementDuringSustainedInput() throws {
        // Given a client predicting one second of uninterrupted movement.
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
            sessionID: "match",
            hostID: "host",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())
        scene.movementVector = CGVector(dx: 1, dy: 0)

        // When the render loop advances for one second.
        scene.update(0)
        for frame in 1...60 {
            scene.update(Double(frame) / 60.0)
        }

        // Then the visible player stays close to the continuously predicted position.
        // At the game's movement speed, one second is approximately 180 points.
        #expect(scene.playerNode.position.x >= 165)
    }

    @Test("Client catches up after a local direction reversal")
    @MainActor
    func clientCatchesUpAfterLocalDirectionReversal() throws {
        // Given a client that has been predicting movement to the right.
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
            sessionID: "match",
            hostID: "host",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())
        scene.movementVector = CGVector(dx: 1, dy: 0)
        scene.update(0)
        for frame in 1...30 {
            scene.update(Double(frame) / 60.0)
        }

        // When the player reverses direction for another half second.
        scene.movementVector = CGVector(dx: -1, dy: 0)
        for frame in 31...60 {
            scene.update(Double(frame) / 60.0)
        }

        // Then the visible player has caught up with the predicted reversal.
        #expect(abs(scene.playerNode.position.x) <= 18)
    }

    @Test("Client submits prediction input once per rendered update")
    @MainActor
    func clientSendsPredictionInputAtStableCadence() throws {
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
            sessionID: "match",
            hostID: "host",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())

        scene.movementVector = CGVector(dx: 1, dy: 0)
        scene.update(0)
        for frame in 1...60 {
            scene.update(Double(frame) / 60.0)
        }

        let inputs = session.sentData.compactMap { data -> MultiplayerPlayerInput? in
            guard case let .playerInput(input) = try? MultiplayerWireMessage.decode(data) else {
                return nil
            }
            return input
        }

        #expect(inputs.count == 60)
        #expect(inputs.map(\.sequence) == Array(1...60))
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

    @Test("A newly joined client renders every seeded world entity from initialization")
    @MainActor
    func newlyJoinedClientRendersSeededWorldEntitiesFromInitialization() throws {
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
            sessionID: "match",
            hostID: "host",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())

        let payload = MultiplayerInitializationPayload(
            sessionID: "match",
            sequence: 1,
            simulationTick: 240,
            seed: 0xCAFE,
            hostID: "host",
            players: [
                MultiplayerInitializationPlayer(id: "host", position: CGPointValue(x: 100, y: 20)),
                MultiplayerInitializationPlayer(id: "client", position: CGPointValue(x: 180, y: 20))
            ],
            zombies: [
                MultiplayerInitializationZombie(
                    id: "zombie-42",
                    position: CGPointValue(x: 260, y: -40),
                    health: 73
                )
            ]
        )

        session.deliver(try MultiplayerWireMessage.initialization(payload).encoded(), from: "host")

        #expect(scene.zombies.map(\.multiplayerID) == ["zombie-42"])
        #expect(scene.zombies.first?.position == CGPoint(x: 260, y: -40))
        #expect(scene.chests.map(\.multiplayerID) == ["chest-1", "chest-2", "chest-3", "chest-4", "chest-5", "chest-6", "chest-7", "chest-8"])
        #expect(scene.powerUps.map(\.multiplayerID) == ["power-up-1"])
        #expect(scene.worldNode.children.contains { $0 is ZombieNode && $0.parent === scene.worldNode })
        #expect(scene.worldNode.children.contains { $0 is ChestNode && $0.parent === scene.worldNode })
        #expect(scene.worldNode.children.contains { $0 is PowerUpNode && $0.parent === scene.worldNode })
    }

    @Test("A client keeps seeded entity IDs and positions after an authoritative recovery")
    @MainActor
    func clientKeepsSeededEntityIDsAndPositionsAfterRecovery() throws {
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
            sessionID: "match",
            hostID: "host",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())

        let initialization = MultiplayerInitializationPayload(
            sessionID: "match",
            sequence: 1,
            simulationTick: 240,
            seed: 0xCAFE,
            hostID: "host",
            players: [
                MultiplayerInitializationPlayer(id: "host", position: CGPointValue(x: 100, y: 20)),
                MultiplayerInitializationPlayer(id: "client", position: CGPointValue(x: 180, y: 20))
            ],
            zombies: [
                MultiplayerInitializationZombie(
                    id: "zombie-42",
                    position: CGPointValue(x: 260, y: -40),
                    health: 73
                )
            ]
        )
        session.deliver(try MultiplayerWireMessage.initialization(initialization).encoded(), from: "host")

        let recovery = MultiplayerRecoveryPayload(
            sessionID: "match",
            firstSequence: 1,
            lastSequence: 1,
            simulationTick: 241,
            players: [
                MultiplayerInitializationPlayer(id: "host", position: CGPointValue(x: 100, y: 20)),
                MultiplayerInitializationPlayer(id: "client", position: CGPointValue(x: 180, y: 20))
            ],
            zombies: [
                MultiplayerInitializationZombie(
                    id: "zombie-42",
                    position: CGPointValue(x: 275, y: -35),
                    health: 61
                )
            ],
            activeChests: ["chest-1", "chest-2", "chest-3", "chest-4", "chest-5", "chest-6", "chest-7", "chest-8"],
            activePowerUps: ["power-up-1"],
            score: 4,
            playerTargets: [:],
            zombieTargets: [:],
            equipment: [:],
            removedEntities: [],
            playerDeaths: []
        )

        session.deliver(try MultiplayerWireMessage.recovery(recovery).encoded(), from: "host")

        #expect(scene.zombies.map(\.multiplayerID) == ["zombie-42"])
        #expect(scene.zombies.first?.position == CGPoint(x: 275, y: -35))
        #expect(scene.chests.map(\.multiplayerID) == ["chest-1", "chest-2", "chest-3", "chest-4", "chest-5", "chest-6", "chest-7", "chest-8"])
        #expect(scene.powerUps.map(\.multiplayerID) == ["power-up-1"])
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
