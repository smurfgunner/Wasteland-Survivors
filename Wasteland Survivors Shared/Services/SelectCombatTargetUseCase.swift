import SpriteKit

final class SelectCombatTargetUseCase {
    func execute(player: PlayerNode, zombies: [ZombieNode]) -> ZombieNode? {
        let playerPosition = player.position
        let range = player.currentWeaponRange

        return zombies
            .filter { !$0.isDead }
            .compactMap { (zombie: ZombieNode) -> (ZombieNode, CGFloat)? in
                let distance = hypot(
                    zombie.position.x - playerPosition.x,
                    zombie.position.y - playerPosition.y
                )

                guard distance <= range else {
                    return nil
                }

                return (zombie, distance)
            }
            .min { $0.1 < $1.1 }?
            .0
    }
}
