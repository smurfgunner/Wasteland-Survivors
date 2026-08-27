import SpriteKit

final class UpdateEnemyBehaviorUseCase {
    func execute(
        zombies: [ZombieNode],
        playerPosition: CGPoint,
        deltaTime: TimeInterval,
        currentTime: TimeInterval,
        onPlayerDamage: (CGFloat) -> Void
    ) {
        for zombie in zombies where !zombie.isDead {
            zombie.updateAI(towards: playerPosition, dt: deltaTime)

            let distance = hypot(
                playerPosition.x - zombie.position.x,
                playerPosition.y - zombie.position.y
            )

            guard distance < 32, zombie.canAttack(currentTime: currentTime) else {
                continue
            }

            onPlayerDamage(12)
            zombie.recordAttack(currentTime: currentTime)
        }
    }
}
