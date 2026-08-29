import Foundation

enum PlayerDamageSystem {
    static func advance(
        state: inout GameState,
        damage: Double,
        contactRadius: Double,
        cooldownTicks: UInt64,
        tick: UInt64,
        events: inout [GameplayEvent]
    ) {
        let zombieIndices = state.zombies.indices.sorted {
            state.zombies[$0].id < state.zombies[$1].id
        }
        let playerIndices = state.players.indices.sorted {
            state.players[$0].id < state.players[$1].id
        }

        for zombieIndex in zombieIndices {
            let zombie = state.zombies[zombieIndex]
            guard zombie.health > 0 else { continue }
            for playerIndex in playerIndices {
                guard state.players[playerIndex].health > 0,
                      zombie.position.distance(to: state.players[playerIndex].position) <= contactRadius else {
                    continue
                }

                let playerID = state.players[playerIndex].id
                let cooldownKey = "\(playerID)::\(zombie.id)"
                guard state.lastDamageTickByPlayer[cooldownKey]
                    .map({ tick >= $0 + cooldownTicks }) ?? true else { continue }
                state.lastDamageTickByPlayer[cooldownKey] = tick
                state.lastDamageTickByPlayer[playerID] = tick
                state.players[playerIndex].health = max(
                    0,
                    state.players[playerIndex].health - damage
                )
                events.append(.playerDamaged(
                    id: "damage-\(zombie.id)-\(playerID)-\(tick)",
                    amount: damage
                ))

                if state.players[playerIndex].health == 0 {
                    events.append(.playerEliminated(id: playerID))
                }
            }
        }
    }
}
