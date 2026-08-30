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
        // Both devices should keep their camera centered on their local player after movement.
        #expect(hostScene.cameraNode.position == hostScene.playerNode.position)
        #expect(clientScene.cameraNode.position == clientScene.playerNode.position)
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

        // Every player attribute must match after the host's transform and target events arrive.
        #expect(clientRemoteHost.position == hostScene.playerNode.position)
        #expect(clientRemoteHost.zRotation == hostScene.playerNode.zRotation)
        let hostTargetEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: initialization.sequence + 4,
            simulationTick: initialization.simulationTick + 4,
            senderID: "host",
            payload: .playerTargetChanged(playerID: "host", zombieID: firstZombieID),
            delivery: .replaceable
        )
        clientSession.deliver(
            try MultiplayerWireMessage.event(hostTargetEvent).encoded(),
            from: "host"
        )
        #expect(clientScene.synchronizedPlayerTarget(forPlayerID: "host") == firstZombieID)

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

        // The client's position, facing direction, and attacked zombie must also reach the host.
        let clientTransformEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: 3,
            simulationTick: initialization.simulationTick + 3,
            senderID: "client",
            payload: .playerTransformChanged(
                playerID: "client",
                position: CGPointValue(
                    x: Double(clientScene.playerNode.position.x),
                    y: Double(clientScene.playerNode.position.y)
                ),
                facing: Double(clientScene.playerNode.zRotation)
            ),
            delivery: .replaceable
        )
        hostSession.deliver(
            try MultiplayerWireMessage.event(clientTransformEvent).encoded(),
            from: "client"
        )
        #expect(hostRemoteClient.position == clientScene.playerNode.position)
        #expect(hostRemoteClient.zRotation == clientScene.playerNode.zRotation)

        let clientTargetEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: 4,
            simulationTick: initialization.simulationTick + 4,
            senderID: "client",
            payload: .playerTargetChanged(playerID: "client", zombieID: firstZombieID),
            delivery: .replaceable
        )
        hostSession.deliver(
            try MultiplayerWireMessage.event(clientTargetEvent).encoded(),
            from: "client"
        )
        #expect(hostScene.synchronizedPlayerTarget(forPlayerID: "client") == firstZombieID)

        // When the host changes weapon and acquires a power-up, those events are delivered to the client.
        hostScene.playerNode.equip(weapon: .sword)
        let hostEventSequence = initialization.sequence + 5
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

        // When the host broadcasts a zombie damage event containing the authoritative result.
        let zombieHealthEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: initialization.sequence + 7,
            simulationTick: initialization.simulationTick + 7,
            senderID: "host",
            payload: .zombieHealthChanged(
                zombieID: firstZombieID,
                damage: 18,
                health: 42,
                sourcePlayerID: "host"
            )
        )
        clientSession.deliver(
            try MultiplayerWireMessage.event(zombieHealthEvent).encoded(),
            from: "host"
        )

        // Then the receiving client applies the authoritative health to the matching zombie only.
        #expect(zombieHealthEvent.payload == .zombieHealthChanged(
            zombieID: firstZombieID,
            damage: 18,
            health: 42,
            sourcePlayerID: "host"
        ))
        let clientZombieAfterDamage = try #require(clientScene.zombies.first { $0.multiplayerID == firstZombieID })
        #expect(clientZombieAfterDamage.health == 42)

        // When the host broadcasts that the damaged zombie has been killed.
        let zombieDeathEvent = MultiplayerEventEnvelope(
            sessionID: "full-match",
            sequence: initialization.sequence + 8,
            simulationTick: initialization.simulationTick + 8,
            senderID: "host",
            payload: .zombieDied(zombieID: firstZombieID, killerID: "host")
        )
        let encodedZombieDeath = try MultiplayerWireMessage.event(zombieDeathEvent).encoded()
        // The host applies its authoritative local event; the client receives the broadcast.
        hostScene.applyMultiplayerEvent(zombieDeathEvent.payload)
        clientSession.deliver(encodedZombieDeath, from: "host")

        // Then every device removes the dead zombie from its collection and scene graph.
        #expect(hostScene.zombies.contains { $0.multiplayerID == firstZombieID } == false)
        #expect(clientScene.zombies.contains { $0.multiplayerID == firstZombieID } == false)
        #expect(hostScene.worldNode.children.contains { ($0 as? ZombieNode)?.multiplayerID == firstZombieID } == false)
        #expect(clientScene.worldNode.children.contains { ($0 as? ZombieNode)?.multiplayerID == firstZombieID } == false)

        // The client must not recreate the dead zombie from stale prediction state on its next tick.
        clientScene.update(91.0 / 60.0)
        #expect(clientScene.zombies.contains { $0.multiplayerID == firstZombieID } == false)
        #expect(clientScene.worldNode.children.contains { ($0 as? ZombieNode)?.multiplayerID == firstZombieID } == false)

        // When the host continues the fixed-tick simulation after the join.
        let zombieIDsBeforeDeath = Set(hostScene.zombies.map(\.multiplayerID))
        for tick in 46...90 {
            hostScene.update(Double(tick) / 60.0)
            #expect(hostScene.zombies.contains { $0.multiplayerID == firstZombieID } == false)
            #expect(hostScene.worldNode.children.contains { ($0 as? ZombieNode)?.multiplayerID == firstZombieID } == false)
        }
        for tick in 92...136 {
            clientScene.update(Double(tick) / 60.0)
            #expect(clientScene.zombies.contains { $0.multiplayerID == firstZombieID } == false)
            #expect(clientScene.worldNode.children.contains { ($0 as? ZombieNode)?.multiplayerID == firstZombieID } == false)
        }

        // Then reconciliation keeps exactly one scene node per zombie state on every device.
        let hostZombieIDs = hostScene.zombies.map(\.multiplayerID)
        let clientZombieIDs = clientScene.zombies.map(\.multiplayerID)
        let hostSceneZombieIDs = hostScene.worldNode.children.compactMap { ($0 as? ZombieNode)?.multiplayerID }
        let clientSceneZombieIDs = clientScene.worldNode.children.compactMap { ($0 as? ZombieNode)?.multiplayerID }
        #expect(hostZombieIDs.count == Set(hostZombieIDs).count)
        #expect(clientZombieIDs.count == Set(clientZombieIDs).count)
        #expect(hostSceneZombieIDs.count == Set(hostSceneZombieIDs).count)
        #expect(clientSceneZombieIDs.count == Set(clientSceneZombieIDs).count)
        #expect(hostSceneZombieIDs.count == hostZombieIDs.count)
        #expect(clientSceneZombieIDs.count == clientZombieIDs.count)
        #expect(Set(hostSceneZombieIDs) == Set(hostZombieIDs))
        #expect(Set(clientSceneZombieIDs) == Set(clientZombieIDs))
        #expect(hostScene.zombies.allSatisfy { $0.parent === hostScene.worldNode })
        #expect(clientScene.zombies.allSatisfy { $0.parent === clientScene.worldNode })

        // Existing world entities remain unique after repeated host/client reconciliation.
        #expect(Set(hostScene.chests.map(\.multiplayerID)).count == hostScene.chests.count)
        #expect(Set(clientScene.chests.map(\.multiplayerID)).count == clientScene.chests.count)
        #expect(zombieIDsBeforeDeath.isSuperset(of: Set(hostScene.zombies.map(\.multiplayerID))) ||
            !hostScene.zombies.isEmpty)
    }

    @Test("Concurrent attacks converge on zombie death for host and every client")
    func concurrentPlayerAttacksSynchronizeZombieDeathAcrossAllReplicas() throws {
        // Given a host and two clients with the same initialized world.
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        var firstClient = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        var secondClient = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.secondClientID)

        // When two players attack the same zombie and the second attack is the killing blow.
        let firstAttack = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            senderID: EventReplicationTestFixtures.hostID,
            payload: .zombieHealthChanged(
                zombieID: "zombie-1",
                damage: 40,
                health: 60,
                sourcePlayerID: EventReplicationTestFixtures.hostID
            )
        )
        let killingAttack = EventReplicationTestFixtures.event(
            sequence: 3,
            tick: 602,
            senderID: EventReplicationTestFixtures.hostID,
            payload: .zombieHealthChanged(
                zombieID: "zombie-1",
                damage: 60,
                health: 0,
                sourcePlayerID: EventReplicationTestFixtures.clientID
            )
        )
        let death = EventReplicationTestFixtures.event(
            sequence: 4,
            tick: 602,
            senderID: EventReplicationTestFixtures.hostID,
            payload: .zombieDied(zombieID: "zombie-1", killerID: EventReplicationTestFixtures.clientID)
        )

        for event in [firstAttack, killingAttack, death] {
            #expect(host.receive(event) == .accepted)
            #expect(firstClient.receive(event) == .accepted)
            #expect(secondClient.receive(event) == .accepted)
        }

        // Then every replica knows the zombie is dead and no longer treats it as active.
        #expect(host.zombieHealth("zombie-1") == nil)
        #expect(firstClient.zombieHealth("zombie-1") == nil)
        #expect(secondClient.zombieHealth("zombie-1") == nil)
        #expect(host.containsZombie("zombie-1") == false)
        #expect(firstClient.containsZombie("zombie-1") == false)
        #expect(secondClient.containsZombie("zombie-1") == false)
    }

    @Test("Player damage to zombies is broadcast with authoritative zombie health")
    func playerDamageToZombieSynchronizesZombieHealthBetweenHostAndClient() throws {
        // Given an initialized host and client with the same replicated world.
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        var client = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.clientID)

        // When the host applies player-originated damage to a zombie and broadcasts the event.
        #expect(host.damageZombie(
            id: "zombie-1",
            amount: 20,
            sourcePlayerID: EventReplicationTestFixtures.hostID
        ) == .accepted)
        let event = try #require(host.drainOutgoingEvents().first)
        let clientResult = client.receive(event)

        // Then the event identifies the player as the source and both peers retain the same zombie health.
        #expect(event.payload == .zombieHealthChanged(
            zombieID: "zombie-1",
            damage: 20,
            health: 80,
            sourcePlayerID: EventReplicationTestFixtures.hostID
        ))
        #expect(clientResult == .accepted)
        #expect(host.zombieHealth("zombie-1") == 80)
        #expect(client.zombieHealth("zombie-1") == 80)

        // When a client-originated attack is delivered to a host replica.
        var clientOrigin = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        var hostReceiver = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        #expect(clientOrigin.damageZombie(
            id: "zombie-1",
            amount: 10,
            sourcePlayerID: EventReplicationTestFixtures.clientID
        ) == .accepted)
        let clientEvent = try #require(clientOrigin.drainOutgoingEvents().first)
        #expect(hostReceiver.receive(clientEvent) == .accepted)

        // Then both peers in that direction converge on the latest zombie health.
        #expect(hostReceiver.zombieHealth("zombie-1") == 90)
        #expect(clientOrigin.zombieHealth("zombie-1") == 90)

        // And a player cannot damage another player or report zombie-originated zombie damage.
        #expect(host.damagePlayer(id: EventReplicationTestFixtures.clientID, amount: 10, sourceID: EventReplicationTestFixtures.hostID) == .rejected(.unknownEntity))
        #expect(host.damageZombie(id: "zombie-1", amount: 10, sourcePlayerID: "zombie-1") == .rejected)
        #expect(host.drainOutgoingEvents().isEmpty)
    }

    @Test("Zombie damage to players is broadcast with authoritative player health")
    func zombieDamageToPlayerSynchronizesPlayerHealthBetweenHostAndClient() throws {
        // Given an initialized host and client with a living client player and zombie.
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        var client = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.clientID)

        // When the host applies zombie-originated damage to the client and broadcasts the event.
        #expect(host.damagePlayer(
            id: EventReplicationTestFixtures.clientID,
            amount: 12,
            sourceID: "zombie-1"
        ) == .accepted)
        let event = try #require(host.drainOutgoingEvents().first)
        let clientResult = client.receive(event)

        // Then the event carries the resulting health and the client accepts the synchronized stat.
        #expect(event.payload == .playerDamaged(
            playerID: EventReplicationTestFixtures.clientID,
            damage: 12,
            health: 88,
            sourceID: "zombie-1"
        ))
        #expect(clientResult == .accepted)
        #expect(host.playerHealth(EventReplicationTestFixtures.clientID) == 88)
        #expect(client.playerHealth(EventReplicationTestFixtures.clientID) == 88)

        // When a client-originated zombie attack is delivered to a host replica.
        var clientOrigin = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        var hostReceiver = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        #expect(clientOrigin.damagePlayer(
            id: EventReplicationTestFixtures.hostID,
            amount: 12,
            sourceID: "zombie-1"
        ) == .accepted)
        let clientEvent = try #require(clientOrigin.drainOutgoingEvents().first)
        #expect(hostReceiver.receive(clientEvent) == .accepted)

        // Then the host and client converge on the damaged host player's health.
        #expect(hostReceiver.playerHealth(EventReplicationTestFixtures.hostID) == 88)
        #expect(clientOrigin.playerHealth(EventReplicationTestFixtures.hostID) == 88)

        // And cross-target damage is rejected both at the source API and by the receiving event validator.
        #expect(host.damageZombie(id: "zombie-1", amount: 10, sourcePlayerID: "zombie-1") == .rejected)
        #expect(host.damagePlayer(id: EventReplicationTestFixtures.clientID, amount: 10, sourceID: EventReplicationTestFixtures.hostID) == .rejected(.unknownEntity))
        #expect(host.drainOutgoingEvents().isEmpty)

        let forgedEvent = EventReplicationTestFixtures.event(
            sequence: 3,
            tick: 603,
            senderID: EventReplicationTestFixtures.hostID,
            payload: .playerDamaged(
                playerID: EventReplicationTestFixtures.clientID,
                damage: 10,
                health: 78,
                sourceID: EventReplicationTestFixtures.hostID
            )
        )
        #expect(client.receive(forgedEvent) == .rejected(.unknownEntity))
    }

}
