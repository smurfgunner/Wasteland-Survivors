import Foundation
import Testing
@testable import Wasteland_Survivors

@Suite("Event-Only Replication Architecture Contract")
struct EventReplicationArchitectureContractTests {
    @Test("Initialization is the only full-state transfer for a new connection")
    func initializationIsTheOnlyFullStateTransferForANewConnection() {
        let harness = EventOnlyArchitectureHarness()
        let messages = harness.connectNewClient("client-2")

        #expect(messages.count == 1)
        #expect(messages.contains { if case .initialization = $0 { return true }; return false })
    }

    @Test("Only permitted synchronization payload categories are emitted")
    func onlyPermittedSynchronizationPayloadCategoriesAreEmitted() {
        let harness = EventOnlyArchitectureHarness()
        harness.runGameplayTicks(1...600)

        for message in harness.sentMessages {
            switch message {
            case .initialization, .event, .recovery:
                break
            default:
                Issue.record("Prohibited synchronization message emitted: \(message)")
            }
        }
    }

    @Test("The host is a player and is not excluded from gameplay events")
    func hostIsAPlayerAndIsNotExcludedFromGameplayEvents() {
        let harness = EventOnlyArchitectureHarness()
        harness.hostPerformsGameplayAction()

        #expect(harness.eventsForOtherPlayers.contains { $0.senderID == "host" })
    }

    @Test("The role determines seeding, not event authorization")
    func roleDeterminesSeedingNotEventAuthorization() {
        let harness = EventOnlyArchitectureHarness()
        harness.clientPerformsAcceptedEvent()

        #expect(harness.clientEventWasAccepted)
    }

    @Test("The originating player does not receive its own event")
    func originatingPlayerDoesNotReceiveItsOwnEvent() {
        let harness = EventOnlyArchitectureHarness()
        harness.clientPerformsGameplayAction()

        #expect(!harness.eventsDeliveredTo("client").contains { $0.senderID == "client" })
    }

    @Test("All other connected players receive the event")
    func allOtherConnectedPlayersReceiveTheEvent() {
        let harness = EventOnlyArchitectureHarness()
        harness.clientPerformsGameplayAction()

        #expect(harness.eventsDeliveredTo("host").count == 1)
        #expect(harness.eventsDeliveredTo("client-2").count == 1)
    }

    @Test("Initialization, events, and recovery are all codable")
    func initializationEventsAndRecoveryAreAllCodable() throws {
        let messages: [MultiplayerWireMessage] = [
            .initialization(EventReplicationTestFixtures.initialization()),
            .recovery(.empty),
            .event(EventReplicationTestFixtures.event(
                sequence: 2,
                tick: 601,
                payload: .scoreChanged(delta: 1, total: 1)
            ))
        ]

        for message in messages {
            #expect(try MultiplayerWireMessage.decode(try message.encoded()) == message)
        }
    }

    @Test("Event-only replication does not depend on VisualSceneSnapshot")
    func eventOnlyReplicationDoesNotDependOnVisualSceneSnapshot() {
        let harness = EventOnlyArchitectureHarness()
        harness.runGameplayTicks(1...60)

        #expect(harness.visualSnapshotCaptureCount == 0)
    }
}
