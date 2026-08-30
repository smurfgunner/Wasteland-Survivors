import Foundation

struct MultiplayerHello: Codable, Equatable, Sendable {
    let sessionID: String
    let peerID: String
    let startedAt: TimeInterval
    let protocolVersion: Int
}

struct MultiplayerHostAnnouncement: Codable, Equatable, Sendable {
    let sessionID: String
    let hostID: String
    let hostStartedAt: TimeInterval
    let protocolVersion: Int
}

struct MultiplayerJoinRequest: Codable, Equatable, Sendable {
    let sessionID: String
    let peerID: String
    let protocolVersion: Int
}

struct MultiplayerJoinAccepted: Codable, Equatable, Sendable {
    let sessionID: String
    let peerID: String
    let hostID: String
    let protocolVersion: Int
}

enum MultiplayerSessionRole: Equatable, Sendable {
    case idle
    case negotiating
    case host
    case client
    case disconnected
}

@MainActor
protocol MultiplayerGameplayReplication: AnyObject {
    var role: MultiplayerSessionRole { get }
    var hostID: String? { get }
    var currentEventSequence: UInt64 { get }
    func start()
    func consumePlayerInputs() -> [PlayerInput]
    func submitPlayerInput(_ input: PlayerInput)
    func publishSimulationStep(_ step: SimulationStep)
    func publishGameplayEvents(_ events: [GameplayEvent], tick: UInt64)
}

@MainActor
final class MultiplayerSessionCoordinator: MultiplayerTransportDelegate, MultiplayerGameplayReplication {
    private let transport: MultiplayerTransport
    private var sessionID: String
    private let startedAt: TimeInterval
    private let protocolVersion: Int
    private var acceptedPeerIDs: Set<String> = []
    private var latestInputSequences: [String: UInt64] = [:]
    private var acknowledgedInputSequencesStorage: [String: UInt64] = [:]
    private var queuedInputs: [MultiplayerPlayerInput] = []
    private var latestInputs: [String: MultiplayerPlayerInput] = [:]
    private var lastInputReceiveLogTime: TimeInterval = 0
    private var lastInputConsumeLogTime: TimeInterval = 0
    private var appliedEvents = AppliedEventStore()
    private var nextGameplayEventSequence: UInt64 = 0
    private var lastReceivedEventSequence: UInt64 = 0
    private var lastPublishedTransforms: [String: (CGPointValue, Double)] = [:]
    private var lastPublishedPlayerTargets: [String: String] = [:]
    private var lastPublishedZombieTargets: [String: String] = [:]
    private var eventReplicationSystem: EventReplicationSystem?
    private var hasSentHello = false

    private(set) var role: MultiplayerSessionRole = .idle
    private(set) var hostID: String?
    var acknowledgedInputSequences: [String: UInt64] {
        acknowledgedInputSequencesStorage
    }
    var onRoleChanged: ((MultiplayerSessionRole) -> Void)?
    /// Called after a host has accepted a peer, allowing the gameplay layer to
    /// immediately send the complete authoritative state for late join-in.
    var onPeerJoined: ((String) -> Void)?
    var onPeerDisconnected: ((String) -> Void)?
    var onHostLost: ((String) -> Void)?
    var onInput: ((MultiplayerPlayerInput) -> Void)?
    var onGameplayEvent: ((MultiplayerGameplayEvent) -> Void)?
    var onEvent: ((MultiplayerEventEnvelope) -> Void)?
    var onInitialization: ((MultiplayerInitializationPayload) -> Void)?
    var onRecovery: ((MultiplayerRecoveryPayload) -> Void)?
    var initializationProvider: ((String) -> MultiplayerInitializationPayload?)?
    var recoveryProvider: ((UInt64) -> MultiplayerRecoveryPayload?)?
    var onRecoveryRequested: ((UInt64) -> Void)?
    var currentEventSequence: UInt64 { nextGameplayEventSequence }
    var configuration = EventReplicationConfiguration()
    var onMessage: ((MultiplayerWireMessage) -> Void)?
    var onTransportError: ((MultiplayerTransportError) -> Void)?

    init(
        transport: MultiplayerTransport,
        sessionID: String,
        startedAt: TimeInterval,
        protocolVersion: Int = 1
    ) {
        self.transport = transport
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.protocolVersion = protocolVersion
    }

    func start() {
        guard role == .idle || role == .disconnected else { return }
        hasSentHello = false
        transport.delegate = self
        updateRole(.negotiating)
        transport.connect()
        if transport.state == .connected {
            sendHello()
        }
    }

    private func sendHello() {
        guard !hasSentHello else { return }
        hasSentHello = true
        send(.hello(MultiplayerHello(
            sessionID: sessionID,
            peerID: transport.localPeerID,
            startedAt: startedAt,
            protocolVersion: protocolVersion
        )))
    }

    func stop() {
        transport.disconnect()
        updateRole(.disconnected)
        hostID = nil
        acceptedPeerIDs.removeAll()
        latestInputSequences.removeAll()
        acknowledgedInputSequencesStorage.removeAll()
        queuedInputs.removeAll()
        latestInputs.removeAll()
        appliedEvents = AppliedEventStore()
        eventReplicationSystem = nil
        lastReceivedEventSequence = 0
    }

    func consumeQueuedInputs() -> [MultiplayerPlayerInput] {
        let inputsByPlayer = Dictionary(
            queuedInputs.map { ($0.playerID, $0) },
            uniquingKeysWith: { current, replacement in
                isNewer(current.sequence, than: replacement.sequence) ? current : replacement
            }
        )
        latestInputs.merge(inputsByPlayer) { current, replacement in
            isNewer(current.sequence, than: replacement.sequence) ? current : replacement
        }
        let inputsToApply = latestInputs.values.sorted { $0.playerID < $1.playerID }
        for input in inputsToApply {
            acknowledgedInputSequencesStorage[input.playerID] = input.sequence
            latestInputs[input.playerID] = MultiplayerPlayerInput(
                playerID: input.playerID,
                sequence: input.sequence,
                movement: input.movement,
                aimAngle: input.aimAngle,
                wantsToAttack: input.wantsToAttack,
                attackTargetID: input.attackTargetID,
                wantsToOpenChestID: nil,
                wantsToCollectPowerUpID: nil
            )
        }
        queuedInputs.removeAll()
        return inputsToApply
    }

    func consumePlayerInputs() -> [PlayerInput] {
        consumeQueuedInputs().map {
            PlayerInput(
                playerID: $0.playerID,
                sequence: $0.sequence,
                movement: CGPointValue($0.movement),
                aimAngle: $0.aimAngle,
                wantsToAttack: $0.wantsToAttack,
                attackTargetID: $0.attackTargetID,
                wantsToOpenChestID: $0.wantsToOpenChestID,
                wantsToCollectPowerUpID: $0.wantsToCollectPowerUpID
            )
        }
    }

    func submitPlayerInput(_ input: PlayerInput) {
        guard role == .client, input.playerID == transport.localPeerID,
              let hostID else { return }
        send(.playerInput(MultiplayerPlayerInput(
            playerID: input.playerID,
            sequence: input.sequence,
            movement: CGVector(dx: input.movement.x, dy: input.movement.y),
            aimAngle: CGFloat(input.aimAngle),
            wantsToAttack: input.wantsToAttack,
            attackTargetID: input.attackTargetID,
            wantsToOpenChestID: input.wantsToOpenChestID,
            wantsToCollectPowerUpID: input.wantsToCollectPowerUpID
        )), to: hostID)
    }

    func publishSimulationStep(_ step: SimulationStep) {
        for player in step.state.players {
            let transform = (player.position, player.rotation)
            if lastPublishedTransforms[player.id]?.0 != transform.0 || lastPublishedTransforms[player.id]?.1 != transform.1 {
                lastPublishedTransforms[player.id] = transform
                publishEvent(.playerTransformChanged(playerID: player.id, position: player.position, facing: player.rotation), tick: step.state.tick)
            }

            let targetID = step.state.zombies
                .filter { $0.health > 0 }
                .min {
                    let firstDistance = $0.position.distance(to: player.position)
                    let secondDistance = $1.position.distance(to: player.position)
                    return firstDistance == secondDistance ? $0.id < $1.id : firstDistance < secondDistance
                }?.id ?? ""
            if lastPublishedPlayerTargets[player.id] != targetID {
                lastPublishedPlayerTargets[player.id] = targetID
                publishEvent(
                    .playerTargetChanged(playerID: player.id, zombieID: targetID.isEmpty ? nil : targetID),
                    tick: step.state.tick
                )
            }
        }

        for zombie in step.state.zombies where zombie.health > 0 {
            let targetID = NPCDecisionSystem.target(for: zombie, players: step.state.players)?.id ?? ""
            if lastPublishedZombieTargets[zombie.id] != targetID {
                lastPublishedZombieTargets[zombie.id] = targetID
                publishEvent(
                    .zombieTargetChanged(zombieID: zombie.id, playerID: targetID.isEmpty ? nil : targetID),
                    tick: step.state.tick
                )
            }
        }

        publishGameplayEvents(step.events, tick: step.state.tick)
    }

    func publishGameplayEvents(_ events: [GameplayEvent], tick: UInt64) {
        for event in events {
            publishEvent(MultiplayerSyncEvent(gameplayEvent: event, sourcePlayerID: transport.localPeerID), tick: tick)
        }
    }

    private func publishEvent(_ event: MultiplayerSyncEvent, tick: UInt64) {
        nextGameplayEventSequence &+= 1
        let envelope = MultiplayerEventEnvelope(
            sessionID: sessionID,
            sequence: nextGameplayEventSequence,
            simulationTick: tick,
            senderID: transport.localPeerID,
            payload: event,
            delivery: event.isMovementEvent ? configuration.movementDelivery : .reliable
        )
        for peerID in transport.connectedPeerIDs where peerID != transport.localPeerID {
            send(.event(envelope), to: peerID)
        }
    }

    func publishInitialization(for peerID: String) {
        guard role == .host, let payload = initializationProvider?(peerID) else { return }
        send(.initialization(payload), to: peerID)
    }

    func publishRecovery(_ payload: MultiplayerRecoveryPayload, to peerID: String) {
        send(.recovery(payload), to: peerID)
    }

    func broadcastGameplayEvent(_ event: GameplayEvent, sequence: UInt64, tick: UInt64) {
        guard role == .host else { return }
        send(.gameplayEvent(MultiplayerGameplayEvent(
            event: event,
            sessionID: sessionID,
            sequence: sequence,
            tick: tick,
            hostID: transport.localPeerID
        )))
    }

    func sendPlayerInput(_ input: MultiplayerPlayerInput) {
        guard role == .client,
              input.playerID == transport.localPeerID,
              let hostID else { return }
        send(.playerInput(input), to: hostID)
    }

    func transport(_ transport: MultiplayerTransport, didChange state: MultiplayerTransportState) {
        if state == .connected {
            sendHello()
        }
        if state == .disconnected || state == .failed {
            updateRole(.disconnected)
            hostID = nil
            acceptedPeerIDs.removeAll()
            latestInputSequences.removeAll()
            queuedInputs.removeAll()
            latestInputs.removeAll()
            appliedEvents = AppliedEventStore()
        }
    }

    func transport(_ transport: MultiplayerTransport, didChangePeer peerID: String, state: MultiplayerPeerState) {
        guard state == .disconnected else { return }

        acceptedPeerIDs.remove(peerID)
        latestInputSequences[peerID] = nil
        latestInputs[peerID] = nil
        acknowledgedInputSequencesStorage[peerID] = nil
        queuedInputs.removeAll { $0.playerID == peerID }
        onPeerDisconnected?(peerID)

        if hostID == peerID, role == .client {
            let candidates = Set(transport.connectedPeerIDs).union([transport.localPeerID])
            guard let nextHost = MultiplayerHostElection.select(sessionID: sessionID, candidates: candidates) else {
                onHostLost?(peerID)
                hostID = nil
                appliedEvents = AppliedEventStore()
                updateRole(.disconnected)
                return
            }
            hostID = nextHost
            if nextHost == transport.localPeerID {
                becomeHost()
                send(.hostAnnouncement(MultiplayerHostAnnouncement(
                    sessionID: sessionID,
                    hostID: transport.localPeerID,
                    hostStartedAt: startedAt,
                    protocolVersion: protocolVersion
                )))
            } else {
                updateRole(.client)
            }
        }
    }

    func transport(_ transportService: MultiplayerTransport, didReceive data: Data, from peerID: String) {
        guard let message = try? MultiplayerWireMessage.decode(data) else {
            return
        }
        self.transport(transportService, didReceive: message, from: peerID)
    }

    func transport(_ transportService: MultiplayerTransport, didReceive message: MultiplayerWireMessage, from peerID: String) {
        guard senderMatches(message, peerID: peerID) else {
            return
        }
        guard isAuthorized(message, from: peerID) else {
            return
        }
        if handle(message, from: peerID) {
            onMessage?(message)
        }
    }

    private func isAuthorized(_ message: MultiplayerWireMessage, from peerID: String) -> Bool {
        switch message {
        case let .gameplayEvent(event):
            guard role == .client, hostID == peerID else { return false }
            do {
                try event.validate(expectedHostID: peerID, expectedSessionID: sessionID)
                return true
            } catch {
                return false
            }
        case let .event(event):
            guard !event.senderID.isEmpty,
                  event.senderID == peerID,
                  event.sessionID == sessionID,
                  event.sequence > 0,
                  event.simulationTick > 0 else { return false }
            return true
        case let .initialization(payload):
            guard payload.protocolVersion == protocolVersion,
                  payload.sessionID == sessionID,
                  payload.hostID == peerID else { return false }
            return true
        case let .recovery(payload):
            return payload.sessionID == sessionID
        default:
            return true
        }
    }

    private func senderMatches(_ message: MultiplayerWireMessage, peerID: String) -> Bool {
        switch message {
        case let .hello(hello): return hello.peerID == peerID
        case let .hostAnnouncement(announcement): return announcement.hostID == peerID
        case let .joinRequest(request): return request.peerID == peerID
        case let .joinAccepted(accepted): return accepted.hostID == peerID
        case let .playerInput(input): return input.playerID == peerID
        case let .gameplayEvent(event): return event.hostID == peerID
        case let .initialization(payload): return payload.hostID == peerID
        case let .event(envelope): return envelope.senderID == peerID
        case .recovery: return true
        }
    }

    @discardableResult
    private func handle(_ message: MultiplayerWireMessage, from peerID: String? = nil) -> Bool {
        switch message {
        case let .hello(hello): handle(hello)
        case let .hostAnnouncement(announcement): handle(announcement)
        case let .joinRequest(request): handle(request)
        case let .joinAccepted(accepted): handle(accepted)
        case let .playerInput(input): handle(input)
        case let .gameplayEvent(event):
            guard appliedEvents.insertIfNew(
                event.event,
                key: "\(event.sessionID):\(event.sequence)"
            ) else { return false }
            onGameplayEvent?(event)
            return true
        case let .initialization(payload):
            var system = EventReplicationSystem(localPlayerID: transport.localPeerID, sessionID: payload.sessionID)
            guard system.receive(payload, from: peerID) == .accepted else { return false }
            eventReplicationSystem = system
            lastReceivedEventSequence = payload.sequence
            nextGameplayEventSequence = max(nextGameplayEventSequence, payload.sequence)
            onInitialization?(payload)
            return true
        case let .event(event):
            if case let .event(event) = message {
                guard event.sequence > lastReceivedEventSequence else { return false }
                guard event.sequence == lastReceivedEventSequence + 1 else {
                    onRecoveryRequested?(lastReceivedEventSequence + 1)
                    if let recovery = recoveryProvider?(lastReceivedEventSequence + 1) {
                        send(.recovery(recovery), to: peerID ?? transport.localPeerID)
                    }
                    return false
                }
                guard appliedEvents.insertIfNew(
                    .matchEnded,
                    key: "\(event.sessionID):\(event.sequence)"
                ) else { return false }
                if var system = eventReplicationSystem {
                    guard system.receive(event) == .accepted else { return false }
                    eventReplicationSystem = system
                }
                lastReceivedEventSequence = event.sequence
                nextGameplayEventSequence = max(nextGameplayEventSequence, event.sequence)
                onEvent?(event)
            }
            return true
        case let .recovery(payload):
            guard var system = eventReplicationSystem,
                  system.apply(payload) == .accepted else { return false }
            eventReplicationSystem = system
            onRecovery?(payload)
            return true
        }
        return true
    }

    private func handle(_ hello: MultiplayerHello) {
        guard hello.peerID != transport.localPeerID else {
            return
        }
        guard hello.protocolVersion == protocolVersion else {
            return
        }

        guard hasPriority(over: hello) else {
            sessionID = hello.sessionID
            becomeClient(hostID: hello.peerID)
            send(.joinRequest(MultiplayerJoinRequest(
                sessionID: sessionID,
                peerID: transport.localPeerID,
                protocolVersion: protocolVersion
            )), to: hello.peerID)
            return
        }

        becomeHost()
        send(.hostAnnouncement(MultiplayerHostAnnouncement(
            sessionID: sessionID,
            hostID: transport.localPeerID,
            hostStartedAt: startedAt,
            protocolVersion: protocolVersion
        )))
    }

    private func handle(_ announcement: MultiplayerHostAnnouncement) {
        guard announcement.protocolVersion == protocolVersion else {
            return
        }
        guard announcement.hostID != transport.localPeerID else {
            return
        }

        sessionID = announcement.sessionID
        becomeClient(hostID: announcement.hostID)
        send(.joinRequest(MultiplayerJoinRequest(
            sessionID: sessionID,
            peerID: transport.localPeerID,
            protocolVersion: protocolVersion
        )), to: announcement.hostID)
    }

    private func handle(_ request: MultiplayerJoinRequest) {
        guard role == .host,
              isCompatible(sessionID: request.sessionID, version: request.protocolVersion),
              request.peerID != transport.localPeerID,
              transport.connectedPeerIDs.contains(request.peerID),
              acceptedPeerIDs.insert(request.peerID).inserted else { return }

        send(.joinAccepted(MultiplayerJoinAccepted(
            sessionID: sessionID,
            peerID: request.peerID,
            hostID: transport.localPeerID,
            protocolVersion: protocolVersion
        )), to: request.peerID)
        onPeerJoined?(request.peerID)
    }

    private func handle(_ accepted: MultiplayerJoinAccepted) {
        guard isCompatible(sessionID: accepted.sessionID, version: accepted.protocolVersion),
              accepted.peerID == transport.localPeerID else { return }
        becomeClient(hostID: accepted.hostID)
    }

    private func handle(_ input: MultiplayerPlayerInput) {
        guard role == .host,
              input.playerID != transport.localPeerID,
              acceptedPeerIDs.contains(input.playerID),
              transport.connectedPeerIDs.contains(input.playerID),
              isValid(input),
              latestInputSequences[input.playerID].map({ isNewer(input.sequence, than: $0) }) ?? true else { return }
        latestInputSequences[input.playerID] = input.sequence
        latestInputs[input.playerID] = input
        queuedInputs.append(input)
        onInput?(input)
    }

    private func isValid(_ input: MultiplayerPlayerInput) -> Bool {
        input.movementX.isFinite &&
        input.movementY.isFinite &&
        input.aimAngle.isFinite &&
        hypot(input.movementX, input.movementY) <= 1
    }

    private func isNewer(_ incoming: UInt64, than latest: UInt64) -> Bool {
        let distance = incoming &- latest
        return distance > 0 && distance < UInt64.max / 2
    }

    private func hasPriority(over peer: MultiplayerHello) -> Bool {
        startedAt < peer.startedAt || (startedAt == peer.startedAt && transport.localPeerID < peer.peerID)
    }

    private func isCompatible(sessionID otherSessionID: String, version: Int) -> Bool {
        otherSessionID == sessionID && version == protocolVersion
    }

    private func becomeHost() {
        hostID = transport.localPeerID
        updateRole(.host)
    }

    private func becomeClient(hostID: String) {
        self.hostID = hostID
        updateRole(.client)
    }

    private func updateRole(_ role: MultiplayerSessionRole) {
        guard self.role != role else { return }
        self.role = role
        onRoleChanged?(role)
    }

    private func send(_ message: MultiplayerWireMessage, to peerID: String? = nil) {
        guard let data = try? message.encoded() else { return }
        do {
            if let peerID {
                try transport.send(data, to: peerID, delivery: message.deliveryPolicy)
            } else {
                try transport.broadcast(data, delivery: message.deliveryPolicy)
            }
        } catch let error as MultiplayerTransportError {
            onTransportError?(error)
        } catch {
            // Unknown transport failures do not have a stable protocol representation.
        }
    }
}
