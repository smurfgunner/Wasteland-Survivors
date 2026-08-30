import Testing
@testable import Wasteland_Survivors

@Suite("Multiplayer Entity Lifecycle")
struct MultiplayerEntityReconcilerTests {
    @Test("Stable IDs allow an item event to remove the same entity everywhere")
    func itemLifecycleUsesStableIDs() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .itemCollected(entityID: "chest-1", collectorID: "host", result: .weapon(.rifle))
        )

        #expect(system.receive(event) == .accepted)
        #expect(system.containsChest("chest-1") == false)
    }

    @Test("A zombie death removes only the matching stable ID")
    func zombieDeathRemovesMatchingID() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .zombieDied(zombieID: "zombie-1", killerID: "host")
        )

        #expect(system.receive(event) == .accepted)
        #expect(system.containsZombie("zombie-1") == false)
    }

    @Test("Repeated lifecycle delivery is idempotent")
    func repeatedLifecycleDeliveryIsIdempotent() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .zombieDied(zombieID: "zombie-1", killerID: "host")
        )

        #expect(system.receive(event) == .accepted)
        #expect(system.receive(event) == .duplicate)
        #expect(system.containsZombie("zombie-1") == false)
    }
}
