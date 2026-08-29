import Testing
@testable import Wasteland_Survivors

@Suite("Simulation Power-Up Effects")
struct SimulationPowerUpTests {
    @Test("Damage power-up modifies authoritative projectile damage")
    func damagePowerUpModifiesAuthoritativeProjectileDamage() {
        // Given a player with a damage power-up and a ranged weapon.
        var state = GameState.initial(seed: 1, playerID: "player")
        state.players[0].powerUps = [.damage]

        // When the player attacks in the authoritative simulation.
        let result = GameSimulation().advance(
            state,
            inputs: [PlayerInput(playerID: "player", sequence: 1, movement: .zero, wantsToAttack: true)],
            tick: 1
        )

        // Then the projectile carries the upgraded damage value.
        #expect(result.state.projectiles.count == 1)
        #expect(result.state.projectiles[0].damage == Double(WeaponType.pistol.damage) * 1.25)
    }

    @Test("Range power-up modifies authoritative melee target eligibility")
    func rangePowerUpModifiesAuthoritativeMeleeTargetEligibility() {
        // Given identical sword attacks with and without the range power-up.
        var baseState = GameState.initial(seed: 1, playerID: "player")
        baseState.players[0].weapon = .sword
        baseState.zombies = [
            GameZombieState(
                id: "zombie-1",
                position: CGPointValue(x: 100, y: 0),
                rotation: 0,
                health: 100
            )
        ]
        var upgradedState = baseState
        upgradedState.players[0].powerUps = [.range]
        let attack = PlayerInput(playerID: "player", sequence: 1, movement: .zero, wantsToAttack: true)

        // When both players attack in the authoritative simulation.
        let baseResult = GameSimulation().advance(baseState, inputs: [attack], tick: 1)
        let upgradedResult = GameSimulation().advance(upgradedState, inputs: [attack], tick: 1)

        // Then only the upgraded range permits the melee hit.
        #expect(baseResult.state.zombies[0].health == 100)
        #expect(upgradedResult.state.zombies[0].health == 100 - Double(WeaponType.sword.damage))
        #expect(upgradedResult.events.contains { event in
            if case .meleeAttack = event { return true }
            return false
        })
    }

    @Test("Mixed and duplicate power-ups produce one order-independent modifier set")
    func mixedAndDuplicatePowerUpsProduceOneOrderIndependentModifierSet() {
        // Given equivalent players with the same mixed power-ups in different orders and with a duplicate.
        var firstState = GameState.initial(seed: 1, playerID: "player")
        firstState.players[0].powerUps = [.damage, .range, .fireRate]
        var secondState = firstState
        secondState.players[0].powerUps = [.fireRate, .damage, .damage, .range]
        let attack = PlayerInput(playerID: "player", sequence: 1, movement: .zero, wantsToAttack: true)

        // When both authoritative simulations process the same attack.
        let firstResult = GameSimulation().advance(firstState, inputs: [attack], tick: 1)
        let secondResult = GameSimulation().advance(secondState, inputs: [attack], tick: 1)

        // Then the complete gameplay result is identical and damage is upgraded only once.
        #expect(firstResult == secondResult)
        #expect(firstResult.state.projectiles[0].damage == Double(WeaponType.pistol.damage) * 1.25)
    }

    @Test("Fire-rate power-up shortens authoritative attack cooldown")
    func fireRatePowerUpShortensAuthoritativeAttackCooldown() {
        // Given a player with a fire-rate power-up and a ranged weapon.
        var state = GameState.initial(seed: 1, playerID: "player")
        state.players[0].powerUps = [.fireRate]
        let simulation = GameSimulation()
        let attack = PlayerInput(playerID: "player", sequence: 1, movement: .zero, wantsToAttack: true)

        // When the player attacks again at the upgraded cooldown boundary.
        let first = simulation.advance(state, inputs: [attack], tick: 1)
        let upgradedCooldown = UInt64((WeaponType.pistol.fireRate * 0.75 * 60).rounded())
        let result = simulation.advance(
            first.state,
            inputs: [attack],
            tick: 1 + upgradedCooldown
        )

        // Then the second attack is accepted at the shorter boundary.
        #expect(result.events.contains { event in
            if case .projectileSpawned = event { return true }
            return false
        })
    }
}
