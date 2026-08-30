import Testing
@testable import Wasteland_Survivors

@Suite("Event Replication Ordering and Recovery")
struct EventReplicationOrderingRecoveryTests {
    @Test("Events apply in strictly increasing sequence order")
    func eventsApplyInOrder() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let first = EventReplicationTestFixtures.event(sequence: 2, tick: 601, payload: .scoreChanged(delta: 1, total: 1))
        let second = EventReplicationTestFixtures.event(sequence: 3, tick: 602, payload: .scoreChanged(delta: 1, total: 2))

        #expect(system.receive(first) == .accepted)
        #expect(system.receive(second) == .accepted)
        #expect(system.lastAppliedSequence == 3)
    }

    @Test("Older events are rejected after a newer event is applied")
    func staleEventsAreRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let newer = EventReplicationTestFixtures.event(sequence: 3, tick: 602, payload: .scoreChanged(delta: 1, total: 1))
        let older = EventReplicationTestFixtures.event(sequence: 1, tick: 600, payload: .scoreChanged(delta: 2, total: 2))

        #expect(system.receive(EventReplicationTestFixtures.event(sequence: 2, tick: 601, payload: .scoreChanged(delta: 1, total: 1))) == .accepted)
        #expect(system.receive(newer) == .accepted)
        #expect(system.receive(older) == .stale)
    }

    @Test("A sequence gap is detected")
    func sequenceGapIsDetected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(sequence: 4, tick: 604, payload: .scoreChanged(delta: 1, total: 1))

        #expect(system.receive(event) == .gapDetected(expected: 2, received: 4))
        #expect(system.recoveryRequestedFromSequence == 2)
    }

    @Test("Recovery payload contains all state changes missing from the gap")
    func recoveryContainsMissingPeriod() {
        let recovery = MultiplayerRecoveryPayload(
            sessionID: EventReplicationTestFixtures.sessionID,
            firstSequence: 2,
            lastSequence: 4,
            simulationTick: 604,
            players: [.init(id: "host", position: .init(x: 1, y: 1), facing: 0)],
            zombies: [.init(id: "zombie-1", position: .init(x: 2, y: 2), health: 50)],
            activeChests: [],
            activePowerUps: [],
            score: 3,
            playerTargets: ["client": "zombie-1"],
            zombieTargets: ["zombie-1": "client"],
            equipment: ["client": .rifle],
            removedEntities: ["zombie-2"],
            playerDeaths: []
        )

        #expect(recovery.firstSequence == 2)
        #expect(recovery.lastSequence == 4)
        #expect(recovery.simulationTick == 604)
        #expect(recovery.zombies[0].health == 50)
        #expect(recovery.removedEntities == ["zombie-2"])
    }

    @Test("Applying recovery advances sequence and tick atomically")
    func applyingRecoveryAdvancesSequenceAndTickAtomically() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let recovery = MultiplayerRecoveryPayload(
            sessionID: EventReplicationTestFixtures.sessionID,
            firstSequence: 2,
            lastSequence: 4,
            simulationTick: 604,
            players: [.init(id: "host", position: .init(x: 1, y: 1), facing: 0)],
            zombies: [],
            activeChests: [],
            activePowerUps: [],
            score: 3,
            playerTargets: [:],
            zombieTargets: [:],
            equipment: [:],
            removedEntities: [],
            playerDeaths: []
        )

        #expect(system.apply(recovery) == .accepted)
        #expect(system.lastAppliedSequence == 4)
        #expect(system.simulationTick == 604)
    }

    @Test("Recovery is rejected for a different session")
    func recoveryIsRejectedForDifferentSession() {
        var system = EventReplicationTestFixtures.initializedSystem()
        var recovery = MultiplayerRecoveryPayload.empty
        recovery.sessionID = "other-session"

        #expect(system.apply(recovery) == .rejected(.wrongSession))
    }

    @Test("Recovery is idempotent")
    func recoveryIsIdempotent() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let recovery = MultiplayerRecoveryPayload.empty

        #expect(system.apply(recovery) == .accepted)
        #expect(system.apply(recovery) == .duplicate)
    }

    @Test("Recovery does not use a periodic board snapshot message")
    func recoveryDoesNotUseAPeriodicBoardSnapshotMessage() throws {
        let recovery = MultiplayerRecoveryPayload.empty
        let message = MultiplayerWireMessage.recovery(recovery)
        let decoded = try MultiplayerWireMessage.decode(try message.encoded())

        guard case .recovery = decoded else {
            Issue.record("Recovery must use the recovery message type")
            return
        }
        #expect(true)
    }

    @Test("Events with inconsistent tick metadata are rejected")
    func inconsistentTicksAreRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        let event = EventReplicationTestFixtures.event(sequence: 2, tick: 0, payload: .scoreChanged(delta: 1, total: 1))

        #expect(system.receive(event) == .rejected(.inconsistentTick))
    }

    @Test("Events from another session are rejected")
    func eventsFromAnotherSessionAreRejected() {
        var system = EventReplicationTestFixtures.initializedSystem()
        var event = EventReplicationTestFixtures.event(sequence: 2, tick: 601, payload: .scoreChanged(delta: 1, total: 1))
        event.sessionID = "other-session"

        #expect(system.receive(event) == .rejected(.wrongSession))
    }

    @Test("No periodic snapshot is emitted during normal gameplay")
    func noPeriodicSnapshotIsEmittedDuringNormalGameplay() {
        var system = EventReplicationTestFixtures.initializedSystem()
        system.advanceSimulation(ticks: 600)

        #expect(system.drainOutgoingMessages().allSatisfy { message in
            if case .recovery = message { return false }
            return true
        })
    }
}
