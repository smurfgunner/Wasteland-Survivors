import Testing
@testable import Wasteland_Survivors

@Suite("Weapon Attack Cooldowns")
struct WeaponAttackCooldownTests {
    @Test("Each weapon uses its configured fire rate for attack timing", arguments: WeaponType.allCases)
    func eachWeaponUsesConfiguredFireRateForAttackTiming(weapon: WeaponType) {
        // Given a player equipped with one supported weapon and a target when melee is required.
        let tickRate = GameSimulation.Configuration.standard.tickRate
        let expectedCooldown = UInt64((weapon.fireRate * tickRate).rounded())
        var initial = GameState.initial(seed: 1, playerID: "player")
        initial.players[0].weapon = weapon
        if weapon.category == .melee {
            initial.zombies = [
                GameZombieState(
                    id: "zombie-1",
                    position: CGPointValue(x: 10, y: 0),
                    rotation: 0,
                    health: 1_000
                )
            ]
        }
        let simulation = GameSimulation()
        let attack = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: true
        )

        // When the player attacks once, then attacks immediately before and exactly at the configured cooldown.
        let first = simulation.advance(initial, inputs: [attack], tick: 1)
        let beforeCooldown = simulation.advance(
            first.state,
            inputs: [attack],
            tick: 1 + max(0, expectedCooldown - 1)
        )
        let atCooldown = simulation.advance(
            beforeCooldown.state,
            inputs: [attack],
            tick: 1 + expectedCooldown
        )

        // Then the first and boundary attacks happen, but the early attack does not.
        #expect(attackCount(in: first.events, weapon: weapon) == 1)
        #expect(attackCount(in: beforeCooldown.events, weapon: weapon) == 0)
        #expect(attackCount(in: atCooldown.events, weapon: weapon) == 1)
    }
}

private func attackCount(in events: [GameplayEvent], weapon: WeaponType) -> Int {
    events.reduce(into: 0) { count, event in
        switch event {
        case .projectileSpawned where weapon.category == .ranged,
             .meleeAttack where weapon.category == .melee:
            count += 1
        default:
            break
        }
    }
}
