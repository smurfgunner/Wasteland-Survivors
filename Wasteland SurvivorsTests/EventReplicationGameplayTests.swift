import Foundation
import Testing
@testable import Wasteland_Survivors

@Suite("Event Replication Gameplay Events")
struct EventReplicationGameplayTests {
    @Test("Zombie health changes include target, damage, and resulting health")
    func zombieDamageContainsAuthoritativeResult() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.damageZombie(id: "zombie-1", amount: 20, sourcePlayerID: EventReplicationTestFixtures.clientID)

        let event = system.drainOutgoingEvents()[0]
        #expect(event.payload == .zombieHealthChanged(
            zombieID: "zombie-1",
            damage: 20,
            health: 80,
            sourcePlayerID: EventReplicationTestFixtures.clientID
        ))
    }

    @Test("Zombie damage is broadcast to every other player but not its origin")
    func zombieDamageOmitsOrigin() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.damageZombie(id: "zombie-1", amount: 20, sourcePlayerID: EventReplicationTestFixtures.clientID)

        let event = system.drainOutgoingEvents()[0]
        #expect(system.recipients(of: event) == [EventReplicationTestFixtures.hostID, "client-2"])
    }

    @Test("Zombie damage is rejected for an unknown zombie")
    func unknownZombieDamageIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        #expect(system.damageZombie(id: "unknown", amount: 20, sourcePlayerID: EventReplicationTestFixtures.clientID) == .rejected)
    }

    @Test("Zombie damage cannot produce negative health")
    func zombieHealthIsClamped() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.damageZombie(id: "zombie-1", amount: 500, sourcePlayerID: EventReplicationTestFixtures.clientID)

        let events = system.drainOutgoingEvents()
        #expect(system.zombieHealth("zombie-1") == nil)
        #expect(events[0].payload == .zombieHealthChanged(
            zombieID: "zombie-1",
            damage: 500,
            health: 0,
            sourcePlayerID: EventReplicationTestFixtures.clientID
        ))
    }

    @Test("Damage after zombie death is ignored")
    func deadZombieCannotTakeDamage() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.damageZombie(id: "zombie-1", amount: 100, sourcePlayerID: EventReplicationTestFixtures.clientID)
        _ = system.drainOutgoingEvents()
        system.damageZombie(id: "zombie-1", amount: 1, sourcePlayerID: EventReplicationTestFixtures.clientID)

        #expect(system.drainOutgoingEvents().isEmpty)
    }

    @Test("Player damage includes target, damage, and resulting health")
    func playerDamageContainsAuthoritativeResult() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.damagePlayer(id: EventReplicationTestFixtures.clientID, amount: 12, sourceID: "zombie-1")

        #expect(system.drainOutgoingEvents()[0].payload == .playerDamaged(
            playerID: EventReplicationTestFixtures.clientID,
            damage: 12,
            health: 88,
            sourceID: "zombie-1"
        ))
    }

    @Test("Score changes are explicit events")
    func scoreChangeIsExplicit() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.changeScore(delta: 1)

        #expect(system.drainOutgoingEvents()[0].payload == .scoreChanged(delta: 1, total: 1))
    }

    @Test("Score event is not inferred from zombie death")
    func scoreRequiresItsOwnEvent() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.killZombie(id: "zombie-1", killerID: EventReplicationTestFixtures.clientID)

        let events = system.drainOutgoingEvents()
        #expect(events.contains { $0.payload.isZombieDeath })
        #expect(events.contains { $0.payload == .scoreChanged(delta: 1, total: 1) } == false)
        system.changeScore(delta: 1)
        #expect(system.drainOutgoingEvents().contains { $0.payload == .scoreChanged(delta: 1, total: 1) })
    }

    @Test("A zombie target change emits only when the target changes")
    func zombieTargetChangeIsEdgeTriggered() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.setZombieTarget(zombieID: "zombie-1", playerID: EventReplicationTestFixtures.clientID)
        system.setZombieTarget(zombieID: "zombie-1", playerID: EventReplicationTestFixtures.clientID)

        #expect(system.drainOutgoingEvents().count == 1)
    }

    @Test("A zombie cannot target an unknown or dead player")
    func zombieTargetValidation() {
        var system = EventReplicationTestFixtures.initializedSystem()
        #expect(system.setZombieTarget(zombieID: "zombie-1", playerID: "unknown") == .rejected(.unknownEntity))
        system.removePlayer(EventReplicationTestFixtures.clientID)
        #expect(system.setZombieTarget(zombieID: "zombie-1", playerID: EventReplicationTestFixtures.clientID) == .rejected(.unknownEntity))
    }

    @Test("All gameplay event variants are codable")
    func allGameplayEventVariantsAreCodable() throws {
        let events: [MultiplayerSyncEvent] = [
            .playerTransformChanged(playerID: "p", position: .init(x: 1, y: 2), facing: 0.5),
            .weaponChanged(playerID: "p", weapon: .rifle),
            .powerUpAcquired(playerID: "p", type: .damage),
            .playerTargetChanged(playerID: "p", zombieID: "z"),
            .zombieHealthChanged(zombieID: "z", damage: 10, health: 90, sourcePlayerID: "p"),
            .playerDamaged(playerID: "p", damage: 10, health: 90, sourceID: "z"),
            .zombieTargetChanged(zombieID: "z", playerID: "p"),
            .itemCollected(entityID: "chest", collectorID: "p", result: .weapon(.rifle)),
            .zombieDied(zombieID: "z", killerID: "p"),
            .playerDied(playerID: "p"),
            .scoreChanged(delta: 1, total: 1)
        ]

        let encoded = try JSONEncoder().encode(events)
        #expect(try JSONDecoder().decode([MultiplayerSyncEvent].self, from: encoded) == events)
    }
}
