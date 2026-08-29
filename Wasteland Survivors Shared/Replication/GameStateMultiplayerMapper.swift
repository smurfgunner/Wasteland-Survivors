import Foundation

enum GameStateMultiplayerMapper {
    static func boardState(
        from state: GameState,
        sequence: UInt64,
        timestamp: TimeInterval,
        hostID: String,
        playerColors: [String: MultiplayerPlayerColor],
        sessionStartTimes: [String: TimeInterval],
        acknowledgedInputSequences: [String: UInt64] = [:]
    ) -> MultiplayerBoardState {
        var board = MultiplayerBoardState(
            sequence: sequence,
            simulationTick: state.tick,
            seed: state.seed,
            timestamp: timestamp,
            serverTime: timestamp,
            hostID: hostID,
            stateHash: 0,
            players: state.players
                .sorted { $0.id < $1.id }
                .map {
                    MultiplayerPlayerState(
                        id: $0.id,
                        position: $0.position.cgPoint,
                        color: playerColors[$0.id] ?? .blue,
                        health: CGFloat($0.health),
                        weapon: $0.weapon,
                        powerUps: $0.powerUps,
                        rotation: CGFloat($0.rotation),
                        sessionStartedAt: sessionStartTimes[$0.id] ?? 0
                    )
                },
            zombies: state.zombies
                .sorted { $0.id < $1.id }
                .map {
                    MultiplayerZombieState(
                        id: $0.id,
                        x: $0.position.x,
                        y: $0.position.y,
                        health: $0.health,
                        rotation: $0.rotation
                    )
                },
            chests: state.chests
                .sorted { $0.id < $1.id }
                .map {
                    MultiplayerChestState(
                        id: $0.id,
                        x: $0.position.x,
                        y: $0.position.y,
                        isOpened: $0.isOpened
                    )
                },
            powerUps: state.powerUps
                .sorted { $0.id < $1.id }
                .map {
                    MultiplayerPowerUpState(
                        id: $0.id,
                        x: $0.position.x,
                        y: $0.position.y,
                        type: $0.type
                    )
                },
            projectiles: state.projectiles
                .sorted { $0.id < $1.id }
                .map {
                    MultiplayerProjectileState(
                        id: $0.id,
                        ownerID: $0.ownerID,
                        x: $0.position.x,
                        y: $0.position.y,
                        angle: $0.angle,
                        weapon: $0.weapon,
                        damage: $0.damage,
                        spawnedTick: $0.spawnedTick
                    )
                },
            killCount: state.score,
            isGameOver: state.isGameOver,
            acknowledgedInputSequences: acknowledgedInputSequences,
            lastAttackTickByPlayer: state.lastAttackTickByPlayer,
            lastDamageTickByPlayer: state.lastDamageTickByPlayer
        )
        board.stateHash = board.contentHash
        return board
    }

    static func gameState(from board: MultiplayerBoardState, seed: UInt64) -> GameState {
        GameState(
            seed: board.seed == 0 ? seed : board.seed,
            tick: board.simulationTick,
            players: board.players.sorted { $0.id < $1.id }.map {
                GamePlayerState(
                    id: $0.id,
                    position: CGPointValue(x: $0.x, y: $0.y),
                    rotation: $0.rotation,
                    health: $0.health,
                    weapon: $0.weapon,
                    powerUps: $0.powerUps
                )
            },
            zombies: board.zombies.sorted { $0.id < $1.id }.map {
                GameZombieState(
                    id: $0.id,
                    position: CGPointValue(x: $0.x, y: $0.y),
                    rotation: $0.rotation,
                    health: $0.health
                )
            },
            chests: board.chests.sorted { $0.id < $1.id }.map {
                GameChestState(
                    id: $0.id,
                    position: CGPointValue(x: $0.x, y: $0.y),
                    isOpened: $0.isOpened
                )
            },
            powerUps: board.powerUps.sorted { $0.id < $1.id }.map {
                GamePowerUpState(
                    id: $0.id,
                    position: CGPointValue(x: $0.x, y: $0.y),
                    type: $0.type
                )
            },
            projectiles: board.projectiles.sorted { $0.id < $1.id }.map {
                GameProjectileState(
                    id: $0.id,
                    ownerID: $0.ownerID,
                    position: CGPointValue(x: $0.x, y: $0.y),
                    angle: $0.angle,
                    weapon: $0.weapon,
                    damage: $0.damage,
                    spawnedTick: $0.spawnedTick
                )
            },
            score: board.killCount,
            isGameOver: board.isGameOver,
            lastAttackTickByPlayer: board.lastAttackTickByPlayer,
            lastDamageTickByPlayer: board.lastDamageTickByPlayer
        )
    }
}
