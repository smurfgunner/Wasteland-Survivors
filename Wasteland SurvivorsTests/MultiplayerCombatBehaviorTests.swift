import Foundation
import Testing
@testable import Wasteland_Survivors

@Suite("Multiplayer Combat Behavior")
struct MultiplayerCombatBehaviorTests {
    @Test("Two players move independently through the deterministic local simulation")
    func twoPlayersMoveIndependentlyThroughDeterministicLocalSimulation() {
        // Given two players with independent movement inputs.
        let state = makeState(
            players: [
                makePlayer(id: "host", position: .zero),
                makePlayer(id: "client", position: CGPointValue(x: 100, y: 100))
            ]
        )

        // When one fixed simulation tick is advanced.
        let step = GameSimulation().advance(
            state,
            inputs: [
                input(for: "host", movement: CGPointValue(x: 1, y: 0), sequence: 1),
                input(for: "client", movement: CGPointValue(x: 0, y: -1), sequence: 1)
            ],
            tick: 1
        )

        // Then each player's movement is applied to the correct player.
        #expect(step.state.players.first { $0.id == "host" }?.position == CGPointValue(x: 3, y: 0))
        #expect(step.state.players.first { $0.id == "client" }?.position == CGPointValue(x: 100, y: 97))
    }

    @Test("Diagonal movement is normalized and cannot exceed configured player speed")
    func diagonalMovementIsNormalizedAndCannotExceedConfiguredPlayerSpeed() {
        // Given a player moving diagonally.
        let state = makeState(players: [makePlayer(id: "player", position: .zero)])

        // When one tick is advanced.
        let step = GameSimulation().advance(
            state,
            inputs: [input(for: "player", movement: CGPointValue(x: 1, y: 1), sequence: 1)],
            tick: 1
        )

        // Then the total movement distance equals one tick of player speed.
        let position = step.state.players[0].position
        #expect(abs(hypot(position.x, position.y) - 3) < 0.0001)
    }

    @Test("A zombie damages every player it is overlapping")
    func zombieDamagesEveryPlayerItIsOverlapping() {
        // Given one zombie overlapping two living players.
        let state = makeState(
            players: [
                makePlayer(id: "a", position: .zero),
                makePlayer(id: "b", position: CGPointValue(x: 10, y: 0))
            ],
            zombies: [makeZombie(id: "zombie", position: CGPointValue(x: 5, y: 0))]
        )

        // When one simulation tick is advanced.
        let step = GameSimulation().advance(
            state,
            inputs: [
                input(for: "a", sequence: 1),
                input(for: "b", sequence: 1)
            ],
            tick: 1
        )

        // Then both players receive the configured contact damage.
        #expect(step.state.players.map(\.health) == [88, 88])
        #expect(step.events.compactMap { event -> String? in
            guard case let .playerDamaged(_, amount) = event else { return nil }
            return String(amount)
        }.count == 2)
    }

    @Test("Contact damage is applied once per cooldown window, not once per render frame")
    func contactDamageIsAppliedOncePerCooldownWindowNotOncePerRenderFrame() {
        // Given a player continuously overlapping a zombie.
        let initial = makeState(
            players: [makePlayer(id: "player", position: .zero)],
            zombies: [makeZombie(id: "zombie", position: .zero)]
        )
        var driver = FixedTickSimulationDriver(initialState: initial)

        // When sixty-one fixed ticks are simulated.
        var allEvents: [GameplayEvent] = []
        for tick in 1...61 {
            let steps = driver.advance(
                elapsedTime: 1.0 / 60.0,
                inputs: [input(for: "player", sequence: UInt64(tick))]
            )
            allEvents.append(contentsOf: steps.flatMap(\.events))
        }

        // Then exactly two damage events occur, at the first tick and after one second.
        let damageEvents = allEvents.filter {
            if case .playerDamaged = $0 { return true }
            return false
        }
        #expect(damageEvents.count == 2)
        #expect(driver.state.players[0].health == 76)
    }

    @Test("Damage from multiple overlapping zombies stacks in one simulation tick")
    func damageFromMultipleOverlappingZombiesStacksInOneSimulationTick() {
        // Given two zombies overlapping the same player.
        let state = makeState(
            players: [makePlayer(id: "player", position: .zero)],
            zombies: [
                makeZombie(id: "a", position: .zero),
                makeZombie(id: "b", position: CGPointValue(x: 1, y: 0))
            ]
        )

        // When one simulation tick is advanced.
        let step = GameSimulation().advance(
            state,
            inputs: [input(for: "player", sequence: 1)],
            tick: 1
        )

        // Then each attacker contributes damage.
        #expect(step.state.players[0].health == 76)
        #expect(step.events.filter {
            if case .playerDamaged = $0 { return true }
            return false
        }.count == 2)
    }

    @Test("Zombie spawning counts living zombies instead of retained dead states")
    func zombieSpawningCountsLivingZombiesInsteadOfRetainedDeadStates() {
        // Given a full zombie list containing only dead zombies at the spawn boundary.
        var state = makeState(
            players: [makePlayer(id: "player", position: .zero)],
            zombies: (0..<18).map { index in
                makeZombie(id: "dead-\(index)", position: .zero, health: 0)
            }
        )
        state.tick = 39

        // When the next authoritative tick is advanced.
        let step = GameSimulation().advance(
            state,
            inputs: [input(for: "player", sequence: 1)],
            tick: 40
        )

        // Then a new zombie is spawned because no retained dead zombie consumes capacity.
        #expect(step.state.zombies.count == 19)
        #expect(step.state.zombies.contains { $0.health > 0 })
    }

    @Test("A dead zombie cannot follow or damage a player during client prediction")
    func deadZombieCannotFollowOrDamageAPlayerDuringClientPrediction() {
        // Given a replicated zombie already marked dead and overlapping a living player.
        let state = makeState(
            players: [makePlayer(id: "player", position: .zero)],
            zombies: [makeZombie(id: "zombie", position: CGPointValue(x: 100, y: 0), health: 0)]
        )

        // When the client prediction simulation advances.
        let step = GameSimulation().advance(
            state,
            inputs: [input(for: "player", sequence: 1)],
            tick: 1
        )

        // Then the dead zombie remains stationary and cannot inflict contact damage.
        #expect(step.state.zombies[0].position == CGPointValue(x: 100, y: 0))
        #expect(step.state.players[0].health == 100)
        #expect(step.events.isEmpty)
    }

    @Test("A dead player does not receive further contact damage or regeneration")
    func deadPlayerDoesNotReceiveFurtherContactDamageOrRegeneration() {
        // Given a player already at zero health and an overlapping zombie.
        let state = makeState(
            players: [makePlayer(id: "player", position: .zero, health: 0)],
            zombies: [makeZombie(id: "zombie", position: .zero)]
        )

        // When multiple ticks are advanced.
        let first = GameSimulation().advance(
            state,
            inputs: [input(for: "player", sequence: 1)],
            tick: 1
        )
        let second = GameSimulation().advance(
            first.state,
            inputs: [input(for: "player", sequence: 2)],
            tick: 2
        )

        // Then health stays zero and no damage or regeneration is emitted.
        #expect(first.state.players[0].health == 0)
        #expect(second.state.players[0].health == 0)
        #expect(second.events.isEmpty)
    }

    @Test("One eliminated player does not end a two-player match")
    func oneEliminatedPlayerDoesNotEndATwoPlayerMatch() {
        // Given one dead player and one living player.
        let state = makeState(
            players: [
                makePlayer(id: "dead", position: .zero, health: 0),
                makePlayer(id: "living", position: CGPointValue(x: 100, y: 100), health: 100)
            ]
        )

        // When the simulation advances.
        let step = GameSimulation().advance(
            state,
            inputs: [
                input(for: "dead", sequence: 1),
                input(for: "living", sequence: 1)
            ],
            tick: 1
        )

        // Then the match continues.
        #expect(step.state.isGameOver == false)
        #expect(step.events.contains { if case .matchEnded = $0 { return true }; return false } == false)
    }

    @Test("The match ends exactly when the final living player is eliminated")
    func matchEndsExactlyWhenTheFinalLivingPlayerIsEliminated() {
        // Given the final living player has twelve health and is overlapping a zombie.
        let state = makeState(
            players: [
                makePlayer(id: "dead", position: CGPointValue(x: 100, y: 100), health: 0),
                makePlayer(id: "living", position: .zero, health: 12)
            ],
            zombies: [makeZombie(id: "zombie", position: .zero)]
        )

        // When the damaging tick is simulated.
        let step = GameSimulation().advance(
            state,
            inputs: [
                input(for: "dead", sequence: 1),
                input(for: "living", sequence: 1)
            ],
            tick: 1
        )

        // Then elimination and match-ended events are both emitted.
        #expect(step.state.players[1].health == 0)
        #expect(step.events.contains { if case .playerEliminated(id: "living") = $0 { return true }; return false })
        #expect(step.events.contains { if case .matchEnded = $0 { return true }; return false })
        #expect(step.state.isGameOver)
    }

    @Test("Player damage is regenerated only after four seconds without further damage")
    func playerDamageIsRegeneratedOnlyAfterFourSecondsWithoutFurtherDamage() {
        // Given a player who takes one contact hit.
        let initial = makeState(
            players: [makePlayer(id: "player", position: .zero)],
            zombies: [makeZombie(id: "zombie", position: .zero)]
        )
        var driver = FixedTickSimulationDriver(initialState: initial)
        _ = driver.advance(
            elapsedTime: 1.0 / 60.0,
            inputs: [input(for: "player", sequence: 1)]
        )

        // Remove the attacker after the first hit so only regeneration is measured.
        var postDamage = driver.state
        postDamage.zombies.removeAll()
        driver.replaceState(postDamage)

        // When one tick beyond the four-second regeneration delay passes.
        for tick in 2...241 {
            _ = driver.advance(
                elapsedTime: 1.0 / 60.0,
                inputs: [input(for: "player", movement: CGPointValue(x: 1, y: 0), sequence: UInt64(tick))]
            )
        }

        // Then the player has begun recovering, but never exceeds maximum health.
        #expect(driver.state.players[0].health > 88)
        #expect(driver.state.players[0].health <= 100)
    }

    @Test("Melee attacks damage a zombie once and emit an attack event")
    func meleeAttacksDamageAZombieOnceAndEmitAnAttackEvent() {
        // Given an in-range player with a melee weapon.
        let state = makeState(
            players: [makePlayer(id: "player", position: .zero, weapon: .sword)],
            zombies: [makeZombie(id: "zombie", position: CGPointValue(x: 50, y: 0))]
        )

        // When one attack input is resolved.
        let step = GameSimulation().advance(
            state,
            inputs: [input(for: "player", sequence: 1, wantsToAttack: true)],
            tick: 1
        )

        // Then the zombie loses the weapon damage and one melee event is emitted.
        #expect(step.state.zombies[0].health == 0)
        #expect(step.events.contains { if case .meleeAttack(_, ownerID: "player") = $0 { return true }; return false })
        #expect(step.events.contains { if case .zombieKilled(id: "zombie", ownerID: "player") = $0 { return true }; return false })
    }

    @Test("Every melee player emits a visual attack event for its own attack")
    func everyMeleePlayerEmitsAVisualAttackEventForItsOwnAttack() {
        // Given two melee players with separate in-range targets.
        let state = makeState(
            players: [
                makePlayer(id: "host", position: .zero, weapon: .sword),
                makePlayer(id: "client", position: CGPointValue(x: 200, y: 0), weapon: .spear)
            ],
            zombies: [
                makeZombie(id: "host-zombie", position: CGPointValue(x: 50, y: 0)),
                makeZombie(id: "client-zombie", position: CGPointValue(x: 250, y: 0))
            ]
        )

        // When the authoritative multiplayer tick resolves both attacks.
        let step = GameSimulation().advance(
            state,
            inputs: [
                input(for: "host", sequence: 1, wantsToAttack: true),
                input(for: "client", sequence: 1, wantsToAttack: true)
            ],
            tick: 1
        )

        // Then each player emits one attack event that peers can render.
        let attackers = step.events.compactMap { event -> String? in
            if case let .meleeAttack(_, ownerID) = event {
                return ownerID
            }
            return nil
        }
        #expect(attackers.count == 2)
        #expect(Set(attackers) == ["host", "client"])
    }

    @Test("Ranged projectiles preserve their owner and damage through collision resolution")
    func rangedProjectilesPreserveTheirOwnerAndDamageThroughCollisionResolution() {
        // Given a ranged player and a zombie on the firing line.
        let state = makeState(
            players: [makePlayer(id: "player", position: .zero, weapon: .pistol)],
            zombies: [makeZombie(id: "zombie", position: CGPointValue(x: 5, y: 0))]
        )

        // When the firing tick is simulated.
        let step = GameSimulation().advance(
            state,
            inputs: [input(for: "player", sequence: 1, wantsToAttack: true)],
            tick: 1
        )

        // Then the projectile damages the zombie and credits its owner.
        #expect(step.state.zombies[0].health == 30)
        #expect(step.events.contains {
            if case let .zombieDamaged(_, amount) = $0 { return amount == 30 }
            return false
        })
        #expect(step.state.projectiles.isEmpty)
    }

    @Test("A shotgun attack creates three independently resolvable projectiles")
    func aShotgunAttackCreatesThreeIndependentlyResolvableProjectiles() {
        // Given a shotgun with an in-range target.
        let state = makeState(
            players: [makePlayer(id: "player", position: .zero, weapon: .shotgun)],
            zombies: [makeZombie(id: "zombie", position: CGPointValue(x: 50, y: 0))]
        )

        // When one attack is simulated.
        let step = GameSimulation().advance(
            state,
            inputs: [input(for: "player", sequence: 1, wantsToAttack: true)],
            tick: 1
        )

        // Then three projectile states carry the same owner and positive damage.
        #expect(step.state.projectiles.count == 3)
        #expect(step.state.projectiles.allSatisfy { $0.ownerID == "player" && $0.damage > 0 })
    }

    @Test("Recovery can restore a zombie that is present in the authoritative state")
    func recoveryCanRestoreAZombiePresentInAuthoritativeState() {
        // Given a client node that was prematurely marked dead by a local visual collision.
        let zombie = ZombieNode(multiplayerID: "zombie")
        zombie.apply(multiplayerHealth: 0)

        // When recovery reports that the zombie is still alive.
        zombie.apply(multiplayerHealth: 30)

        // Then the client restores the authoritative living state.
        #expect(zombie.isDead == false)
        #expect(zombie.health == 30)
    }

    @Test("Client prediction replays pending movement without changing recovered health")
    func clientPredictionReplaysPendingMovementWithoutChangingAuthoritativeHealth() {
        // Given recovered authoritative state with a damaged local player and a pending movement input.
        let authoritative = makeState(
            players: [makePlayer(id: "client", position: .zero, health: 40)],
            zombies: [makeZombie(id: "zombie", position: CGPointValue(x: 200, y: 0))]
        )
        let pending = input(for: "client", movement: CGPointValue(x: 1, y: 0), sequence: 5)

        // When the local prediction driver replays the input.
        var driver = FixedTickSimulationDriver(initialState: authoritative)
        let steps = driver.advance(elapsedTime: 1.0 / 60.0, inputs: [pending])

        // Then prediction preserves the recovered health while applying movement.
        #expect(steps.last?.state.players[0].health == 40)
        #expect(steps.last?.state.players[0].position == CGPointValue(x: 3, y: 0))
    }

    private func makeState(
        players: [GamePlayerState],
        zombies: [GameZombieState] = [],
        isGameOver: Bool = false
    ) -> GameState {
        GameState(seed: 42, tick: 0, players: players, zombies: zombies, chests: [], powerUps: [], projectiles: [], score: 0, isGameOver: isGameOver)
    }

    private func makePlayer(
        id: String,
        position: CGPointValue,
        health: Double = 100,
        weapon: WeaponType = .pistol
    ) -> GamePlayerState {
        GamePlayerState(id: id, position: position, rotation: 0, health: health, weapon: weapon, powerUps: [])
    }

    private func makeZombie(
        id: String,
        position: CGPointValue,
        health: Double = 60
    ) -> GameZombieState {
        GameZombieState(id: id, position: position, rotation: 0, health: health)
    }

    private func input(
        for playerID: String,
        movement: CGPointValue = .zero,
        sequence: UInt64,
        wantsToAttack: Bool = false
    ) -> PlayerInput {
        PlayerInput(playerID: playerID, sequence: sequence, movement: movement, aimAngle: 0, wantsToAttack: wantsToAttack)
    }

}
