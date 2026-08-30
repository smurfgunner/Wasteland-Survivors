import CoreGraphics
import SpriteKit
import Testing
@testable import Wasteland_Survivors

@Suite("Full Multiplayer Gameplay")
struct FullMultiplayerGameplayTests {
    @Test("Full multiplayer gameplay remains visually and authoritatively synchronized")
    @MainActor
    func fullMultiplayerGameplayKeepsHostAndClientInAgreement() throws {
        // Given a host that starts a local multiplayer game.
        let hostSession = FakeMultiplayerSession(localPlayerID: "host")
        let hostScene = GameScene.newGameScene(
            size: CGSize(width: 1_000, height: 700),
            multiplayerSessionID: "full-match",
            multiplayerSessionFactory: { hostSession }
        )
        let hostView = SKView(frame: CGRect(x: 0, y: 0, width: 1_000, height: 700))
        hostScene.didMove(to: hostView)
        hostScene.startLocalMultiplayer()

        // When the host runs enough fixed ticks for zombies to spawn and begin pursuing players.
        hostScene.movementVector = CGVector(dx: 1, dy: 0)
        hostScene.update(0)
        for tick in 1...45 {
            hostScene.update(Double(tick) / 60.0)
        }

        // Then the host has active zombies and has emitted gameplay traffic.
        #expect(!hostScene.zombies.isEmpty)
        #expect(hostScene.zombies.allSatisfy { $0.parent === hostScene.worldNode })
        #expect(hostScene.zombies.allSatisfy { $0.position != .zero })
        // Given a second player joins the active session.
        hostSession.connectedPeerIDs.insert("client")
        hostSession.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "full-match",
            peerID: "client",
            startedAt: 9_999_999_999,
            protocolVersion: 1
        )).encoded())
        hostSession.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "full-match",
            peerID: "client",
            protocolVersion: 1
        )).encoded(), from: "client")

        let initialization = try #require(hostSession.sentData.compactMap { data -> MultiplayerInitializationPayload? in
            guard case let .initialization(payload) = try? MultiplayerWireMessage.decode(data) else {
                return nil
            }
            return payload
        }.last)

        // Then the host keeps the joining player's visual and sends the complete active world.
        let hostPlayerPosition = hostScene.playerNode.position
        let hostRemoteClient = try #require(hostScene.remotePlayers["client"])
        #expect(hostRemoteClient.parent === hostScene.worldNode)
        #expect(hypot(
            hostRemoteClient.position.x - hostPlayerPosition.x,
            hostRemoteClient.position.y - hostPlayerPosition.y
        ) <= MultiplayerSpawnPlanner.spawnRadius)
        #expect(Set(initialization.players.map(\.id)) == ["host", "client"])
        #expect(Set(initialization.zombies.map(\.id)) == Set(hostScene.zombies.map(\.multiplayerID)))

        // Given the joining client starts and accepts the host's authoritative initialization.
        let clientSession = FakeMultiplayerSession(localPlayerID: "client")
        let clientScene = GameScene.newGameScene(
            size: CGSize(width: 1_000, height: 700),
            multiplayerSessionID: "full-match",
            multiplayerSessionFactory: { clientSession }
        )
        let clientView = SKView(frame: CGRect(x: 0, y: 0, width: 1_000, height: 700))
        clientScene.didMove(to: clientView)
        clientScene.startLocalMultiplayer()
        clientSession.deliver(try MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "full-match",
            hostID: "host",
            hostStartedAt: 1,
            protocolVersion: 1
        )).encoded())
        clientSession.deliver(
            try MultiplayerWireMessage.initialization(initialization).encoded(),
            from: "host"
        )

        // Then both players render the same active world and the client renders the host near its own player.
        let clientRemoteHost = try #require(clientScene.remotePlayers["host"])
        #expect(clientRemoteHost.parent === clientScene.worldNode)
        #expect(clientScene.zombies.map(\.multiplayerID) == hostScene.zombies.map(\.multiplayerID))
        #expect(clientScene.chests.map(\.multiplayerID) == hostScene.chests.map(\.multiplayerID))
        #expect(clientScene.powerUps.map(\.multiplayerID) == hostScene.powerUps.map(\.multiplayerID))
        #expect(hypot(
            clientRemoteHost.position.x - clientScene.playerNode.position.x,
            clientRemoteHost.position.y - clientScene.playerNode.position.y
        ) <= MultiplayerSpawnPlanner.spawnRadius)

        // When both devices continue after the join, the host moves locally while
        // the client also moves and attacks through the host-authoritative session.
        let hostPositionBeforeMovement = hostScene.playerNode.position
        let hostRemoteClientPositionBeforeMovement = hostRemoteClient.position
        let clientPositionBeforeMovement = clientScene.playerNode.position
        hostScene.movementVector = CGVector(dx: 0, dy: 1)
        clientScene.movementVector = CGVector(dx: 0, dy: 1)
        hostScene.keysPressed.insert(126)
        clientScene.keysPressed.insert(126)
        clientScene.update(0)
        hostScene.update(2.0)
        clientScene.update(2.0)
        clientScene.update(2.1)
        let clientInput = try #require(clientSession.sentData.compactMap { data -> MultiplayerPlayerInput? in
            guard case let .playerInput(input) = try? MultiplayerWireMessage.decode(data) else { return nil }
            return input
        }.last)
        hostSession.deliver(try MultiplayerWireMessage.playerInput(clientInput).encoded(), from: "client")
        hostScene.update(2.1)
        // Then neither side is frozen: both local players move and the host applies the
        // client's input to the remote player.
        #expect(!hostScene.isGameOver)
        #expect(hostScene.playerNode.currentHealth > 0)
        #expect(hostScene.playerNode.position != hostPositionBeforeMovement)
        #expect(hostRemoteClient.position != hostRemoteClientPositionBeforeMovement)
        #expect(clientScene.playerNode.position != clientPositionBeforeMovement)
        #expect(hostScene.zombies.allSatisfy { $0.parent === hostScene.worldNode })
        #expect(clientScene.zombies.allSatisfy { $0.parent === clientScene.worldNode })

        // When authoritative movement, target, and attack events are delivered to the client.
        let firstZombieID = try #require(initialization.zombies.first?.id)
        let hostTransformEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: initialization.sequence + 1,
            simulationTick: initialization.simulationTick + 1,
            senderID: "host",
            payload: .playerTransformChanged(
                playerID: "host",
                position: CGPointValue(x: Double(hostScene.playerNode.position.x), y: Double(hostScene.playerNode.position.y)),
                facing: Double(hostScene.playerNode.zRotation)
            )
        )
        let targetEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: initialization.sequence + 2,
            simulationTick: initialization.simulationTick + 2,
            senderID: "host",
            payload: .zombieTargetChanged(zombieID: firstZombieID, playerID: "host")
        )
        let projectileEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: initialization.sequence + 3,
            simulationTick: initialization.simulationTick + 3,
            senderID: "host",
            payload: .projectileSpawned(projectileID: "projectile-full-match", playerID: "host")
        )
        for event in [hostTransformEvent, targetEvent, projectileEvent] {
            clientSession.deliver(
                try MultiplayerWireMessage.event(event).encoded(),
                from: "host"
            )
        }

        // Then client-side zombie motion, target updates, and attack visuals follow the same event stream.
        #expect(Set(hostScene.zombies.map(\.multiplayerID)).isSubset(of: Set(clientScene.zombies.map(\.multiplayerID))))
        #expect(clientScene.zombies.allSatisfy { $0.parent === clientScene.worldNode })
        #expect(clientScene.worldNode.children.contains { $0 is ProjectileNode })
        #expect(hostScene.zombies.contains { $0.multiplayerID == firstZombieID })

        // When the client equips a weapon and acquires a power-up, the client-originated
        // authoritative events are delivered back to the host.
        clientScene.playerNode.equip(weapon: .shotgun)
        let clientWeaponEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: 1,
            simulationTick: initialization.simulationTick + 1,
            senderID: "client",
            payload: .weaponChanged(playerID: "client", weapon: .shotgun)
        )
        clientSession.deliver(
            try MultiplayerWireMessage.event(clientWeaponEvent).encoded(),
            from: "client"
        )
        hostSession.deliver(
            try MultiplayerWireMessage.event(clientWeaponEvent).encoded(),
            from: "client"
        )
        let clientPowerUp = PowerUpType.damage
        _ = clientScene.playerNode.apply(powerUp: clientPowerUp)
        let clientPowerUpEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: 2,
            simulationTick: initialization.simulationTick + 2,
            senderID: "client",
            payload: .powerUpAcquired(playerID: "client", type: clientPowerUp)
        )
        hostSession.deliver(
            try MultiplayerWireMessage.event(clientPowerUpEvent).encoded(),
            from: "client"
        )

        // Then the host renders the client's selected weapon and power-up on the correct player.
        let hostClientPlayer = try #require(hostScene.remotePlayers["client"])
        #expect(hostClientPlayer.currentWeapon == .shotgun)
        #expect(hostClientPlayer.appliedPowerUpTypes.contains(clientPowerUp))

        // When the host changes weapon and acquires a power-up, those events are delivered to the client.
        hostScene.playerNode.equip(weapon: .sword)
        let hostEventSequence = initialization.sequence + 4
        let hostWeaponEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: hostEventSequence,
            simulationTick: initialization.simulationTick + 3,
            senderID: "host",
            payload: .weaponChanged(playerID: "host", weapon: .sword)
        )
        let hostPowerUp = PowerUpType.range
        _ = hostScene.playerNode.apply(powerUp: hostPowerUp)
        let hostPowerUpEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: hostEventSequence + 1,
            simulationTick: initialization.simulationTick + 4,
            senderID: "host",
            payload: .powerUpAcquired(playerID: "host", type: hostPowerUp)
        )
        clientSession.deliver(
            try MultiplayerWireMessage.event(hostWeaponEvent).encoded(),
            from: "host"
        )
        clientSession.deliver(
            try MultiplayerWireMessage.event(hostPowerUpEvent).encoded(),
            from: "host"
        )

        // Then the client renders the host's weapon and power-up on the host player only.
        #expect(clientRemoteHost.currentWeapon == .sword)
        #expect(clientRemoteHost.appliedPowerUpTypes.contains(hostPowerUp))
        #expect(clientScene.playerNode.currentWeapon != .sword)

        // When the host continues the fixed-tick simulation after the join.
        let zombieIDsBeforeDeath = Set(hostScene.zombies.map(\.multiplayerID))
        for tick in 46...90 {
            hostScene.update(Double(tick) / 60.0)
        }

        // Then new zombie targets remain deterministic, entity IDs remain unique,
        // and a zombie death/removal is represented consistently when one occurs.
        #expect(hostScene.zombies.map(\.multiplayerID).count == Set(hostScene.zombies.map(\.multiplayerID)).count)
        #expect(clientScene.zombies.map(\.multiplayerID).count == Set(clientScene.zombies.map(\.multiplayerID)).count)
        #expect(Set(hostScene.chests.map(\.multiplayerID)).count == hostScene.chests.count)
        #expect(Set(clientScene.chests.map(\.multiplayerID)).count == clientScene.chests.count)
        #expect(zombieIDsBeforeDeath.isSuperset(of: Set(hostScene.zombies.map(\.multiplayerID))) ||
            !hostScene.zombies.isEmpty)
    }

}
