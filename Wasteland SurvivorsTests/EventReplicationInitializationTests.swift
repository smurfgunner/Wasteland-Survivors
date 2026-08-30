import Foundation
import Testing
@testable import Wasteland_Survivors

@Suite("Event Replication Initialization")
struct EventReplicationInitializationTests {
    @Test("Initialization carries seed, tick, host, players, zombie positions, and zombie health")
    func initializationContainsRequiredState() {
        let payload = EventReplicationTestFixtures.initialization()

        #expect(payload.seed == 42)
        #expect(payload.simulationTick == 600)
        #expect(payload.hostID == EventReplicationTestFixtures.hostID)
        #expect(payload.players.count == 2)
        #expect(payload.zombies.count == 2)
        #expect(payload.zombies.first?.health == 100)
    }

    @Test("Initialization round trips through the wire format")
    func initializationRoundTripsThroughWireFormat() throws {
        let message = MultiplayerWireMessage.initialization(EventReplicationTestFixtures.initialization())
        let decoded = try MultiplayerWireMessage.decode(try message.encoded())

        #expect(decoded == message)
    }

    @Test("Initialization is accepted exactly once")
    func initializationIsAcceptedExactlyOnce() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        let payload = EventReplicationTestFixtures.initialization()

        #expect(system.receive(payload) == .accepted)
        #expect(system.receive(payload) == .duplicate)
    }

    @Test("Initialization is required before gameplay events are applied")
    func initializationIsRequiredBeforeGameplayEventsAreApplied() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .scoreChanged(delta: 1, total: 1)
        )

        #expect(system.receive(event) == .waitingForInitialization)
        #expect(system.pendingEventCount == 1)
    }

    @Test("Buffered events are applied after initialization")
    func bufferedEventsAreAppliedAfterInitialization() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        let event = EventReplicationTestFixtures.event(
            sequence: 2,
            tick: 601,
            payload: .scoreChanged(delta: 1, total: 1)
        )

        _ = system.receive(event)
        _ = system.receive(EventReplicationTestFixtures.initialization())

        #expect(system.currentScore == 1)
        #expect(system.lastAppliedSequence == 2)
    }

    @Test("Initialization rejects the wrong session")
    func initializationRejectsWrongSession() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        var payload = EventReplicationTestFixtures.initialization()
        payload.sessionID = "other-session"

        #expect(system.receive(payload) == .rejected(.wrongSession))
        #expect(system.isInitialized == false)
    }

    @Test("Initialization rejects a non-host sender")
    func initializationRejectsNonHostSender() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        let payload = EventReplicationTestFixtures.initialization(hostID: EventReplicationTestFixtures.hostID)

        #expect(system.receive(payload, from: EventReplicationTestFixtures.clientID) == .rejected(.unauthorizedSender))
    }

    @Test("Initialization rejects an unsupported protocol version")
    func initializationRejectsUnsupportedProtocolVersion() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        var payload = EventReplicationTestFixtures.initialization()
        payload.protocolVersion = Int.max

        #expect(system.receive(payload) == .rejected(.unsupportedVersion))
    }

    @Test("Initialization rejects duplicate player identifiers")
    func initializationRejectsDuplicatePlayerIdentifiers() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        var payload = EventReplicationTestFixtures.initialization()
        payload.players.append(payload.players[0])

        #expect(system.receive(payload) == .rejected(.malformedPayload))
    }

    @Test("Initialization rejects duplicate zombie identifiers")
    func initializationRejectsDuplicateZombieIdentifiers() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        var payload = EventReplicationTestFixtures.initialization()
        payload.zombies.append(payload.zombies[0])

        #expect(system.receive(payload) == .rejected(.malformedPayload))
    }

    @Test("Initialization rejects invalid zombie health")
    func initializationRejectsInvalidZombieHealth() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        var payload = EventReplicationTestFixtures.initialization()
        payload.zombies[0].health = -1

        #expect(system.receive(payload) == .rejected(.malformedPayload))
    }

    @Test("Initialization reconstructs chests and power-ups from seed and tick")
    func initializationReconstructsChestsAndPowerUpsFromSeedAndTick() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        _ = system.receive(EventReplicationTestFixtures.initialization())

        let expected = LocalWorldGenerator(seed: 42).world(at: 600)

        #expect(system.chests == expected.chests)
        #expect(system.powerUps == expected.powerUps)
    }

    @Test("Initialization restores the current event sequence")
    func initializationRestoresCurrentEventSequence() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.clientID)
        var payload = EventReplicationTestFixtures.initialization(sequence: 900)

        #expect(system.receive(payload) == .accepted)
        #expect(system.lastAppliedSequence == 900)
    }

    @Test("Initialization contains no periodic-snapshot-only payload")
    func initializationContainsNoPeriodicSnapshotOnlyPayload() throws {
        let encoded = try JSONEncoder().encode(EventReplicationTestFixtures.initialization())

        #expect(!encoded.contains(Data("playersStateSnapshot".utf8)))
        #expect(!encoded.contains(Data("fullBoardSnapshot".utf8)))
    }

    @Test("Late join initialization establishes active state without event history")
    func lateJoinInitializationEstablishesActiveStateWithoutEventHistory() {
        var system = EventReplicationSystem(localPlayerID: EventReplicationTestFixtures.secondClientID)
        let payload = EventReplicationTestFixtures.initialization()

        #expect(system.receive(payload) == .accepted)
        #expect(system.isInitialized)
        #expect(system.eventHistoryRequiredForInitialization == false)
    }
}
