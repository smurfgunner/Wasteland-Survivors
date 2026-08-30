import Testing
@testable import Wasteland_Survivors

@Suite("Event Replication Player State")
struct EventReplicationPlayerTests {
    @Test("Changed movement and facing are emitted immediately")
    func changedMovementAndFacingEmitOneUpdate() {
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)

        host.setPlayerTransform(
            playerID: EventReplicationTestFixtures.clientID,
            position: .init(x: 10, y: 20),
            facing: 1.5
        )

        let events = host.drainOutgoingEvents()
        #expect(events.count == 1)
        #expect(events[0].payload == .playerTransformChanged(
            playerID: EventReplicationTestFixtures.clientID,
            position: .init(x: 10, y: 20),
            facing: 1.5
        ))
    }

    @Test("Unchanged movement and facing emit no event")
    func unchangedTransformDoesNotEmit() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let position = system.playerPosition(EventReplicationTestFixtures.clientID)
        let facing = system.playerFacing(EventReplicationTestFixtures.clientID)

        system.setPlayerTransform(
            playerID: EventReplicationTestFixtures.clientID,
            position: position,
            facing: facing
        )

        #expect(system.drainOutgoingEvents().isEmpty)
    }

    @Test("Transform updates are sent to peers but never echoed to the originator")
    func transformDoesNotEchoToOrigin() {
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)

        host.setPlayerTransform(
            playerID: EventReplicationTestFixtures.hostID,
            position: .init(x: 4, y: 5),
            facing: 0.25
        )

        let event = host.drainOutgoingEvents()[0]
        #expect(host.recipients(of: event).contains(EventReplicationTestFixtures.hostID) == false)
    }

    @Test("Transform updates identify the sender and simulation tick")
    func transformContainsCausalityMetadata() {
        var host = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        host.setSimulationTick(601)

        host.setPlayerTransform(
            playerID: EventReplicationTestFixtures.clientID,
            position: .init(x: 1, y: 2),
            facing: 0
        )

        let event = host.drainOutgoingEvents()[0]
        #expect(event.senderID == EventReplicationTestFixtures.hostID)
        #expect(event.simulationTick == 601)
    }

    @Test("Weapon changes emit once per change")
    func weaponChangeIsEdgeTriggered() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.setWeapon(playerID: EventReplicationTestFixtures.clientID, weapon: .rifle)
        system.setWeapon(playerID: EventReplicationTestFixtures.clientID, weapon: .rifle)

        let events = system.drainOutgoingEvents()
        #expect(events.count == 1)
        #expect(events[0].payload == .weaponChanged(playerID: EventReplicationTestFixtures.clientID, weapon: .rifle))
    }

    @Test("Each power-up acquisition emits once")
    func powerUpAcquisitionIsNotRepeated() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.acquirePowerUp(playerID: EventReplicationTestFixtures.clientID, type: .damage)
        system.acquirePowerUp(playerID: EventReplicationTestFixtures.clientID, type: .damage)

        let events = system.drainOutgoingEvents()
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.payload == .powerUpAcquired(playerID: EventReplicationTestFixtures.clientID, type: .damage) })
    }

    @Test("A player target change emits once")
    func playerTargetChangeIsEdgeTriggered() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.setPlayerTarget(playerID: EventReplicationTestFixtures.clientID, zombieID: "zombie-1")
        system.setPlayerTarget(playerID: EventReplicationTestFixtures.clientID, zombieID: "zombie-1")

        #expect(system.drainOutgoingEvents().count == 1)
    }

    @Test("A player can clear its target")
    func playerCanClearTarget() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.setPlayerTarget(playerID: EventReplicationTestFixtures.clientID, zombieID: "zombie-1")
        system.setPlayerTarget(playerID: EventReplicationTestFixtures.clientID, zombieID: nil)

        #expect(system.drainOutgoingEvents().last?.payload == .playerTargetChanged(
            playerID: EventReplicationTestFixtures.clientID,
            zombieID: nil
        ))
    }

    @Test("A target outside range is rejected")
    func outOfRangeTargetIsRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        #expect(system.setPlayerTarget(playerID: EventReplicationTestFixtures.clientID, zombieID: "out-of-range") == .rejected(.unknownEntity))
    }

    @Test("A dead or unknown player cannot emit gameplay state changes")
    func deadPlayerCannotEmit() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.removePlayer(EventReplicationTestFixtures.clientID)

        #expect(system.setPlayerTarget(playerID: EventReplicationTestFixtures.clientID, zombieID: "zombie-1") == .rejected(.unknownEntity))
        #expect(system.setWeapon(playerID: EventReplicationTestFixtures.clientID, weapon: .rifle) == .rejected(.unknownEntity))
    }

    @Test("Movement delivery mode is selectable")
    func movementDeliveryModeIsConfigurable() {
        let reliable = EventReplicationConfiguration(movementDelivery: .reliable)
        let replaceable = EventReplicationConfiguration(movementDelivery: .replaceable)

        #expect(reliable.movementDelivery != replaceable.movementDelivery)
    }

    @Test("Movement events use the configured delivery mode")
    func movementUsesConfiguredDeliveryMode() {
        for mode in [MultiplayerDeliveryPolicy.reliable, .replaceable] {
            var system = EventReplicationTestFixtures.initializedSystem()
            system.configuration.movementDelivery = mode
            system.setPlayerTransform(
                playerID: EventReplicationTestFixtures.clientID,
                position: .init(x: 2, y: 3),
                facing: 0.5
            )

            #expect(system.drainOutgoingEvents()[0].delivery == mode)
        }
    }
}
