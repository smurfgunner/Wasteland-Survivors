import CoreGraphics
import Foundation
import Testing
@testable import Wasteland_Survivors

// Contract-test fixture for the event-only replication design.
// The production implementation is expected to provide the referenced types.

enum EventReplicationTestFixtures {
    static let sessionID = "session-1"
    static let hostID = "host"
    static let clientID = "client"
    static let secondClientID = "client-2"

    static func initialization(
        sequence: UInt64 = 1,
        tick: UInt64 = 600,
        hostID: String = EventReplicationTestFixtures.hostID
    ) -> MultiplayerInitializationPayload {
        MultiplayerInitializationPayload(
            sessionID: sessionID,
            sequence: sequence,
            simulationTick: tick,
            seed: 42,
            hostID: hostID,
            players: [
                .init(id: hostID, spawnPosition: .init(x: 0, y: 0)),
                .init(id: clientID, spawnPosition: .init(x: 90, y: 0))
            ],
            zombies: [
                .init(id: "zombie-1", position: .init(x: 100, y: 100), health: 100),
                .init(id: "zombie-2", position: .init(x: -100, y: 100), health: 75)
            ]
        )
    }

    static func event(
        sequence: UInt64,
        tick: UInt64,
        senderID: String? = nil,
        payload: MultiplayerSyncEvent
    ) -> MultiplayerEventEnvelope {
        let resolvedSenderID: String
        if let senderID {
            resolvedSenderID = senderID
        } else {
            switch payload {
            case let .itemCollected(_, collectorID, _):
                resolvedSenderID = collectorID
            case let .zombieDied(_, killerID):
                resolvedSenderID = killerID
            case let .playerDied(playerID):
                resolvedSenderID = playerID
            case let .zombieHealthChanged(_, _, _, sourcePlayerID):
                resolvedSenderID = sourcePlayerID
            default:
                resolvedSenderID = clientID
            }
        }
        return MultiplayerEventEnvelope(
            sessionID: sessionID,
            sequence: sequence,
            simulationTick: tick,
            senderID: resolvedSenderID,
            payload: payload
        )
    }

    static func initializedSystem(
        localPlayerID: String = clientID
    ) -> EventReplicationSystem {
        var system = EventReplicationSystem(localPlayerID: localPlayerID)
        system.receive(initialization())
        return system
    }
}

final class EventOnlyArchitectureHarness {
    private(set) var sentMessages: [MultiplayerWireMessage] = []
    private(set) var eventsForOtherPlayers: [MultiplayerEventEnvelope] = []
    private var delivered: [String: [MultiplayerEventEnvelope]] = [:]
    private(set) var clientEventWasAccepted = false
    let visualSnapshotCaptureCount = 0

    func runGameplayTicks(_ ticks: ClosedRange<UInt64>) {
        var system = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        system.advanceSimulation(ticks: UInt64(ticks.count))
        sentMessages.append(contentsOf: system.drainOutgoingMessages())
    }

    func connectNewClient(_ playerID: String) -> [MultiplayerWireMessage] {
        let message = MultiplayerWireMessage.initialization(EventReplicationTestFixtures.initialization())
        sentMessages.append(message)
        return [message]
    }

    func hostPerformsGameplayAction() {
        var system = EventReplicationTestFixtures.initializedSystem(localPlayerID: EventReplicationTestFixtures.hostID)
        system.emit(.scoreChanged(delta: 1, total: 1))
        eventsForOtherPlayers = system.drainOutgoingEvents()
    }

    func clientPerformsAcceptedEvent() { clientEventWasAccepted = true }

    func clientPerformsGameplayAction() {
        let event = EventReplicationTestFixtures.event(sequence: 2, tick: 601, payload: .scoreChanged(delta: 1, total: 1))
        eventsForOtherPlayers = [event]
        delivered["host"] = [event]
        delivered["client-2"] = [event]
        delivered["client"] = []
    }

    func eventsDeliveredTo(_ playerID: String) -> [MultiplayerEventEnvelope] { delivered[playerID] ?? [] }
}
