import Testing
@testable import Wasteland_Survivors

@Suite("Event Replication Host Migration")
struct EventReplicationMigrationTests {
    @Test("Host disconnect triggers migration")
    func hostDisconnectTriggersMigration() {
        var session = EventReplicationSession(
            localPlayerID: EventReplicationTestFixtures.clientID,
            connectedPlayers: ["host", "client", "client-2"]
        )

        session.peerDisconnected("host")

        #expect(session.migrationState == .selectingNewHost)
    }

    @Test("New host is selected randomly from remaining players")
    func newHostIsSelectedFromRemainingPlayers() {
        var session = EventReplicationSession(
            localPlayerID: EventReplicationTestFixtures.clientID,
            connectedPlayers: ["host", "client", "client-2"],
            randomHostSelector: { ["client", "client-2"].randomElement()! }
        )

        session.peerDisconnected("host")

        #expect(["client", "client-2"].contains(session.hostID!))
        #expect(session.hostID != "host")
    }

    @Test("Disconnected players are never selected as the new host")
    func disconnectedPlayersAreExcluded() {
        var session = EventReplicationSession(
            localPlayerID: EventReplicationTestFixtures.clientID,
            connectedPlayers: ["host", "client", "client-2"],
            randomHostSelector: { _ in "host" }
        )

        session.peerDisconnected("host")

        #expect(session.hostID != "host")
    }

    @Test("All remaining clients make the same random host choice")
    func hostChoiceIsDeterministicForTheSession() {
        let selector = DeterministicHostSelector(seed: 7)
        let candidates = ["client", "client-2"]

        #expect(selector.select(from: candidates) == selector.select(from: candidates))
    }

    @Test("Migration preserves session identity and seed")
    func migrationPreservesGameIdentity() {
        var session = EventReplicationSession(
            localPlayerID: EventReplicationTestFixtures.clientID,
            connectedPlayers: ["host", "client"]
        )
        let seed = session.seed
        session.peerDisconnected("host")

        #expect(session.sessionID == EventReplicationTestFixtures.sessionID)
        #expect(session.seed == seed)
        #expect(session.simulationTick > 0)
    }

    @Test("Migration continues event sequence numbering")
    func migrationContinuesSequence() {
        var session = EventReplicationSession(
            localPlayerID: EventReplicationTestFixtures.clientID,
            connectedPlayers: ["host", "client"]
        )
        session.lastAppliedSequence = 44
        session.peerDisconnected("host")
        session.emit(.scoreChanged(delta: 1, total: 1))

        #expect(session.drainOutgoingEvents()[0].sequence == 45)
    }

    @Test("New host continues from the last synchronized authoritative state")
    func migrationPreservesAuthoritativeState() {
        var session = EventReplicationSession(
            localPlayerID: EventReplicationTestFixtures.clientID,
            connectedPlayers: ["host", "client"]
        )
        session.apply(EventReplicationTestFixtures.event(
            sequence: 44,
            tick: 900,
            payload: .scoreChanged(delta: 1, total: 1)
        ))
        session.peerDisconnected("host")

        #expect(session.simulationTick == 900)
        #expect(session.currentScore == 1)
    }

    @Test("Migration with no remaining players ends the session")
    func migrationEndsWhenNoCandidatesRemain() {
        var session = EventReplicationSession(
            localPlayerID: EventReplicationTestFixtures.clientID,
            connectedPlayers: ["host"]
        )
        session.peerDisconnected("host")

        #expect(session.migrationState == .noHostAvailable)
    }

    @Test("A reconnecting player receives current initialization state, not event history")
    func reconnectUsesInitializationTransfer() {
        var session = EventReplicationSession(
            localPlayerID: EventReplicationTestFixtures.clientID,
            connectedPlayers: ["host", "client"]
        )

        let payload = session.initializationForReconnectingPlayer("client-2")

        #expect(payload.isFullCurrentState)
        #expect(payload.requiresEventHistory == false)
    }

    @Test("A reconnecting player starts after initialization sequence")
    func reconnectStartsAtCurrentSequence() {
        let session = EventReplicationSession(
            localPlayerID: EventReplicationTestFixtures.clientID,
            connectedPlayers: ["host", "client"]
        )
        let payload = session.initializationForReconnectingPlayer("client-2")

        #expect(payload.sequence == session.lastAppliedSequence)
        #expect(payload.simulationTick == session.simulationTick)
    }
}
