import Foundation

enum InteractionResolutionSystem {
    static func resolve(
        input: PlayerInput,
        playerIndex: Int,
        state: inout GameState,
        proximity: Double,
        seed: UInt64,
        events: inout [GameplayEvent]
    ) {
        guard state.players.indices.contains(playerIndex),
              state.players[playerIndex].health > 0 else { return }

        if let chestID = input.wantsToOpenChestID,
           let chestIndex = state.chests.firstIndex(where: { $0.id == chestID && !$0.isOpened }),
           state.players[playerIndex].position.distance(to: state.chests[chestIndex].position) <= proximity {
            state.chests[chestIndex].isOpened = true
            let weapon = ChestRewardPolicy.select(
                seed: seed,
                chestID: chestID,
                excluding: state.players[playerIndex].weapon
            )
            state.players[playerIndex].weapon = weapon
            events.append(.chestOpened(
                id: chestID,
                playerID: state.players[playerIndex].id,
                weapon: weapon
            ))
        }

        if let powerUpID = input.wantsToCollectPowerUpID,
           let powerUpIndex = state.powerUps.firstIndex(where: { $0.id == powerUpID }),
           state.players[playerIndex].position.distance(to: state.powerUps[powerUpIndex].position) <= proximity {
            let powerUp = state.powerUps[powerUpIndex]
            guard !state.players[playerIndex].powerUps.contains(powerUp.type) else { return }
            state.players[playerIndex].powerUps.append(powerUp.type)
            state.powerUps.remove(at: powerUpIndex)
            events.append(.powerUpCollected(
                id: powerUp.id,
                playerID: state.players[playerIndex].id,
                type: powerUp.type
            ))
        }
    }
}
