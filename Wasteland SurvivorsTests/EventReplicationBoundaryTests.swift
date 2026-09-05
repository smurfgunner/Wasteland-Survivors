import Foundation
import Testing
@testable import Wasteland_Survivors

@Suite("Event Replication Boundaries and Security")
struct EventReplicationBoundaryTests {
    @Test("Events from every connected player are accepted")
    func connectedPlayersMaySendEvents() {
        var system = EventReplicationTestFixtures.initializedSystem(localPlayerID: "client-2")

        for senderID in ["host", "client"] {
            let event = EventReplicationTestFixtures.event(
                sequence: senderID == "host" ? 2 : 3,
                tick: 601,
                senderID: senderID,
                payload: .scoreChanged(delta: 1, total: senderID == "host" ? 1 : 2)
            )

            #expect(system.receive(event) == .accepted)
        }
    }

    @Test("Disconnected senders cannot send new events")
    func disconnectedSenderIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.disconnectPeer(EventReplicationTestFixtures.hostID)

        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            senderID: EventReplicationTestFixtures.hostID,
            payload: .scoreChanged(delta: 1, total: 1)
        )

        #expect(system.receive(event) == .rejected(.senderDisconnected))
    }

    @Test("An event with an empty sender is rejected")
    func emptySenderIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            senderID: "",
            payload: .scoreChanged(delta: 1, total: 1)
        )

        #expect(system.receive(event) == .rejected(.invalidSender))
    }

    @Test("An event with an empty session is rejected")
    func emptySessionIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        var event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .scoreChanged(delta: 1, total: 1)
        )
        event.sessionID = ""

        #expect(system.receive(event) == .rejected(.wrongSession))
    }

    @Test("An event with a zero sequence is rejected")
    func zeroSequenceIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 0,
            tick: 601,
            payload: .scoreChanged(delta: 1, total: 1)
        )

        #expect(system.receive(event) == .rejected(.invalidSequence))
    }

    @Test("Event sequence overflow cannot make an older event appear newer")
    func sequenceOverflowIsSafe() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.lastAppliedSequence = UInt64.max - 1

        let event = EventReplicationTestFixtures.event(
            sequence: 0,
            tick: 601,
            payload: .scoreChanged(delta: 1, total: 1)
        )

        #expect(system.receive(event) != .accepted)
    }

    @Test("An event payload must match its declared event type")
    func mismatchedPayloadIsRejected() {
        #expect(throws: DecodingError.self) {
            try MultiplayerWireMessage.decode(
                Data(#"{"type":"scoreChanged","playerTargetChanged":{"playerID":"p","zombieID":"z"}}"#.utf8)
            )
        }
    }

    @Test("A zombie health event cannot target an unknown player source")
    func unknownDamageSourceIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        #expect(system.receive(EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .zombieHealthChanged(
                zombieID: "zombie-1",
                damage: 10,
                health: 90,
                sourcePlayerID: "unknown"
            )
        )) == .rejected(.unknownEntity))
    }

    @Test("A player damage event cannot target an unknown player")
    func unknownDamageTargetIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        #expect(system.receive(EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .playerDamaged(
                playerID: "unknown",
                damage: 10,
                health: 90,
                sourceID: "zombie-1"
            )
        )) == .rejected(.unknownEntity))
    }

    @Test("A collection event cannot target an unknown entity")
    func unknownCollectionEntityIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        #expect(system.receive(EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .itemCollected(
                entityID: "unknown",
                collectorID: "client",
                result: .powerUp(.damage)
            )
        )) == .rejected(.unknownEntity))
    }

    @Test("A player transform must contain finite coordinates and facing")
    func nonFinitePlayerTransformIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .playerTransformChanged(
                playerID: "client",
                position: .init(x: .nan, y: 0),
                facing: .infinity
            )
        )

        #expect(system.receive(event) == .rejected(.malformedPayload))
    }

    @Test("Zombie health events cannot carry negative damage")
    func negativeZombieDamageIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .zombieHealthChanged(
                zombieID: "zombie-1",
                damage: -10,
                health: 110,
                sourcePlayerID: "client"
            )
        )

        #expect(system.receive(event) == .rejected(.malformedPayload))
    }

    @Test("Player health events cannot carry non-finite resulting health")
    func nonFinitePlayerHealthIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .playerDamaged(
                playerID: "client",
                damage: 10,
                health: .nan,
                sourceID: "zombie-1"
            )
        )

        #expect(system.receive(event) == .rejected(.malformedPayload))
    }

    @Test("An event cannot move simulation time backwards")
    func regressingEventTickIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 599,
            payload: .scoreChanged(delta: 1, total: 1)
        )

        #expect(system.receive(event) == .rejected(.inconsistentTick))
    }

    @Test("A score event total must agree with its delta")
    func inconsistentScoreTotalIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .scoreChanged(delta: 1, total: 999)
        )

        #expect(system.receive(event) == .rejected(.malformedPayload))
    }

    @Test("A player cannot move another player's character")
    func playerTransformOwnershipIsEnforced() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            senderID: "client",
            payload: .playerTransformChanged(
                playerID: "host",
                position: .init(x: 900, y: 900),
                facing: 1
            )
        )

        #expect(system.receive(event) == .rejected(.unauthorizedSender))
    }

    @Test("A player cannot replace another player's weapon")
    func weaponChangeOwnershipIsEnforced() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            senderID: "client",
            payload: .weaponChanged(playerID: "host", weapon: .sword)
        )

        #expect(system.receive(event) == .rejected(.unauthorizedSender))
    }

    @Test("A player cannot grant another player a power-up")
    func powerUpOwnershipIsEnforced() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            senderID: "client",
            payload: .powerUpAcquired(playerID: "host", type: .damage)
        )

        #expect(system.receive(event) == .rejected(.unauthorizedSender))
    }

    @Test("A player cannot change another player's target")
    func playerTargetOwnershipIsEnforced() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            senderID: "client",
            payload: .playerTargetChanged(playerID: "host", zombieID: "zombie-1")
        )

        #expect(system.receive(event) == .rejected(.unauthorizedSender))
    }

    @Test("A player cannot emit attacks for another player")
    func playerAttackOwnershipIsEnforced() {
        for payload in [
            MultiplayerSyncEvent.projectileSpawned(projectileID: "forged-projectile", playerID: "host"),
            MultiplayerSyncEvent.meleeAttack(attackID: "forged-attack", playerID: "host")
        ] {
            var system = EventReplicationTestFixtures.initializedSystem()
            let event = EventReplicationTestFixtures.event(
                sequence: 2,
                tick: 601,
                senderID: "client",
                payload: payload
            )

            #expect(system.receive(event) == .rejected(.unauthorizedSender))
        }
    }

    @Test("A player cannot collect an item for another player")
    func collectionOwnershipIsEnforced() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            senderID: "client",
            payload: .itemCollected(
                entityID: "power-up-1",
                collectorID: "host",
                result: .powerUp(.damage)
            )
        )

        #expect(system.receive(event) == .rejected(.unauthorizedSender))
    }

    @Test("A player cannot report another player dead")
    func playerDeathOwnershipIsEnforced() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            senderID: "client",
            payload: .playerDied(playerID: "host")
        )

        #expect(system.receive(event) == .rejected(.unauthorizedSender))
    }

    @Test("Zombie damage source must match the authenticated sender")
    func zombieDamageSourceOwnershipIsEnforced() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            senderID: "client",
            payload: .zombieHealthChanged(
                zombieID: "zombie-1",
                damage: 10,
                health: 90,
                sourcePlayerID: "host"
            )
        )

        #expect(system.receive(event) == .rejected(.unauthorizedSender))
    }

    @Test("Zombie death killer must match the authenticated sender")
    func zombieDeathOwnershipIsEnforced() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            senderID: "client",
            payload: .zombieDied(zombieID: "zombie-1", killerID: "host")
        )

        #expect(system.receive(event) == .rejected(.unauthorizedSender))
    }

    @Test("A player cannot receive its own outgoing event")
    func originatorSuppressionAppliesToHostAndClients() {
        for localPlayerID in ["host", "client", "client-2"] {
            var system = EventReplicationTestFixtures.initializedSystem(localPlayerID: localPlayerID)
            system.emit(.scoreChanged(delta: 1, total: 1))

            #expect(system.outgoingRecipients().contains(localPlayerID) == false)
        }
    }

    @Test("The host is eligible to originate events as a player")
    func hostOriginatesPlayerEvents() {
        var system = EventReplicationTestFixtures.initializedSystem(localPlayerID: "host")
        system.emit(.playerTransformChanged(
            playerID: "host",
            position: .init(x: 1, y: 2),
            facing: 0.5
        ))

        let event = system.drainOutgoingEvents()[0]
        #expect(system.recipients(of: event).contains("host") == false)
    }

    @Test("A client-originated event is delivered to the host and other clients")
    func clientEventFanoutExcludesOnlyOriginator() {
        var system = EventReplicationTestFixtures.initializedSystem(localPlayerID: "client")
        system.emit(.scoreChanged(delta: 1, total: 1))

        #expect(system.outgoingRecipients().sorted() == ["client-2", "host"])
    }

    @Test("A recovery payload includes active and removed entity sets")
    func recoveryContainsCompleteEntityState() {
        let recovery = MultiplayerRecoveryPayload.complete(
            activePlayers: ["host", "client"],
            activeZombies: ["zombie-1"],
            activeChests: ["chest-1"],
            activePowerUps: ["power-up-1"],
            removedEntities: ["zombie-2", "chest-2"]
        )

        #expect(recovery.activePlayers == ["host", "client"])
        #expect(recovery.activeZombies == ["zombie-1"])
        #expect(recovery.removedEntities.contains("zombie-2"))
        #expect(recovery.removedEntities.contains("chest-2"))
    }
}
