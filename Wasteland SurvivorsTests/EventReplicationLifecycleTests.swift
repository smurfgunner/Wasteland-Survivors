import CoreGraphics
import SpriteKit
import Testing
@testable import Wasteland_Survivors

@Suite("Event Replication Entity Lifecycle")
struct EventReplicationLifecycleTests {
    @Test("Chest collection removes the chest from every client")
    func chestCollectionRemovesEntityEverywhere() {
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        var client = EventReplicationTestFixtures.initializedSystem()

        host.collectItem(entityID: "chest-1", collectorID: EventReplicationTestFixtures.hostID, result: .weapon(.rifle))
        for event in host.drainOutgoingEvents() {
            _ = client.receive(event)
        }

        #expect(client.containsChest("chest-1") == false)
    }

    @Test("Power-up collection removes the power-up from every client")
    func powerUpCollectionRemovesEntityEverywhere() {
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        var client = EventReplicationTestFixtures.initializedSystem()

        host.collectItem(entityID: "power-up-1", collectorID: EventReplicationTestFixtures.hostID, result: .powerUp(.damage))
        for event in host.drainOutgoingEvents() {
            _ = client.receive(event)
        }

        #expect(client.containsPowerUp("power-up-1") == false)
    }

    @Test("A client chest pickup synchronizes removal and weapon reward with host and other clients")
    func clientChestPickupSynchronizesAcrossAllParties() throws {
        // Given a host, the collecting client, and two observing clients share the same chest.
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        var collector = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        var firstObserver = EventReplicationTestFixtures.initializedSystem(localPlayerID: "observer-1")
        var secondObserver = EventReplicationTestFixtures.initializedSystem(localPlayerID: "observer-2")

        // When the collecting client picks up the chest and its event is delivered to every other party.
        #expect(collector.collectItem(
            entityID: "chest-1",
            collectorID: EventReplicationTestFixtures.clientID,
            result: .weapon(.rifle)
        ) == .accepted)
        let outgoingEvents = collector.drainOutgoingEvents()
        #expect(outgoingEvents.count == 1)
        let event = try #require(outgoingEvents.first)
        #expect(host.receive(event) == .accepted)
        #expect(firstObserver.receive(event) == .accepted)
        #expect(secondObserver.receive(event) == .accepted)

        // Then every party removes the same chest and agrees on the collector's weapon.
        for party in [host, collector, firstObserver, secondObserver] {
            #expect(party.containsChest("chest-1") == false)
            #expect(party.weapon(of: EventReplicationTestFixtures.clientID) == .rifle)
        }
        #expect(event.payload == .itemCollected(
            entityID: "chest-1",
            collectorID: EventReplicationTestFixtures.clientID,
            result: .weapon(.rifle)
        ))
    }

    @Test("A client power-up pickup synchronizes removal and reward identity with host and other clients")
    func clientPowerUpPickupSynchronizesAcrossAllParties() throws {
        // Given a host, the collecting client, and two observing clients share the same power-up.
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        var collector = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        var firstObserver = EventReplicationTestFixtures.initializedSystem(localPlayerID: "observer-1")
        var secondObserver = EventReplicationTestFixtures.initializedSystem(localPlayerID: "observer-2")

        // When the collecting client picks up the power-up and its event is delivered to every other party.
        #expect(collector.collectItem(
            entityID: "power-up-1",
            collectorID: EventReplicationTestFixtures.clientID,
            result: .powerUp(.damage)
        ) == .accepted)
        let outgoingEvents = collector.drainOutgoingEvents()
        #expect(outgoingEvents.count == 1)
        let event = try #require(outgoingEvents.first)
        #expect(host.receive(event) == .accepted)
        #expect(firstObserver.receive(event) == .accepted)
        #expect(secondObserver.receive(event) == .accepted)

        // Then every party removes the same power-up and receives the exact collector and reward type.
        for party in [host, collector, firstObserver, secondObserver] {
            #expect(party.containsPowerUp("power-up-1") == false)
        }
        #expect(event.payload == .itemCollected(
            entityID: "power-up-1",
            collectorID: EventReplicationTestFixtures.clientID,
            result: .powerUp(.damage)
        ))
    }

    @Test("Chest-open state is applied and remains rendered on every party")
    @MainActor
    func openedChestIsRenderedAsOpenedAcrossAllParties() throws {
        // Given every party renders the same unopened multiplayer chest.
        let partyIDs = ["host", "client-1", "client-2", "client-3"]
        let scenes = partyIDs.map { playerID in
            let session = FakeMultiplayerSession(localPlayerID: playerID)
            let scene = GameScene.newGameScene(
                size: CGSize(width: 1_000, height: 700),
                multiplayerSessionID: "chest-render-session",
                multiplayerSessionFactory: { session }
            )
            scene.didMove(to: SKView(frame: CGRect(x: 0, y: 0, width: 1_000, height: 700)))
            scene.startLocalMultiplayer()
            return scene
        }
        #expect(scenes.allSatisfy { scene in
            scene.chests.contains { $0.multiplayerID == "chest-1" && !$0.isOpened }
        })

        // When the authoritative chest-open result is applied on every party.
        let event = MultiplayerSyncEvent.itemCollected(
            entityID: "chest-1",
            collectorID: "client-1",
            result: .weapon(.rifle)
        )
        scenes.forEach { $0.applyMultiplayerEvent(event) }

        // Then the same chest remains in the scene graph and renders its opened state everywhere.
        for scene in scenes {
            let chest = try #require(scene.chests.first { $0.multiplayerID == "chest-1" })
            #expect(chest.isOpened)
            #expect(chest.parent === scene.worldNode)
        }
    }

    @Test(
        "Each power-up kind is applied once per weapon and player on every party",
        arguments: WeaponType.allCases,
        PowerUpType.allCases
    )
    func eachPowerUpKindAppliesOncePerWeaponPerPlayerAcrossAllParties(
        weapon: WeaponType,
        powerUp: PowerUpType
    ) {
        // Given four parties render the same player with the same selected weapon.
        let players = (0..<4).map { _ -> PlayerNode in
            let player = PlayerNode()
            player.equip(weapon: weapon)
            return player
        }

        // When the same synchronized power-up is delivered twice.
        let firstApplications = players.map { $0.apply(powerUp: powerUp) }
        let valuesAfterFirstDelivery = players.map(weaponValues)
        let secondApplications = players.map { $0.apply(powerUp: powerUp) }
        let valuesAfterDuplicateDelivery = players.map(weaponValues)

        // Then every party applies it once, ignores the duplicate, and renders identical weapon values.
        #expect(firstApplications.allSatisfy { $0 })
        #expect(secondApplications.allSatisfy { !$0 })
        #expect(Set(valuesAfterFirstDelivery).count == 1)
        #expect(valuesAfterDuplicateDelivery == valuesAfterFirstDelivery)
        #expect(players.allSatisfy { $0.appliedPowerUpTypes == [powerUp] })
    }

    @Test("Replicated player damage updates health and the local HUD on every party")
    @MainActor
    func replicatedPlayerDamageUpdatesHealthAndHUDOnEveryParty() {
        // Given four rendered replicas of the damaged player's multiplayer view.
        let scenes = makeLocalPlayerReplicas(playerID: "damaged-player")
        #expect(scenes.allSatisfy { healthLabelText(in: $0) == "HP: 100/100" })

        // When authoritative zombie damage is delivered to every replica.
        let damage = MultiplayerSyncEvent.playerDamaged(
            playerID: "damaged-player",
            damage: 12,
            health: 88,
            sourceID: "zombie-1"
        )
        scenes.forEach { $0.applyMultiplayerEvent(damage) }

        // Then gameplay health and every rendered HUD show the same authoritative value.
        #expect(scenes.allSatisfy { $0.playerNode.currentHealth == 88 })
        #expect(scenes.allSatisfy { healthLabelText(in: $0) == "HP: 88/100" })
        #expect(Set(scenes.compactMap(healthFillScale(in:))).count == 1)
        #expect(scenes.allSatisfy { scene in
            guard let scale = healthFillScale(in: scene) else { return false }
            return abs(scale - 0.88) < 0.0001
        })
    }

    @Test("Replicated player health waits for its cooldown, regenerates, and refreshes every HUD")
    @MainActor
    func replicatedPlayerHealthRegeneratesAndUpdatesEveryHUD() {
        // Given every party has applied the same authoritative damage result.
        let scenes = makeLocalPlayerReplicas(playerID: "damaged-player")
        let damage = MultiplayerSyncEvent.playerDamaged(
            playerID: "damaged-player",
            damage: 12,
            health: 88,
            sourceID: "zombie-1"
        )
        scenes.forEach { $0.applyMultiplayerEvent(damage) }

        // When time advances to just before and then beyond the intended regeneration delay.
        let regeneratedBeforeDelay = scenes.map { $0.playerNode.updateHealth(deltaTime: 3.9) }
        let healthBeforeDelay = scenes.map { $0.playerNode.currentHealth }
        let regeneratedAfterDelay = scenes.map { $0.playerNode.updateHealth(deltaTime: 0.2) }
        scenes.forEach { scene in
            scene.update(4.1)
        }

        // Then no early regeneration occurs, recovery agrees everywhere, and every HUD refreshes.
        #expect(regeneratedBeforeDelay.allSatisfy { !$0 })
        #expect(healthBeforeDelay.allSatisfy { $0 == 88 })
        #expect(regeneratedAfterDelay.allSatisfy { $0 })
        let regeneratedHealth = scenes.map { $0.playerNode.currentHealth }
        #expect(Set(regeneratedHealth).count == 1)
        let expectedLabel = "HP: \(Int(regeneratedHealth[0]))/100"
        #expect(scenes.allSatisfy { healthLabelText(in: $0) == expectedLabel })
        #expect(Set(scenes.compactMap(healthFillScale(in:))).count == 1)
    }

    @Test("Contested collection resolves exactly once")
    func contestedCollectionIsSingleWinner() {
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)

        host.collectItem(entityID: "chest-1", collectorID: EventReplicationTestFixtures.hostID, result: .weapon(.rifle))
        host.collectItem(entityID: "chest-1", collectorID: EventReplicationTestFixtures.clientID, result: .weapon(.rifle))

        let events = host.drainOutgoingEvents()
        #expect(events.count == 1)
    }

    @Test("Zombie death removes the zombie from every client")
    func zombieDeathRemovesEntityEverywhere() {
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        var client = EventReplicationTestFixtures.initializedSystem()

        host.killZombie(id: "zombie-1", killerID: EventReplicationTestFixtures.hostID)
        for event in host.drainOutgoingEvents() {
            _ = client.receive(event)
        }

        #expect(client.containsZombie("zombie-1") == false)
    }

    @Test("Zombie death is emitted once")
    func zombieDeathIsIdempotent() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.killZombie(id: "zombie-1", killerID: EventReplicationTestFixtures.clientID)
        system.killZombie(id: "zombie-1", killerID: EventReplicationTestFixtures.clientID)

        #expect(system.drainOutgoingEvents().count == 1)
    }

    @Test("Player death removes the player from every client")
    func playerDeathRemovesEntityEverywhere() {
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        var client = EventReplicationTestFixtures.initializedSystem()

        host.killPlayer(id: EventReplicationTestFixtures.clientID)
        for event in host.drainOutgoingEvents() {
            _ = client.receive(event)
        }

        #expect(client.containsPlayer(EventReplicationTestFixtures.clientID) == false)
    }

    @Test("Dead players cannot move, attack, target, collect, or receive damage")
    func deadPlayerIsInactive() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.killPlayer(id: EventReplicationTestFixtures.clientID)
        _ = system.drainOutgoingEvents()

        #expect(system.setPlayerTransform(playerID: EventReplicationTestFixtures.clientID, position: .zero, facing: 0) == .rejected(.unknownEntity))
        #expect(system.setPlayerTarget(playerID: EventReplicationTestFixtures.clientID, zombieID: "zombie-1") == .rejected(.unknownEntity))
        #expect(system.collectItem(entityID: "chest-1", collectorID: EventReplicationTestFixtures.clientID, result: .weapon(.rifle)) == .rejected(.unknownEntity))
        #expect(system.damagePlayer(id: EventReplicationTestFixtures.clientID, amount: 1, sourceID: "zombie-1") == .rejected(.unknownEntity))
    }

    @Test("Duplicate lifecycle events do not duplicate rewards or removals")
    func lifecycleEventsAreIdempotent() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .itemCollected(entityID: "chest-1", collectorID: "host", result: .weapon(.rifle))
        )

        #expect(system.receive(event) == .accepted)
        #expect(system.receive(event) == .duplicate)
        #expect(system.weapon(of: "host") == .rifle)
    }

    private func weaponValues(_ player: PlayerNode) -> WeaponValues {
        WeaponValues(
            damage: player.currentWeaponDamage,
            range: player.currentWeaponRange,
            fireRate: player.currentWeaponFireRate
        )
    }

    @MainActor
    private func makeLocalPlayerReplicas(playerID: String) -> [GameScene] {
        (0..<4).map { replica in
            let session = FakeMultiplayerSession(localPlayerID: playerID)
            let scene = GameScene.newGameScene(
                size: CGSize(width: 1_000, height: 700),
                multiplayerSessionID: "health-replica-\(replica)",
                multiplayerSessionFactory: { session }
            )
            scene.didMove(to: SKView(frame: CGRect(x: 0, y: 0, width: 1_000, height: 700)))
            scene.startLocalMultiplayer()
            return scene
        }
    }

    @MainActor
    private func healthLabelText(in scene: GameScene) -> String? {
        scene.hudManager.containerNode.children
            .compactMap { $0 as? SKLabelNode }
            .first { $0.text?.hasPrefix("HP:") == true }?
            .text
    }

    @MainActor
    private func healthFillScale(in scene: GameScene) -> CGFloat? {
        (scene.hudManager.containerNode.children.first { $0.name == "healthBarFill" } as? SKShapeNode)?
            .xScale
    }
}

private struct WeaponValues: Hashable {
    let damage: CGFloat
    let range: CGFloat
    let fireRate: TimeInterval
}
