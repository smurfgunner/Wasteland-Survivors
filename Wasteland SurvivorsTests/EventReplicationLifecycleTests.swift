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
}
