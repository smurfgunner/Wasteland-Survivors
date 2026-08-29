import Testing
@testable import Wasteland_Survivors

@Suite("Deterministic Chest Rewards")
struct ChestRewardPolicyTests {
    @Test("Every supported equipped weapon receives a different supported reward", arguments: WeaponType.allCases)
    func everySupportedEquippedWeaponReceivesDifferentSupportedReward(currentWeapon: WeaponType) {
        // Given a deterministic match seed and chest identity.
        // When a reward is selected for every supported current weapon.
        let reward = ChestRewardPolicy.select(
            seed: 42,
            chestID: "chest-1",
            excluding: currentWeapon
        )

        // Then the reward is supported and never repeats the equipped weapon.
        #expect(WeaponType.allCases.contains(reward))
        #expect(reward != currentWeapon)
    }

    @Test("Authoritative chest opening applies the deterministic policy result")
    func authoritativeChestOpeningAppliesDeterministicPolicyResult() {
        // Given an unopened chest at the player's position in a seeded match.
        var state = GameState.initial(seed: 42, playerID: "player")
        state.chests = [
            GameChestState(id: "chest-1", position: .zero, isOpened: false)
        ]
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: .zero,
            wantsToOpenChestID: "chest-1"
        )

        // When the authoritative simulation resolves the interaction.
        let result = GameSimulation().advance(state, inputs: [input], tick: 1)

        // Then the equipped reward is exactly the deterministic policy result.
        let expected = ChestRewardPolicy.select(seed: 42, chestID: "chest-1", excluding: .pistol)
        #expect(result.state.players[0].weapon == expected)
        #expect(result.events.contains(.chestOpened(id: "chest-1", playerID: "player", weapon: expected)))
    }

    @Test("The same seed and chest identity always select the same reward")
    func sameSeedAndChestIdentityAlwaysSelectSameReward() {
        // Given identical reward-selection inputs.
        // When the reward is selected repeatedly.
        let first = ChestRewardPolicy.select(seed: 42, chestID: "chest-1", excluding: .pistol)
        let second = ChestRewardPolicy.select(seed: 42, chestID: "chest-1", excluding: .pistol)

        // Then selection is reproducible.
        #expect(first == second)
    }

    @Test("Changing chest identity changes the deterministic selection stream")
    func changingChestIdentityChangesDeterministicSelectionStream() {
        // Given two distinct chest identities in the same match.
        let first = ChestRewardPolicy.select(seed: 42, chestID: "chest-1", excluding: .pistol)
        let second = ChestRewardPolicy.select(seed: 42, chestID: "chest-2", excluding: .pistol)

        // Then the selections are deterministic values from independently addressed streams.
        #expect(first != second)
    }
}
