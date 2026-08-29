import CoreGraphics
import Foundation
import Testing
@testable import Wasteland_Survivors

@Suite("Multiplayer Session Coordination")
struct MultiplayerSessionCoordinatorTests {
    @Test("Starting a session announces the local handshake")
    @MainActor
    func startingAnnouncesHandshake() throws {
        // Given a legacy transport boundary with a known local identity.
        let session = CoordinatorTestSession(localPlayerID: "local")
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 10
        )

        // When the session starts.
        coordinator.start()

        // Then it enters negotiation and broadcasts a versioned hello.
        #expect(coordinator.role == .negotiating)
        #expect(session.deliveryPolicies == [.reliable])
        let message = try #require(session.messages.first)
        #expect(message == .hello(.init(
            sessionID: "match",
            peerID: "local",
            startedAt: 10,
            protocolVersion: 1
        )))
    }

    @Test("Starting a session waits for an asynchronous transport connection before sending the handshake")
    @MainActor
    func asynchronousConnectionSendsHandshakeAfterConnection() throws {
        let session = CoordinatorTestSession(localPlayerID: "local")
        session.connectsImmediately = false
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 10)

        coordinator.start()
        #expect(session.messages.isEmpty)

        session.finishConnecting()

        #expect(session.messages == [.hello(.init(
            sessionID: "match",
            peerID: "local",
            startedAt: 10,
            protocolVersion: 1
        ))])
    }

    @Test("An earlier peer becomes the explicit host")
    @MainActor
    func earlierPeerBecomesHost() throws {
        // Given a local peer negotiating after an earlier advertiser.
        let session = CoordinatorTestSession(localPlayerID: "local")
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 20
        )
        coordinator.start()

        // When the earlier peer announces itself.
        let announcement = MultiplayerWireMessage.hostAnnouncement(.init(
            sessionID: "match",
            hostID: "host",
            hostStartedAt: 10,
            protocolVersion: 1
        ))
        session.deliver(try announcement.encoded())

        // Then the host identity is accepted and a join request is sent.
        #expect(coordinator.role == .client)
        #expect(coordinator.hostID == "host")
        #expect(session.messages.contains {
            if case .joinRequest = $0 { return true }
            return false
        })
    }

    @Test("A later peer adopts the active session ID before requesting to join")
    @MainActor
    func laterPeerAdoptsActiveSessionIDBeforeRequestingToJoin() throws {
        let session = CoordinatorTestSession(localPlayerID: "local")
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "local-session",
            startedAt: 20
        )
        coordinator.start()

        let activePeerHello = MultiplayerWireMessage.hello(.init(
            sessionID: "active-session",
            peerID: "host",
            startedAt: 10,
            protocolVersion: 1
        ))
        session.deliver(try activePeerHello.encoded())

        #expect(coordinator.role == .client)
        #expect(coordinator.hostID == "host")
        #expect(session.messages.contains {
            if case let .joinRequest(request) = $0 {
                return request.sessionID == "active-session"
            }
            return false
        })
    }

    @Test("The earliest peer keeps its session ID when establishing the active session")
    @MainActor
    func earliestPeerKeepsItsSessionIDWhenEstablishingActiveSession() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "host-session",
            startedAt: 10
        )
        coordinator.start()

        let laterPeerHello = MultiplayerWireMessage.hello(.init(
            sessionID: "later-session",
            peerID: "client",
            startedAt: 20,
            protocolVersion: 1
        ))
        session.deliver(try laterPeerHello.encoded())

        #expect(coordinator.role == .host)
        #expect(session.messages.contains {
            if case let .hostAnnouncement(announcement) = $0 {
                return announcement.sessionID == "host-session"
            }
            return false
        })
    }

    @Test("A host accepts a joining peer exactly once")
    @MainActor
    func hostAcceptsJoinOnce() throws {
        // Given the earliest peer is coordinating as host.
        let session = CoordinatorTestSession(localPlayerID: "host")
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 10
        )
        session.connectedPeerIDs = ["client"]
        coordinator.start()
        let laterHello = MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "client",
            startedAt: 20,
            protocolVersion: 1
        ))

        // When the same join request arrives twice.
        session.deliver(try laterHello.encoded())
        let request = MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match",
            peerID: "client",
            protocolVersion: 1
        ))
        session.deliver(try request.encoded())
        session.deliver(try request.encoded())

        // Then only one acceptance is emitted.
        let acceptances = session.messages.filter {
            if case .joinAccepted = $0 { return true }
            return false
        }
        #expect(coordinator.role == .host)
        #expect(acceptances.count == 1)
        #expect(session.directedPeerIDs == ["client"])
    }

    @Test("A newly accepted peer receives a state-transfer notification")
    @MainActor
    func acceptedPeerTriggersStateTransferNotification() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 1)
        var joinedPeerID: String?
        coordinator.onPeerJoined = { joinedPeerID = $0 }
        coordinator.start()

        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "client", startedAt: 2, protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match", peerID: "client", protocolVersion: 1
        )).encoded(), from: "client")

        #expect(joinedPeerID == "client")
    }

    @Test("The host broadcasts gameplay events reliably")
    @MainActor
    func hostBroadcastsGameplayEventsReliably() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 1)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "client", startedAt: 20, protocolVersion: 1
        )).encoded())

        let event = GameplayEvent.zombieKilled(id: "zombie-1", ownerID: "host")
        coordinator.broadcastGameplayEvent(event, sequence: 1, tick: 10)

        let message = try #require(session.messages.last)
        guard case let .gameplayEvent(envelope) = message else {
            Issue.record("Expected gameplay event message")
            return
        }
        #expect(envelope.sessionID == "match")
        #expect(envelope.event == event)
        #expect(session.deliveryPolicies.last == .reliable)
    }

    @Test("A client cannot broadcast authoritative gameplay events")
    @MainActor
    func clientCannotBroadcastGameplayEvents() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())

        coordinator.broadcastGameplayEvent(.matchEnded, sequence: 1, tick: 10)

        #expect(session.messages.filter {
            if case .gameplayEvent = $0 { return true }
            return false
        }.isEmpty)
    }

    @Test("A client sends owned intent to the elected host")
    @MainActor
    func clientSendsOwnedIntentToHost() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())

        let input = MultiplayerPlayerInput(
            playerID: "client", sequence: 1, movement: CGVector(dx: 1, dy: 0),
            aimAngle: 0.5, wantsToAttack: true
        )
        coordinator.sendPlayerInput(input)

        let message = try #require(session.messages.last)
        guard case let .playerInput(sentInput) = message else {
            Issue.record("Expected player input message")
            return
        }
        #expect(sentInput == input)
        #expect(session.directedPeerIDs.last == "host")
        #expect(session.deliveryPolicies.last == .reliable)
    }

    @Test("Transport identity is required for a player input")
    @MainActor
    func rejectsForgedTransportIdentity() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 1
        )
        coordinator.start()
        var received: [MultiplayerPlayerInput] = []
        coordinator.onInput = { received.append($0) }

        let input = MultiplayerPlayerInput(
            playerID: "client",
            sequence: 1,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: false
        )
        session.deliver(try MultiplayerWireMessage.playerInput(input).encoded(), from: "attacker")

        #expect(received.isEmpty)
    }

    @Test("Input sequences are accepted monotonically per player")
    @MainActor
    func inputSequencesAreMonotonic() throws {
        // Given a coordinator listening for client intent.
        let session = CoordinatorTestSession(localPlayerID: "host")
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 1
        )
        coordinator.start()
        session.connectedPeerIDs = ["client"]
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "client",
            startedAt: 20,
            protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match",
            peerID: "client",
            protocolVersion: 1
        )).encoded(), from: "client")
        var received: [MultiplayerPlayerInput] = []
        coordinator.onInput = { received.append($0) }

        // When duplicate and older inputs arrive.
        let input = MultiplayerPlayerInput(
            playerID: "client",
            sequence: 2,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: false
        )
        let message = MultiplayerWireMessage.playerInput(input)
        session.deliver(try message.encoded())
        session.deliver(try message.encoded())
        let older = MultiplayerPlayerInput(
            playerID: "client",
            sequence: 1,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: false
        )
        session.deliver(try MultiplayerWireMessage.playerInput(older).encoded())

        // Then only the newest sequence is forwarded.
        #expect(received == [input])
    }

    @Test("Host retains the latest client input between network packets")
    @MainActor
    func hostRetainsLatestClientInputBetweenNetworkPackets() throws {
        // Given a host that has accepted a client and received one movement input.
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 1
        )
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "client", startedAt: 20, protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match", peerID: "client", protocolVersion: 1
        )).encoded(), from: "client")
        let input = MultiplayerPlayerInput(
            playerID: "client",
            sequence: 1,
            movement: CGVector(dx: 1, dy: 0),
            aimAngle: 0,
            wantsToAttack: false
        )
        session.deliver(
            try MultiplayerWireMessage.playerInput(input).encoded(),
            from: "client"
        )

        // When the host advances more than one simulation step without another packet.
        let firstStep = coordinator.consumeQueuedInputs()
        let secondStep = coordinator.consumeQueuedInputs()

        // Then the latest intent remains active for every authoritative step.
        #expect(firstStep == [input])
        #expect(secondStep == [input])
        #expect(coordinator.acknowledgedInputSequences["client"] == 1)
    }

    @Test("Input sequence ordering accepts a single wraparound")
    @MainActor
    func inputSequenceOrderingAcceptsWraparound() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 1
        )
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "client",
            startedAt: 20,
            protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match",
            peerID: "client",
            protocolVersion: 1
        )).encoded(), from: "client")

        let beforeWrap = MultiplayerPlayerInput(
            playerID: "client",
            sequence: UInt64.max,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: false
        )
        let afterWrap = MultiplayerPlayerInput(
            playerID: "client",
            sequence: 0,
            movement: .init(dx: 1, dy: 0),
            aimAngle: 0,
            wantsToAttack: false
        )
        session.deliver(try MultiplayerWireMessage.playerInput(beforeWrap).encoded())
        session.deliver(try MultiplayerWireMessage.playerInput(afterWrap).encoded())

        #expect(coordinator.consumeQueuedInputs() == [afterWrap])
    }

    @Test("Input sequence half-range is treated as ambiguous")
    @MainActor
    func inputSequenceHalfRangeIsAmbiguous() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 1
        )
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "client",
            startedAt: 20,
            protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match",
            peerID: "client",
            protocolVersion: 1
        )).encoded(), from: "client")

        let first = MultiplayerPlayerInput(playerID: "client", sequence: 0, movement: .zero, aimAngle: 0, wantsToAttack: false)
        let ambiguous = MultiplayerPlayerInput(playerID: "client", sequence: UInt64.max / 2, movement: .init(dx: 1, dy: 0), aimAngle: 0, wantsToAttack: false)
        session.deliver(try MultiplayerWireMessage.playerInput(first).encoded())
        session.deliver(try MultiplayerWireMessage.playerInput(ambiguous).encoded())

        #expect(coordinator.consumeQueuedInputs() == [first])
    }

    @Test("A client does not queue input for authoritative simulation")
    @MainActor
    func clientDoesNotQueueInputForAuthoritativeSimulation() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 20
        )
        coordinator.start()
        let hostHello = MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "host",
            startedAt: 10,
            protocolVersion: 1
        ))
        session.deliver(try hostHello.encoded())

        let input = MultiplayerPlayerInput(
            playerID: "other-client",
            sequence: 1,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: false
        )
        session.deliver(try MultiplayerWireMessage.playerInput(input).encoded())

        #expect(coordinator.role == .client)
        #expect(coordinator.consumeQueuedInputs().isEmpty)
    }

    @Test("A host ignores legacy client-authoritative player updates")
    @MainActor
    func hostRejectsClientPlayerUpdate() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 1)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "client", startedAt: 20, protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match", peerID: "client", protocolVersion: 1
        )).encoded(), from: "client")
        var received: [MultiplayerWireMessage] = []
        coordinator.onMessage = { received.append($0) }
        let update = MultiplayerPlayerState(id: "client", position: CGPoint(x: 999, y: 999), color: .red)

        session.deliver(try MultiplayerWireMessage.playerUpdate(update).encoded(), from: "client")

        #expect(received.isEmpty)
    }

    @Test("A connected but unaccepted peer cannot influence the host")
    @MainActor
    func unacceptedPeerInputIsIgnored() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 1
        )
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "client",
            startedAt: 20,
            protocolVersion: 1
        )).encoded())

        let input = MultiplayerPlayerInput(
            playerID: "client",
            sequence: 1,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: true
        )
        session.deliver(try MultiplayerWireMessage.playerInput(input).encoded())

        #expect(coordinator.role == .host)
        #expect(coordinator.consumeQueuedInputs().isEmpty)
    }

    @Test("Accepted input is queued until the host consumes a simulation tick")
    @MainActor
    func acceptedInputIsQueuedUntilConsumed() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 1
        )
        coordinator.start()
        session.connectedPeerIDs = ["client"]
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "client",
            startedAt: 20,
            protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match",
            peerID: "client",
            protocolVersion: 1
        )).encoded(), from: "client")

        let input = MultiplayerPlayerInput(
            playerID: "client",
            sequence: 1,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: true
        )
        session.deliver(try MultiplayerWireMessage.playerInput(input).encoded())

        #expect(coordinator.consumeQueuedInputs() == [input])
        #expect(coordinator.consumeQueuedInputs().isEmpty)
    }

    @Test("Consuming host inputs exposes per-player acknowledgement sequences")
    @MainActor
    func consumedInputsProduceAcknowledgements() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 1)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "client", startedAt: 20, protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match", peerID: "client", protocolVersion: 1
        )).encoded(), from: "client")
        let input = MultiplayerPlayerInput(playerID: "client", sequence: 7, movement: .zero, aimAngle: 0, wantsToAttack: false)
        session.deliver(try MultiplayerWireMessage.playerInput(input).encoded(), from: "client")

        _ = coordinator.consumeQueuedInputs()

        #expect(coordinator.acknowledgedInputSequences == ["client": 7])
    }

    @Test("Messages with an unsupported protocol version cannot alter negotiation")
    @MainActor
    func incompatibleMessagesCannotAlterNegotiation() throws {
        let session = CoordinatorTestSession(localPlayerID: "local")
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 10
        )
        coordinator.start()
        let initialMessageCount = session.messages.count

        let incompatibleVersionHello = MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "future",
            startedAt: 1,
            protocolVersion: 999
        ))

        session.deliver(try incompatibleVersionHello.encoded())

        #expect(coordinator.role == .negotiating)
        #expect(coordinator.hostID == nil)
        #expect(session.messages.count == initialMessageCount)
    }

    @Test("Typed transport failures are observable by the coordinator")
    @MainActor
    func typedTransportFailuresAreObservable() {
        let session = CoordinatorTestSession(localPlayerID: "local")
        session.broadcastError = .notConnected
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 10
        )
        var failures: [MultiplayerTransportError] = []
        coordinator.onTransportError = { failures.append($0) }

        coordinator.start()

        #expect(failures == [.notConnected])
    }

    @Test("A directed transport failure is observable during join acceptance")
    @MainActor
    func directedTransportFailuresAreObservable() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        session.sendError = .peerUnavailable
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 1
        )
        var failures: [MultiplayerTransportError] = []
        coordinator.onTransportError = { failures.append($0) }

        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "client",
            startedAt: 20,
            protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match",
            peerID: "client",
            protocolVersion: 1
        )).encoded(), from: "client")

        #expect(failures == [.peerUnavailable])
    }

    @Test("A disconnected transport leaves the coordinator disconnected")
    @MainActor
    func disconnectUpdatesCoordinatorState() {
        let session = CoordinatorTestSession(localPlayerID: "local")
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 10
        )
        coordinator.start()
        session.disconnect()

        #expect(coordinator.role == .disconnected)
    }

    @Test("Transport disconnect clears accepted membership and queued inputs")
    @MainActor
    func disconnectClearsAcceptedMembershipAndQueuedInputs() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 1
        )
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "client",
            startedAt: 20,
            protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match",
            peerID: "client",
            protocolVersion: 1
        )).encoded(), from: "client")
        let input = MultiplayerPlayerInput(playerID: "client", sequence: 1, movement: .zero, aimAngle: 0, wantsToAttack: true)
        session.deliver(try MultiplayerWireMessage.playerInput(input).encoded())

        session.disconnect()

        #expect(coordinator.consumeQueuedInputs().isEmpty)
    }

    @Test("A single peer disconnect removes only that peer's authority state")
    @MainActor
    func peerDisconnectRemovesOnlyThatPeerAuthorityState() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client-a", "client-b"]
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 1
        )
        coordinator.start()

        for (peerID, startedAt) in [("client-a", 20.0), ("client-b", 30.0)] {
            session.deliver(try MultiplayerWireMessage.hello(.init(
                sessionID: "match",
                peerID: peerID,
                startedAt: startedAt,
                protocolVersion: 1
            )).encoded())
            session.deliver(try MultiplayerWireMessage.joinRequest(.init(
                sessionID: "match",
                peerID: peerID,
                protocolVersion: 1
            )).encoded(), from: peerID)
        }

        session.peerDisconnected("client-a")
        let input = MultiplayerPlayerInput(playerID: "client-b", sequence: 1, movement: .zero, aimAngle: 0, wantsToAttack: false)
        session.deliver(try MultiplayerWireMessage.playerInput(input).encoded())

        #expect(coordinator.consumeQueuedInputs() == [input])
    }

    @Test("A client does not forward authoritative snapshots from a non-host peer")
    @MainActor
    func clientRejectsNonHostSnapshotsBeforePresentation() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1)).encoded())

        var received: [MultiplayerWireMessage] = []
        coordinator.onMessage = { received.append($0) }
        let forged = MultiplayerBoardState.empty(hostID: "attacker", sequence: 1)
        session.deliver(try MultiplayerWireMessage.boardSnapshot(forged).encoded(), from: "attacker")

        #expect(received.isEmpty)
    }

    @Test("A client forwards authoritative snapshots only once and in sequence order")
    @MainActor
    func clientRejectsStaleAuthoritativeSnapshots() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())

        var received: [MultiplayerWireMessage] = []
        coordinator.onMessage = { received.append($0) }
        let newest = MultiplayerBoardState.empty(hostID: "host", sequence: 2)
        let stale = MultiplayerBoardState.empty(hostID: "host", sequence: 1)
        session.deliver(try MultiplayerWireMessage.boardSnapshot(newest).encoded(), from: "host")
        session.deliver(try MultiplayerWireMessage.boardSnapshot(newest).encoded(), from: "host")
        session.deliver(try MultiplayerWireMessage.boardSnapshot(stale).encoded(), from: "host")

        #expect(received == [.boardSnapshot(newest)])
    }

    @Test("A client rejects semantically invalid authoritative snapshots")
    @MainActor
    func clientRejectsInvalidAuthoritativeSnapshot() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())
        var received: [MultiplayerWireMessage] = []
        coordinator.onMessage = { received.append($0) }
        let invalid = MultiplayerBoardState(
            sequence: 1, hostID: "host",
            players: [MultiplayerPlayerState(id: "client", position: .zero, color: .blue, health: -1)],
            zombies: [], chests: [], powerUps: [],
            projectiles: [MultiplayerProjectileState(id: "projectile", ownerID: "host", x: 0, y: 0, angle: 0, weapon: .pistol, damage: -1)],
            killCount: 0
        )

        session.deliver(try MultiplayerWireMessage.boardSnapshot(invalid).encoded(), from: "host")

        #expect(received.isEmpty)
    }

    @Test("A snapshot with a forged state hash is rejected")
    @MainActor
    func clientRejectsForgedSnapshotStateHash() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())
        var received: [MultiplayerWireMessage] = []
        coordinator.onMessage = { received.append($0) }
        let forged = MultiplayerBoardState(
            sequence: 1, simulationTick: 1, hostID: "host", stateHash: 42,
            players: [], zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0
        )

        session.deliver(try MultiplayerWireMessage.boardSnapshot(forged).encoded(), from: "host")

        #expect(received.isEmpty)
    }

    @Test("A snapshot cannot acknowledge input for an unknown player")
    @MainActor
    func clientRejectsUnknownInputAcknowledgement() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())
        var received: [MultiplayerWireMessage] = []
        coordinator.onMessage = { received.append($0) }
        let forged = MultiplayerBoardState(
            sequence: 1, simulationTick: 1, hostID: "host",
            players: [MultiplayerPlayerState(id: "client", position: .zero, color: .red)],
            zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0,
            acknowledgedInputSequences: ["attacker": 4]
        )

        session.deliver(try MultiplayerWireMessage.boardSnapshot(forged).encoded(), from: "host")

        #expect(received.isEmpty)
    }

    @Test("Snapshot acknowledgements cannot move backwards")
    @MainActor
    func clientRejectsBackwardInputAcknowledgement() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())
        var received: [MultiplayerWireMessage] = []
        coordinator.onMessage = { received.append($0) }
        func board(sequence: UInt64, acknowledgement: UInt64) -> MultiplayerBoardState {
            MultiplayerBoardState(
                sequence: sequence, simulationTick: sequence, hostID: "host",
                players: [MultiplayerPlayerState(id: "client", position: .zero, color: .red)],
                zombies: [], chests: [], powerUps: [], projectiles: [], killCount: 0,
                acknowledgedInputSequences: ["client": acknowledgement]
            )
        }

        session.deliver(try MultiplayerWireMessage.boardSnapshot(board(sequence: 1, acknowledgement: 5)).encoded(), from: "host")
        session.deliver(try MultiplayerWireMessage.boardSnapshot(board(sequence: 2, acknowledgement: 4)).encoded(), from: "host")

        #expect(received.count == 1)
    }

    @Test("A client applies each authorized gameplay event at most once")
    @MainActor
    func clientAppliesGameplayEventExactlyOnce() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())

        var received: [MultiplayerGameplayEvent] = []
        var rawMessages: [MultiplayerWireMessage] = []
        coordinator.onGameplayEvent = { received.append($0) }
        coordinator.onMessage = { rawMessages.append($0) }
        let envelope = MultiplayerGameplayEvent(
            event: .matchEnded,
            sessionID: "match",
            sequence: 4,
            tick: 120,
            hostID: "host"
        )
        let data = try MultiplayerWireMessage.gameplayEvent(envelope).encoded()
        session.deliver(data, from: "host")
        session.deliver(data, from: "host")

        #expect(received == [envelope])
        #expect(rawMessages.count == 1)
    }

    @Test("Reliable gameplay events tolerate reordering while deduplicating retransmission")
    @MainActor
    func clientHandlesReorderedAndDuplicatedGameplayEvents() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())

        var received: [MultiplayerGameplayEvent] = []
        coordinator.onGameplayEvent = { received.append($0) }
        let first = MultiplayerGameplayEvent(
            event: .zombieDamaged(id: "zombie-1", amount: 10),
            sessionID: "match", sequence: 1, tick: 10, hostID: "host"
        )
        let second = MultiplayerGameplayEvent(
            event: .zombieKilled(id: "zombie-1", ownerID: "host"),
            sessionID: "match", sequence: 2, tick: 11, hostID: "host"
        )

        session.deliver(try MultiplayerWireMessage.gameplayEvent(second).encoded(), from: "host")
        session.deliver(try MultiplayerWireMessage.gameplayEvent(first).encoded(), from: "host")
        session.deliver(try MultiplayerWireMessage.gameplayEvent(second).encoded(), from: "host")

        #expect(received == [second, first])
    }

    @Test("Held transport packets can be released in a different order")
    @MainActor
    func heldTransportPacketsCanBeReorderedAndDuplicated() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())

        var received: [MultiplayerGameplayEvent] = []
        coordinator.onGameplayEvent = { received.append($0) }
        session.holdDeliveries = true
        let first = MultiplayerGameplayEvent(event: .zombieDamaged(id: "zombie", amount: 1), sessionID: "match", sequence: 1, tick: 1, hostID: "host")
        let second = MultiplayerGameplayEvent(event: .zombieKilled(id: "zombie", ownerID: "host"), sessionID: "match", sequence: 2, tick: 2, hostID: "host")
        session.deliver(try MultiplayerWireMessage.gameplayEvent(first).encoded(), from: "host")
        session.deliver(try MultiplayerWireMessage.gameplayEvent(second).encoded(), from: "host")

        session.duplicateHeld(at: 1)
        session.releaseHeld(at: 1)
        session.releaseHeld(at: 0)

        #expect(received == [second, first])
    }

    @Test("Dropped input packets do not invent or duplicate host intent")
    @MainActor
    func droppedInputPacketIsAbsentFromHostQueue() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 1)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "client", startedAt: 2, protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match", peerID: "client", protocolVersion: 1
        )).encoded(), from: "client")
        session.holdDeliveries = true
        let first = MultiplayerPlayerInput(playerID: "client", sequence: 1, movement: .init(dx: 1, dy: 0), aimAngle: 0, wantsToAttack: false)
        let dropped = MultiplayerPlayerInput(playerID: "client", sequence: 2, movement: .init(dx: -1, dy: 0), aimAngle: 0, wantsToAttack: false)
        session.deliver(try MultiplayerWireMessage.playerInput(first).encoded(), from: "client")
        session.deliver(try MultiplayerWireMessage.playerInput(dropped).encoded(), from: "client")

        session.dropHeld(at: 1)
        session.releaseHeld(at: 0, from: "client")

        #expect(coordinator.consumeQueuedInputs() == [first])
    }

    @Test("A client ignores gameplay events from a non-host peer")
    @MainActor
    func clientRejectsNonHostGameplayEvent() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())

        var received: [MultiplayerGameplayEvent] = []
        coordinator.onGameplayEvent = { received.append($0) }
        let forged = MultiplayerGameplayEvent(
            event: .matchEnded,
            sessionID: "match",
            sequence: 1,
            tick: 1,
            hostID: "attacker"
        )
        session.deliver(try MultiplayerWireMessage.gameplayEvent(forged).encoded(), from: "attacker")

        #expect(received.isEmpty)
    }

    @Test("A peer cannot spoof the host field in a gameplay event")
    @MainActor
    func clientRejectsGameplayEventWithForgedHostField() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())

        var received: [MultiplayerGameplayEvent] = []
        coordinator.onGameplayEvent = { received.append($0) }
        let forged = MultiplayerGameplayEvent(
            event: .matchEnded,
            sessionID: "match",
            sequence: 2,
            tick: 2,
            hostID: "host"
        )
        session.deliver(try MultiplayerWireMessage.gameplayEvent(forged).encoded(), from: "attacker")

        #expect(received.isEmpty)
    }

    @Test("A client reports host loss and enters a terminal disconnected state")
    @MainActor
    func clientReportsHostLoss() throws {
        let session = CoordinatorTestSession(localPlayerID: "client")
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 20)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match", peerID: "host", startedAt: 1, protocolVersion: 1
        )).encoded())
        var lostHostID: String?
        coordinator.onHostLost = { lostHostID = $0 }

        session.peerDisconnected("host")

        #expect(coordinator.role == .disconnected)
        #expect(coordinator.hostID == nil)
        #expect(lostHostID == "host")
    }

    @Test("The host rejects movement input outside the normalized range")
    @MainActor
    func hostRejectsOutOfRangeMovementInput() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: "match",
            startedAt: 1
        )
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(
            sessionID: "match",
            peerID: "client",
            startedAt: 20,
            protocolVersion: 1
        )).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(
            sessionID: "match",
            peerID: "client",
            protocolVersion: 1
        )).encoded(), from: "client")

        let invalidInput = MultiplayerPlayerInput(
            playerID: "client",
            sequence: 1,
            movement: CGVector(dx: 1.01, dy: 0),
            aimAngle: 0,
            wantsToAttack: false
        )
        session.deliver(try MultiplayerWireMessage.playerInput(invalidInput).encoded())

        #expect(coordinator.consumeQueuedInputs().isEmpty)
    }

    @Test("A reconnecting peer must be accepted again before sending input")
    @MainActor
    func reconnectingPeerMustRejoinBeforeInputIsAccepted() throws {
        let session = CoordinatorTestSession(localPlayerID: "host")
        session.connectedPeerIDs = ["client"]
        let coordinator = MultiplayerSessionCoordinator(transport: session, sessionID: "match", startedAt: 1)
        coordinator.start()
        session.deliver(try MultiplayerWireMessage.hello(.init(sessionID: "match", peerID: "client", startedAt: 20, protocolVersion: 1)).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(sessionID: "match", peerID: "client", protocolVersion: 1)).encoded(), from: "client")

        session.peerDisconnected("client")
        session.connectedPeerIDs.insert("client")
        let beforeRejoin = MultiplayerPlayerInput(playerID: "client", sequence: 1, movement: .zero, aimAngle: 0, wantsToAttack: false)
        session.deliver(try MultiplayerWireMessage.playerInput(beforeRejoin).encoded())
        #expect(coordinator.consumeQueuedInputs().isEmpty)

        session.deliver(try MultiplayerWireMessage.hello(.init(sessionID: "match", peerID: "client", startedAt: 20, protocolVersion: 1)).encoded())
        session.deliver(try MultiplayerWireMessage.joinRequest(.init(sessionID: "match", peerID: "client", protocolVersion: 1)).encoded(), from: "client")
        session.deliver(try MultiplayerWireMessage.playerInput(beforeRejoin).encoded())

        #expect(coordinator.consumeQueuedInputs() == [beforeRejoin])
    }
}

@MainActor
private final class CoordinatorTestSession: MultiplayerTransport {
    weak var delegate: MultiplayerTransportDelegate?
    let localPeerID: String
    private(set) var state: MultiplayerTransportState = .idle
    var connectedPeerIDs: Set<String> = []
    var messages: [MultiplayerWireMessage] = []
    var directedPeerIDs: [String] = []
    var deliveryPolicies: [MultiplayerDeliveryPolicy] = []
    var broadcastError: MultiplayerTransportError?
    var sendError: MultiplayerTransportError?
    var holdDeliveries = false
    var connectsImmediately = true
    private var heldData: [Data] = []

    init(localPlayerID: String) {
        self.localPeerID = localPlayerID
    }

    func connect() {
        state = connectsImmediately ? .connected : .connecting
        delegate?.transport(self, didChange: state)
    }

    func finishConnecting() {
        state = .connected
        delegate?.transport(self, didChange: state)
    }

    func disconnect() {
        state = .disconnected
        connectedPeerIDs.removeAll()
        delegate?.transport(self, didChange: state)
    }

    func peerDisconnected(_ peerID: String) {
        connectedPeerIDs.remove(peerID)
        delegate?.transport(self, didChangePeer: peerID, state: .disconnected)
    }

    func send(_ data: Data, to peerID: String) throws {
        guard state == .connected else { throw MultiplayerTransportError.notConnected }
        if let sendError { throw sendError }
        directedPeerIDs.append(peerID)
        record(data)
    }

    func send(_ data: Data, to peerID: String, delivery: MultiplayerDeliveryPolicy) throws {
        deliveryPolicies.append(delivery)
        try send(data, to: peerID)
    }

    func broadcast(_ data: Data) throws {
        guard state == .connected else { throw MultiplayerTransportError.notConnected }
        if let broadcastError { throw broadcastError }
        record(data)
    }

    func broadcast(_ data: Data, delivery: MultiplayerDeliveryPolicy) throws {
        deliveryPolicies.append(delivery)
        try broadcast(data)
    }

    func deliver(_ data: Data, from peerID: String? = nil) {
        if holdDeliveries {
            heldData.append(data)
            return
        }
        deliverImmediately(data, from: peerID)
    }

    func releaseHeld(at index: Int, from peerID: String? = "host") {
        let data = heldData.remove(at: index)
        deliverImmediately(data, from: peerID)
    }

    func duplicateHeld(at index: Int, from peerID: String? = "host") {
        deliverImmediately(heldData[index], from: peerID)
    }

    func dropHeld(at index: Int) {
        heldData.remove(at: index)
    }

    private func deliverImmediately(_ data: Data, from peerID: String? = nil) {
        let resolvedPeerID = peerID ?? senderID(from: data)
        guard let resolvedPeerID else { return }
        delegate?.transport(self, didReceive: data, from: resolvedPeerID)
    }

    private func record(_ data: Data) {
        if let message = try? MultiplayerWireMessage.decode(data) {
            messages.append(message)
        }
    }

    private func senderID(from data: Data) -> String? {
        guard let message = try? MultiplayerWireMessage.decode(data) else { return nil }
        switch message {
        case let .hello(value): return value.peerID
        case let .hostAnnouncement(value): return value.hostID
        case let .joinRequest(value): return value.peerID
        case let .joinAccepted(value): return value.hostID
        case let .playerUpdate(value): return value.id
        case let .boardSnapshot(value): return value.hostID
        case let .playerInput(value): return value.playerID
        case let .gameplayEvent(value): return value.hostID
        }
    }
}
