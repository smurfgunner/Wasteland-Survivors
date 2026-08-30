import SpriteKit

enum GameSceneStateAdapter {
    static func gameState(
        localPlayer: PlayerNode,
        remotePlayers: [String: PlayerNode],
        zombies: [ZombieNode],
        chests: [ChestNode],
        powerUps: [PowerUpNode],
        projectiles: [ProjectileNode],
        localPlayerID: String,
        seed: UInt64,
        tick: UInt64,
        score: Int
    ) -> GameState {
        let players = [GamePlayerState(
            id: localPlayerID,
            position: CGPointValue(localPlayer.position),
            rotation: Double(localPlayer.zRotation),
            health: Double(localPlayer.currentHealth),
            weapon: localPlayer.currentWeapon,
            powerUps: localPlayer.appliedPowerUpTypes
        )] + remotePlayers
            .map { id, player in
                GamePlayerState(
                    id: id,
                    position: CGPointValue(player.position),
                    rotation: Double(player.zRotation),
                    health: Double(player.currentHealth),
                    weapon: player.currentWeapon,
                    powerUps: player.appliedPowerUpTypes
                )
            }

        return GameState(
            seed: seed,
            tick: tick,
            players: players,
            zombies: zombies.map {
                GameZombieState(
                    id: $0.multiplayerID,
                    position: CGPointValue($0.position),
                    rotation: Double($0.zRotation),
                    health: Double($0.health)
                )
            },
            chests: chests.map {
                GameChestState(
                    id: $0.multiplayerID,
                    position: CGPointValue($0.position),
                    isOpened: $0.isOpened
                )
            },
            powerUps: powerUps.map {
                GamePowerUpState(
                    id: $0.multiplayerID,
                    position: CGPointValue($0.position),
                    type: $0.powerUp
                )
            },
            projectiles: projectiles.map {
                GameProjectileState(
                    id: $0.multiplayerID,
                    position: CGPointValue($0.position),
                    angle: Double($0.zRotation),
                    weapon: $0.weapon,
                    damage: Double($0.damage)
                )
            },
            score: score,
            isGameOver: false
        )
    }
}

private extension CGPointValue {
    init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }
}
