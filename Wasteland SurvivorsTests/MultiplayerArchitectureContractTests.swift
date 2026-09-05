import CoreGraphics
import Foundation
import SpriteKit
import Testing
@testable import Wasteland_Survivors

@Suite("Multiplayer Architecture Contracts")
struct MultiplayerArchitectureContractTests {
    @Test("Offline scene authority is fixed-tick and independent of render partitioning")
    @MainActor
    func offlineSceneUsesFixedTickSimulation() {
        let whole = GameScene.newGameScene(size: CGSize(width: 800, height: 600))
        let wholeView = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        whole.didMove(to: wholeView)
        whole.startGame()
        whole.update(0)
        whole.update(1)

        let split = GameScene.newGameScene(size: CGSize(width: 800, height: 600))
        let splitView = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        split.didMove(to: splitView)
        split.startGame()
        split.update(0)
        for time in stride(from: 1.0 / 60.0, through: 1.0, by: 1.0 / 60.0) {
            split.update(time)
        }

        #expect(whole.authoritativeSimulationTick == 60)
        #expect(split.authoritativeSimulationTick == whole.authoritativeSimulationTick)
    }

    @Test("A seeded match remains identical across a long deterministic input run")
    func seededMatchRemainsIdenticalAcrossLongRun() {
        let initial = GameState.initial(seed: 9_001, playerID: "player")
        let simulation = GameSimulation()

        var first = initial
        var second = initial

        for tick in 1...300 {
            let input = PlayerInput(
                playerID: "player",
                sequence: UInt64(tick),
                movement: CGPointValue(
                    x: tick.isMultiple(of: 2) ? 1 : -1,
                    y: tick.isMultiple(of: 3) ? 1 : 0
                ),
                aimAngle: Double(tick) / 10,
                wantsToAttack: tick.isMultiple(of: 21)
            )
            first = simulation.advance(first, inputs: [input], tick: UInt64(tick)).state
            second = simulation.advance(second, inputs: [input], tick: UInt64(tick)).state
        }

        #expect(first == second)
    }

    @Test("Fixed-tick accumulation is independent of render frame partitioning")
    func fixedTickAccumulationIsFrameRateIndependent() {
        let initial = GameState.initial(seed: 4_202, playerID: "player")
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: CGPointValue(x: 1, y: 0.25),
            aimAngle: 0.8
        )

        var thirtyFPS = FixedTickSimulationDriver(initialState: initial)
        var sixtyFPS = FixedTickSimulationDriver(initialState: initial)

        _ = thirtyFPS.advance(elapsedTime: 1.0 / 30.0, inputs: [input])
        _ = sixtyFPS.advance(elapsedTime: 1.0 / 60.0, inputs: [input])
        _ = sixtyFPS.advance(elapsedTime: 1.0 / 60.0, inputs: [input])

        #expect(thirtyFPS.state == sixtyFPS.state)
        #expect(thirtyFPS.state.tick == 2)
    }

    @Test("One-shot attack input is consumed once when one frame contains multiple ticks")
    func fixedTickConsumesOneShotAttackOnce() {
        var initial = GameState.initial(seed: 4_204, playerID: "player")
        initial.zombies = [GameZombieState(
            id: "zombie-1",
            position: CGPointValue(x: 0, y: 160),
            rotation: 0,
            health: 1_000
        )]
        let simulation = GameSimulation(configuration: .init(
            playerSpeed: 180,
            zombieSpeed: 55,
            tickRate: 2,
            zombieDamage: 12,
            attackRange: 160,
            maxZombies: 18,
            zombieSpawnIntervalTicks: 60,
            chestSpawnIntervalTicks: 600,
            maxChests: 3,
            projectileSpeed: 420,
            projectileCollisionRadius: 20,
            projectileLifetimeTicks: 120,
            playerContactRadius: 24
        ))
        var driver = FixedTickSimulationDriver(initialState: initial, simulation: simulation, tickRate: 2)
        let input = PlayerInput(playerID: "player", sequence: 1, movement: .zero, wantsToAttack: true)

        let steps = driver.advance(elapsedTime: 1, inputs: [input])

        #expect(steps.count == 2)
        #expect(steps.flatMap(\.events).filter {
            if case .projectileSpawned = $0 { return true }
            return false
        }.count == 1)
        #expect(driver.state.projectiles.count <= 1)
    }

    @Test("Fixed-tick accumulation retains fractional time until the next complete tick")
    func fixedTickAccumulationRetainsRemainder() {
        let initial = GameState.initial(seed: 4_203, playerID: "player")
        var driver = FixedTickSimulationDriver(initialState: initial)
        let input = PlayerInput(playerID: "player", sequence: 1, movement: .zero)

        #expect(driver.advance(elapsedTime: 1.0 / 120.0, inputs: [input]).isEmpty)
        #expect(driver.state.tick == 0)

        let steps = driver.advance(elapsedTime: 1.0 / 120.0, inputs: [input])
        #expect(steps.count == 1)
        #expect(driver.state.tick == 1)
        #expect(driver.advance(elapsedTime: 0, inputs: [input]).isEmpty)
    }

    @Test("Simulation regenerates damaged players after the deterministic delay")
    func simulationRegeneratesPlayerHealth() {
        var initial = GameState.initial(seed: 4_206, playerID: "player")
        initial.players[0].health = 50

        var state = initial
        for tick in 1...240 {
            state = GameSimulation().advance(state, inputs: [], tick: UInt64(tick)).state
        }

        #expect(abs(state.players[0].health - (50 + 10 / 60)) < 0.0001)
    }

    @Test("Simulation rejects non-finite movement and aim input")
    func simulationRejectsNonFiniteInput() {
        let initial = GameState.initial(seed: 4_205, playerID: "player")
        let invalid = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: CGPointValue(x: .nan, y: .infinity),
            aimAngle: .nan
        )

        let result = GameSimulation().advance(initial, inputs: [invalid], tick: 1)

        #expect(result.state.players[0].position == initial.players[0].position)
        #expect(result.state.players[0].rotation == initial.players[0].rotation)
    }

    @Test("Simulation accepts movement, aim, combat, chest, and power-up intent as authoritative input")
    func simulationProcessesAllIntentFields() {
        var initial = GameState.initial(seed: 42, playerID: "player")
        initial.players[0].weapon = .sword
        initial.zombies = [
            GameZombieState(
                id: "zombie",
                position: CGPointValue(x: 10, y: 0),
                rotation: 0,
                health: 20
            )
        ]
        initial.chests = [
            GameChestState(id: "chest", position: .zero, isOpened: false)
        ]
        initial.powerUps = [
            GamePowerUpState(id: "power-up", position: .zero, type: .damage)
        ]

        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: CGPointValue(x: 1, y: 0),
            aimAngle: 0.5,
            wantsToAttack: true,
            wantsToCollectPowerUpID: "power-up"
        )
        let result = GameSimulation().advance(initial, inputs: [input], tick: 1)

        #expect(result.state.players[0].rotation == 0.0)
        #expect(result.state.powerUps.isEmpty)
        #expect(result.state.players[0].powerUps == [.damage])
        #expect(result.events.contains {
            if case .meleeAttack = $0 { return true }
            return false
        })
    }

    @Test("Gameplay event variants have stable non-empty IDs and are codable")
    func gameplayEventVariantsHaveStableIDsAndAreCodable() throws {
        let events: [GameplayEvent] = [
            .projectileSpawned(id: "projectile", ownerID: "player"),
            .meleeAttack(id: "melee", ownerID: "player"),
            .zombieDamaged(id: "damage", amount: 10),
            .zombieKilled(id: "zombie", ownerID: "player"),
            .chestOpened(id: "chest", playerID: "player", weapon: .rifle),
            .powerUpCollected(id: "power-up", playerID: "player", type: .damage),
            .playerDamaged(id: "player-damage", amount: 5),
            .playerEliminated(id: "player"),
            .matchEnded
        ]

        #expect(events.allSatisfy { !$0.id.isEmpty })
        #expect(Set(events.map { $0.id }).count == events.count)

        let encoded = try JSONEncoder().encode(events)
        let decoded = try JSONDecoder().decode([GameplayEvent].self, from: encoded)
        #expect(decoded == events)
    }

    @Test("Two-player deterministic simulation is independent of input collection order")
    func twoPlayerSimulationIsIndependentOfInputCollectionOrder() {
        var first = GameState.initial(seed: 4_321, playerID: "player-a")
        first.players.append(GamePlayerState(
            id: "player-b",
            position: CGPointValue(x: 100, y: -20),
            rotation: 0,
            health: 100,
            weapon: .pistol,
            powerUps: []
        ))
        var second = first
        let simulation = GameSimulation()

        for tick in 1...180 {
            let inputs = [
                PlayerInput(
                    playerID: "player-a",
                    sequence: UInt64(tick),
                    movement: CGPointValue(x: 1, y: tick.isMultiple(of: 2) ? 1 : 0),
                    aimAngle: Double(tick) / 4,
                    wantsToAttack: tick.isMultiple(of: 21)
                ),
                PlayerInput(
                    playerID: "player-b",
                    sequence: UInt64(tick),
                    movement: CGPointValue(x: -1, y: tick.isMultiple(of: 3) ? 1 : 0),
                    aimAngle: -Double(tick) / 5,
                    wantsToAttack: tick.isMultiple(of: 17)
                )
            ]

            first = simulation.advance(first, inputs: inputs, tick: UInt64(tick)).state
            second = simulation.advance(second, inputs: inputs.reversed(), tick: UInt64(tick)).state
        }

        #expect(first == second)
    }

    @Test("State serialization preserves every authoritative simulation field")
    func stateSerializationPreservesAuthoritativeFields() throws {
        var state = GameState.initial(seed: 77, playerID: "player")
        state.tick = 18
        state.score = 4
        state.isGameOver = true
        state.lastAttackTickByPlayer = ["player": 12]
        state.players[0].health = 63
        state.zombies = [GameZombieState(id: "z", position: CGPointValue(x: 2, y: 3), rotation: 0.3, health: 8)]
        state.projectiles = [
            GameProjectileState(
                id: "p",
                ownerID: "player",
                position: CGPointValue(x: 4, y: 5),
                angle: 1.2,
                weapon: .rifle,
                damage: 20,
                spawnedTick: 17
            )
        ]

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)

        #expect(decoded == state)
    }

    @Test("Entity-scoped randomness is independent of evaluation order")
    func entityScopedRandomnessIsIndependentOfEvaluationOrder() {
        let values = ["a", "b", "c"].map {
            DeterministicRandom.value(seed: 123, entityID: $0, tick: 18, purpose: "spawn-angle")
        }
        let reversed = ["c", "b", "a"].map { entityID in
            DeterministicRandom.value(seed: 123, entityID: entityID, tick: 18, purpose: "spawn-angle")
        }.reversed()

        #expect(values == Array(reversed))
    }

    @Test("Wire messages reject malformed payloads")
    func wireMessagesRejectMalformedPayloads() {
        var malformedJSONRejected = false
        do {
            _ = try MultiplayerWireMessage.decode(Data("{".utf8))
        } catch {
            malformedJSONRejected = true
        }

        var malformedMessageRejected = false
        do {
            _ = try MultiplayerWireMessage.decode(Data(#"{ "type": "playerInput", "input": {} }"#.utf8))
        } catch {
            malformedMessageRejected = true
        }

        #expect(malformedJSONRejected)
        #expect(malformedMessageRejected)
    }

    @Test("Host selection uses session time and stable ID as a deterministic tie-break")
    func hostSelectionUsesStableTieBreak() {
        let players = [
            MultiplayerPlayerState(id: "zeta", position: .zero, color: .blue, sessionStartedAt: 10),
            MultiplayerPlayerState(id: "alpha", position: .zero, color: .red, sessionStartedAt: 10),
            MultiplayerPlayerState(id: "earlier", position: .zero, color: .green, sessionStartedAt: 9)
        ]

        #expect(MultiplayerHostSelector.hostID(for: players) == "earlier")
        #expect(MultiplayerHostSelector.hostID(for: Array(players.dropLast())) == "alpha")
    }

    @Test("Offline transport reports transitions and delivers directed and broadcast loopback messages")
    @MainActor
    func offlineTransportReportsTransitionsAndDelivery() throws {
        let transport = OfflineTransport(localPeerID: "offline")
        let recorder = ClaimAuditTransportRecorder()
        transport.delegate = recorder
        let data = Data("message".utf8)

        transport.connect()
        try transport.send(data, to: "offline")
        try transport.broadcast(data)
        transport.disconnect()

        #expect(recorder.states == [.connected, .disconnected])
        #expect(recorder.received == [data, data])
        #expect(throws: MultiplayerTransportError.notConnected) {
            try transport.send(data, to: "offline")
        }
    }

    @Test("Offline transport exposes connection state and rejects unavailable peers")
    @MainActor
    func offlineTransportExposesConnectionState() throws {
        let transport = OfflineTransport(localPeerID: "offline")
        let recorder = ClaimAuditTransportRecorder()
        transport.delegate = recorder

        #expect(transport.state == .idle)
        transport.connect()
        #expect(transport.state == .connected)
        #expect(transport.connectedPeerIDs == ["offline"])

        try transport.send(Data([1, 2, 3]), to: "offline")
        #expect(recorder.received == [Data([1, 2, 3])])

        #expect(throws: MultiplayerTransportError.peerUnavailable) {
            try transport.send(Data(), to: "other-peer")
        }

        transport.disconnect()
        #expect(transport.state == .disconnected)
        #expect(throws: MultiplayerTransportError.notConnected) {
            try transport.broadcast(Data())
        }
    }

    @Test("Gameplay event IDs are idempotent under duplicate delivery")
    func gameplayEventIDsAreIdempotent() {
        var store = AppliedEventStore(capacity: 4)
        let events: [GameplayEvent] = [
            .projectileSpawned(id: "projectile-1", ownerID: "player"),
            .meleeAttack(id: "melee-1", ownerID: "player"),
            .zombieDamaged(id: "damage-1", amount: 10),
            .zombieKilled(id: "zombie-1", ownerID: "player"),
            .chestOpened(id: "chest-1", playerID: "player", weapon: .rifle),
            .powerUpCollected(id: "power-up-1", playerID: "player", type: .damage),
            .playerDamaged(id: "player-damage-1", amount: 5),
            .playerEliminated(id: "player"),
            .matchEnded
        ]

        for event in events {
            let firstDeliveryAccepted = store.insertIfNew(event)
            let duplicateDeliveryAccepted = store.insertIfNew(event)
            #expect(firstDeliveryAccepted)
            #expect(!duplicateDeliveryAccepted)
        }
    }

    @Test("A session queues only the newest accepted input for each peer")
    @MainActor
    func sessionQueuesNewestInputPerPeer() throws {
        let transport = ClaimAuditCoordinatorTransport(localPeerID: "host")
        let coordinator = MultiplayerSessionCoordinator(
            transport: transport,
            sessionID: "match",
            startedAt: 1
        )
        coordinator.start()
        transport.connectedPeerIDs = ["client-a", "client-b"]
        for clientID in ["client-a", "client-b"] {
            try transport.deliver(.hello(.init(
                sessionID: "match",
                peerID: clientID,
                startedAt: 10,
                protocolVersion: 1
            )), from: clientID)
            try transport.deliver(.joinRequest(.init(
                sessionID: "match",
                peerID: clientID,
                protocolVersion: 1
            )), from: clientID)
        }

        let first = MultiplayerPlayerInput(
            playerID: "client-b",
            sequence: 1,
            movement: CGVector(dx: 1, dy: 0),
            aimAngle: 0,
            wantsToAttack: false
        )
        let newer = MultiplayerPlayerInput(
            playerID: "client-b",
            sequence: 2,
            movement: CGVector(dx: 0, dy: 1),
            aimAngle: 1,
            wantsToAttack: true
        )
        let other = MultiplayerPlayerInput(
            playerID: "client-a",
            sequence: 4,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: false
        )

        try transport.deliver(.playerInput(first), from: "client-b")
        try transport.deliver(.playerInput(newer), from: "client-b")
        try transport.deliver(.playerInput(other), from: "client-a")

        #expect(coordinator.consumeQueuedInputs() == [other, newer])
        #expect(coordinator.consumeQueuedInputs() == [other, newer])
    }

}

private struct AuditState {
    let id: String
    let value: Int
}

private final class AuditEntity {
    let id: String
    var value: Int

    init(id: String, value: Int) {
        self.id = id
        self.value = value
    }
}

@MainActor
private final class ClaimAuditTransportRecorder: MultiplayerTransportDelegate {
    var states: [MultiplayerTransportState] = []
    var received: [Data] = []

    func transport(_ transport: MultiplayerTransport, didChange state: MultiplayerTransportState) {
        states.append(state)
    }

    func transport(_ transport: MultiplayerTransport, didReceive data: Data, from peerID: String) {
        received.append(data)
    }
}

@MainActor
private final class ClaimAuditCoordinatorTransport: MultiplayerTransport {
    weak var delegate: MultiplayerTransportDelegate?
    let localPeerID: String
    private(set) var state: MultiplayerTransportState = .idle
    var connectedPeerIDs: Set<String> = []

    init(localPeerID: String) {
        self.localPeerID = localPeerID
    }

    func connect() {
        state = .connected
        delegate?.transport(self, didChange: state)
    }

    func disconnect() {
        state = .disconnected
        delegate?.transport(self, didChange: state)
    }

    func send(_ data: Data, to peerID: String) throws {}
    func broadcast(_ data: Data) throws {}

    func deliver(_ message: MultiplayerWireMessage, from peerID: String) throws {
        delegate?.transport(self, didReceive: try message.encoded(), from: peerID)
    }
}
