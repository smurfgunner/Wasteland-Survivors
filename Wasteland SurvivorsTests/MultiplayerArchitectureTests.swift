import Foundation
import Testing
@testable import Wasteland_Survivors

@Suite("Multiplayer Architecture")
struct MultiplayerArchitectureTests {
    @Test("Seeded entity decisions are stable and isolated")
    func seededEntityDecisionsAreStableAndIsolated() {
        let first = DeterministicRandom.value(
            seed: 42,
            entityID: "zombie-1",
            tick: 120,
            purpose: "target"
        )
        let repeated = DeterministicRandom.value(
            seed: 42,
            entityID: "zombie-1",
            tick: 120,
            purpose: "target"
        )
        let differentEntity = DeterministicRandom.value(
            seed: 42,
            entityID: "zombie-2",
            tick: 120,
            purpose: "target"
        )

        #expect(first == repeated)
        #expect(first != differentEntity)
        #expect(first >= 0 && first < 1)
    }

    @Test("Simulation results do not depend on input collection order")
    func simulationResultsDoNotDependOnInputCollectionOrder() {
        let initial = GameState.initial(seed: 42, playerID: "player-a")
        var state = initial
        state.players.append(GamePlayerState(
            id: "player-b",
            position: CGPointValue(x: 100, y: 0),
            rotation: 0,
            health: 100,
            weapon: .pistol,
            powerUps: []
        ))
        let inputs = [
            PlayerInput(playerID: "player-a", sequence: 1, movement: CGPointValue(x: 1, y: 0)),
            PlayerInput(playerID: "player-b", sequence: 1, movement: CGPointValue(x: 0, y: 1))
        ]

        let forward = GameSimulation().advance(state, inputs: inputs, tick: 1)
        let reversed = GameSimulation().advance(state, inputs: inputs.reversed(), tick: 1)

        #expect(forward.state == reversed.state)
        #expect(forward.events == reversed.events)
    }
    @Test("Seeded zombie spawning is bounded and reproducible")
    func seededZombieSpawningIsBoundedAndReproducible() {
        let simulation = GameSimulation()
        let initial = GameState.initial(seed: 42, playerID: "player")

        let first = simulation.advance(initial, inputs: [], tick: 60)
        let repeated = simulation.advance(initial, inputs: [], tick: 60)

        #expect(first.state.zombies.count == 1)
        #expect(first.state.zombies == repeated.state.zombies)
        #expect(first.state.zombies[0].id == "zombie-60-0")

        var state = first.state
        for tick in stride(from: 120, through: 1_200, by: 60) {
            state = simulation.advance(state, inputs: [], tick: UInt64(tick)).state
        }

        #expect(state.zombies.count <= GameSimulation.Configuration.standard.maxZombies)
    }

    @Test("NPC target selection is stable when player ordering changes")
    func npcTargetSelectionIsStableWhenPlayerOrderingChanges() {
        let zombie = GameZombieState(
            id: "zombie-1",
            position: .zero,
            rotation: 0,
            health: 100
        )
        let playerA = GamePlayerState(
            id: "player-a",
            position: CGPointValue(x: -100, y: 0),
            rotation: 0,
            health: 100,
            weapon: .pistol,
            powerUps: []
        )
        let playerB = GamePlayerState(
            id: "player-b",
            position: CGPointValue(x: 100, y: 0),
            rotation: 0,
            health: 100,
            weapon: .pistol,
            powerUps: []
        )
        let simulation = GameSimulation()
        var firstState = GameState.initial(seed: 1, playerID: playerA.id)
        firstState.players = [playerA, playerB]
        firstState.zombies = [zombie]
        var secondState = firstState
        secondState.players = [playerB, playerA]

        let first = simulation.advance(firstState, inputs: [], tick: 1)
        let second = simulation.advance(secondState, inputs: [], tick: 1)

        #expect(first.state.zombies == second.state.zombies)
    }

    @Test("Identical seed and inputs produce identical simulation state")
    func identicalInputsProduceIdenticalState() {
        // Given two matches with the same immutable initial state.
        let initial = GameState.initial(seed: 42, playerID: "player")
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: CGPointValue(x: 1, y: 0)
        )
        let simulation = GameSimulation()

        // When both matches advance through the same fixed ticks.
        let first = simulation.advance(initial, inputs: [input], tick: 1)
        let second = simulation.advance(initial, inputs: [input], tick: 1)

        // Then the observable state and events are identical.
        #expect(first.state == second.state)
        #expect(first.events == second.events)
    }

    @Test("Player movement is deterministic and normalized")
    func playerMovementIsNormalized() {
        // Given a player and a diagonal input.
        let initial = GameState.initial(seed: 1, playerID: "player")
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: CGPointValue(x: 1, y: 1)
        )

        // When one fixed tick advances.
        let result = GameSimulation().advance(initial, inputs: [input], tick: 1)
        let player = result.state.players[0]

        // Then diagonal movement has the same magnitude as cardinal movement.
        #expect(abs(player.position.x - player.position.y) < 0.0001)
        #expect(abs(player.position.x - (180.0 / 60.0 / sqrt(2))) < 0.0001)
        #expect(result.state.tick == 1)
    }

    @Test("Invalid player input cannot move another player")
    func invalidPlayerInputIsIgnored() {
        // Given a match owned by player-a and input claiming to be player-b.
        let initial = GameState.initial(seed: 1, playerID: "player-a")
        let input = PlayerInput(
            playerID: "player-b",
            sequence: 1,
            movement: CGPointValue(x: 1, y: 0)
        )

        // When the host advances the match.
        let result = GameSimulation().advance(initial, inputs: [input], tick: 1)

        // Then player-a remains at its authoritative position.
        #expect(result.state.players[0].position == .zero)
    }

    @Test("Attack intent respects the weapon cooldown")
    func attackIntentRespectsWeaponCooldown() {
        var initial = GameState.initial(seed: 1, playerID: "player")
        initial.players[0].weapon = .sword
        initial.zombies = [GameZombieState(
            id: "zombie-1",
            position: CGPointValue(x: 10, y: 0),
            rotation: 0,
            health: 100
        )]
        let simulation = GameSimulation()
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: .zero,
            wantsToAttack: true
        )

        let first = simulation.advance(initial, inputs: [input], tick: 1)
        let second = simulation.advance(first.state, inputs: [input], tick: 2)

        #expect(first.state.zombies[0].health == 40)
        #expect(second.state.zombies[0].health == 40)
        #expect(!second.events.contains {
            if case .meleeAttack = $0 { return true }
            return false
        })
    }

    @Test("Ranged attack creates a deterministic projectile")
    func rangedAttackCreatesDeterministicProjectile() {
        var initial = GameState.initial(seed: 1, playerID: "player")
        initial.players[0].weapon = .rifle
        initial.zombies = [GameZombieState(
            id: "zombie-1",
            position: CGPointValue(x: 100, y: 0),
            rotation: 0,
            health: 1_000
        )]
        let simulation = GameSimulation()
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: true
        )

        let result = simulation.advance(initial, inputs: [input], tick: 1)

        #expect(result.state.projectiles.count == 1)
        #expect(result.state.projectiles[0].id == "projectile-1-player")
        #expect(result.events.contains(.projectileSpawned(id: "projectile-1-player", ownerID: "player")))
    }

    @Test("Projectile collision damages and removes a zombie exactly once")
    func projectileCollisionDamagesAndRemovesZombieExactlyOnce() {
        var initial = GameState.initial(seed: 1, playerID: "player")
        initial.players[0].weapon = .rifle
        initial.zombies = [GameZombieState(
            id: "zombie-1",
            position: CGPointValue(x: 7, y: 0),
            rotation: 0,
            health: 18
        )]
        let simulation = GameSimulation()
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: true
        )

        let result = simulation.advance(initial, inputs: [input], tick: 1)

        #expect(result.state.projectiles.isEmpty)
        #expect(result.state.zombies[0].health == 0)
        #expect(result.state.score == 1)
        #expect(result.events.contains(.zombieDamaged(id: "damage-projectile-1-player-zombie-1", amount: 18)))
        #expect(result.events.contains(.zombieKilled(id: "zombie-1", ownerID: "player")))
    }

    @Test("Unresolved projectiles expire after their deterministic lifetime")
    func unresolvedProjectilesExpireAfterDeterministicLifetime() {
        var initial = GameState.initial(seed: 1, playerID: "player")
        initial.players[0].weapon = .rifle
        initial.zombies = [GameZombieState(
            id: "zombie-1",
            position: CGPointValue(x: 100, y: 0),
            rotation: 0,
            health: 1_000
        )]
        let simulation = GameSimulation()
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: true
        )

        let spawned = simulation.advance(initial, inputs: [input], tick: 1)
        let expired = simulation.advance(spawned.state, inputs: [], tick: 121)

        #expect(spawned.state.projectiles.count == 1)
        #expect(expired.state.projectiles.isEmpty)
    }

    @Test("Melee damage and score are authoritative simulation outcomes")
    func meleeDamageAndScoreAreAuthoritative() {
        // Given a zombie in range of the player's attack.
        var initial = GameState.initial(seed: 1, playerID: "player")
        initial.players[0].weapon = .sword
        initial.zombies = [GameZombieState(
            id: "zombie-1",
            position: CGPointValue(x: 10, y: 0),
            rotation: 0,
            health: 20
        )]
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: .zero,
            wantsToAttack: true
        )

        // When the host advances one tick.
        let result = GameSimulation().advance(initial, inputs: [input], tick: 1)

        // Then the zombie is killed and only the host awards score.
        #expect(result.state.zombies[0].health == 0)
        #expect(result.state.score == 1)
        #expect(result.events.contains(.zombieKilled(id: "zombie-1", ownerID: "player")))
    }

    @Test("Zombie contact applies deterministic player damage")
    func zombieContactAppliesDeterministicPlayerDamage() {
        var initial = GameState.initial(seed: 1, playerID: "player")
        initial.zombies = [GameZombieState(
            id: "zombie-1",
            position: CGPointValue(x: 24, y: 0),
            rotation: 0,
            health: 100
        )]

        let result = GameSimulation().advance(initial, inputs: [], tick: 1)

        #expect(result.state.players[0].health == 88)
        #expect(result.events.contains(.playerDamaged(id: "damage-zombie-1-player-1", amount: 12)))
    }

    @Test("Player elimination ends the match only when no players remain alive")
    func playerEliminationEndsMatchOnlyWhenNoPlayersRemainAlive() {
        var initial = GameState.initial(seed: 1, playerID: "player")
        initial.players[0].health = 12
        initial.zombies = [GameZombieState(
            id: "zombie-1",
            position: CGPointValue(x: 24, y: 0),
            rotation: 0,
            health: 100
        )]

        let result = GameSimulation().advance(initial, inputs: [], tick: 1)

        #expect(result.state.players[0].health == 0)
        #expect(result.state.isGameOver)
        #expect(result.events.contains(.playerEliminated(id: "player")))
        #expect(result.events.contains(.matchEnded))
    }

    @Test("A living player prevents match termination")
    func livingPlayerPreventsMatchTermination() {
        var initial = GameState.initial(seed: 1, playerID: "player-a")
        initial.players.append(GamePlayerState(
            id: "player-b",
            position: CGPointValue(x: 200, y: 0),
            rotation: 0,
            health: 100,
            weapon: .pistol,
            powerUps: []
        ))
        initial.players[0].health = 12
        initial.zombies = [GameZombieState(
            id: "zombie-1",
            position: CGPointValue(x: 24, y: 0),
            rotation: 0,
            health: 100
        )]

        let result = GameSimulation().advance(initial, inputs: [], tick: 1)

        #expect(result.state.players[0].health == 0)
        #expect(!result.state.isGameOver)
        #expect(result.events.contains(.playerEliminated(id: "player-a")))
        #expect(!result.events.contains(.matchEnded))
    }

    @Test("Chest opening requires ownership proximity and is single-use")
    func chestOpeningRequiresOwnershipProximityAndIsSingleUse() {
        var initial = GameState.initial(seed: 1, playerID: "player")
        initial.chests = [GameChestState(
            id: "chest-1",
            position: .zero,
            isOpened: false
        )]
        let simulation = GameSimulation()
        let open = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: .zero,
            wantsToOpenChestID: "chest-1"
        )

        let first = simulation.advance(initial, inputs: [open], tick: 1)
        let second = simulation.advance(first.state, inputs: [open], tick: 2)

        #expect(first.state.chests[0].isOpened)
        #expect(first.events.contains {
            if case .chestOpened(id: "chest-1", playerID: "player", _) = $0 { return true }
            return false
        })
        #expect(!second.events.contains {
            if case .chestOpened = $0 { return true }
            return false
        })

        var distant = initial
        distant.chests[0] = GameChestState(
            id: "chest-1",
            position: CGPointValue(x: 1_000, y: 0),
            isOpened: false
        )
        let rejected = simulation.advance(distant, inputs: [open], tick: 1)
        #expect(!rejected.state.chests[0].isOpened)
        #expect(rejected.events.isEmpty)
    }

    @Test("Power-up collection requires proximity and removes the collected item")
    func powerUpCollectionRequiresProximityAndRemovesItem() {
        var initial = GameState.initial(seed: 1, playerID: "player")
        initial.powerUps = [GamePowerUpState(
            id: "power-up-1",
            position: .zero,
            type: .damage
        )]
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: .zero,
            wantsToCollectPowerUpID: "power-up-1"
        )

        let result = GameSimulation().advance(initial, inputs: [input], tick: 1)

        #expect(result.state.powerUps.isEmpty)
        #expect(result.state.players[0].powerUps == [.damage])
        #expect(result.events.contains(.powerUpCollected(
            id: "power-up-1",
            playerID: "player",
            type: .damage
        )))
    }

    @Test("A player cannot collect a power-up by claiming a different player input")
    func playerCannotCollectPowerUpByClaimingDifferentPlayerInput() {
        var initial = GameState.initial(seed: 1, playerID: "player")
        initial.powerUps = [GamePowerUpState(
            id: "power-up-1",
            position: .zero,
            type: .range
        )]
        let input = PlayerInput(
            playerID: "attacker",
            sequence: 1,
            movement: .zero,
            wantsToCollectPowerUpID: "power-up-1"
        )

        let result = GameSimulation().advance(initial, inputs: [input], tick: 1)

        #expect(result.state.powerUps.count == 1)
        #expect(result.state.players[0].powerUps.isEmpty)
        #expect(result.events.isEmpty)
    }

    @Test("Snapshots reject stale sequences and unauthorized owners")
    func snapshotsRejectStaleAndUnauthorizedOwners() throws {
        // Given an authoritative snapshot envelope owned by host.
        let state = GameState.initial(seed: 1, playerID: "player")
        let snapshot = AuthoritativeSnapshot(
            sequence: 4,
            tick: 8,
            serverTime: 1,
            hostID: "host",
            state: state
        )
        let envelope = try snapshot.envelope()

        // When the envelope is validated with a different owner or old sequence.
        #expect(throws: ReplicationError.unauthorizedOwner) {
            try envelope.validate(expectedOwnerID: "attacker")
        }
        #expect(throws: ReplicationError.staleSequence) {
            try envelope.validate(latestSequence: 4)
        }
        #expect(throws: ReplicationError.inconsistentState) {
            try AuthoritativeSnapshot.from(envelope, expectedHostID: "host")
        }
    }

    @Test("Snapshot history retains ordered bounded state")
    func snapshotHistoryIsOrderedAndBounded() {
        // Given a history with a capacity of two.
        var history = SnapshotHistory(capacity: 2)
        let state = GameState.initial(seed: 1, playerID: "player")

        // When three ordered snapshots are appended.
        for sequence in 1...3 {
            _ = history.append(AuthoritativeSnapshot(
                sequence: UInt64(sequence),
                tick: UInt64(sequence),
                serverTime: Double(sequence),
                hostID: "host",
                state: state
            ))
        }

        // Then only the newest two snapshots remain and stale values are rejected.
        #expect(history.snapshots.map(\.sequence) == [2, 3])
        let acceptedDuplicate = history.append(AuthoritativeSnapshot(
            sequence: 3,
            tick: 3,
            serverTime: 3,
            hostID: "host",
            state: state
        ))
        #expect(!acceptedDuplicate)
    }

    @Test("Gameplay events are applied exactly once")
    func gameplayEventsAreDeduplicated() {
        // Given an empty event store and one event ID.
        var store = AppliedEventStore(capacity: 2)
        let event = GameplayEvent.zombieKilled(id: "event-1", ownerID: "player")

        // When the same reliable event is delivered twice.
        let first = store.insertIfNew(event)
        let duplicate = store.insertIfNew(event)

        // Then only the first delivery is accepted.
        #expect(first)
        #expect(!duplicate)
    }

    @Test("Offline transport loops back only while connected")
    func offlineTransportLoopsBackOnlyWhileConnected() throws {
        // Given an offline transport and a receiving delegate.
        let transport = OfflineTransport(localPeerID: "offline")
        let delegate = TransportRecorder()
        transport.delegate = delegate

        // When it connects and sends to itself.
        transport.connect()
        try transport.send(Data([1, 2, 3]), to: "offline")

        // Then the state and message are observable through the contract.
        #expect(transport.state == .connected)
        #expect(delegate.received == [Data([1, 2, 3])])

        // When it disconnects, sending fails.
        transport.disconnect()
        #expect(throws: MultiplayerTransportError.notConnected) {
            try transport.send(Data(), to: "offline")
        }
    }

    @Test("Applied event history evicts the oldest event deterministically")
    func appliedEventHistoryEvictsOldestEvent() {
        var store = AppliedEventStore(capacity: 2)
        let first = GameplayEvent.zombieKilled(id: "event-1", ownerID: "player")
        let second = GameplayEvent.zombieKilled(id: "event-2", ownerID: "player")
        let third = GameplayEvent.zombieKilled(id: "event-3", ownerID: "player")

        let insertedFirst = store.insertIfNew(first)
        let insertedSecond = store.insertIfNew(second)
        let insertedThird = store.insertIfNew(third)
        let reinsertedFirst = store.insertIfNew(first)

        #expect(insertedFirst)
        #expect(insertedSecond)
        #expect(insertedThird)
        #expect(reinsertedFirst)
    }
}

private final class TransportRecorder: MultiplayerTransportDelegate {
    var received: [Data] = []
    var states: [MultiplayerTransportState] = []

    func transport(_ transport: MultiplayerTransport, didChange state: MultiplayerTransportState) {
        states.append(state)
    }

    func transport(_ transport: MultiplayerTransport, didReceive data: Data, from peerID: String) {
        received.append(data)
    }
}
