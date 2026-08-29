import SpriteKit

final class UpdateEnemyBehaviorUseCase {
    func execute(
        zombies: [ZombieNode],
        players: [PlayerNode],
        deltaTime: TimeInterval,
        currentTime: TimeInterval,
        onPlayerDamage: (PlayerNode, CGFloat) -> Void
    ) {
        for zombie in zombies where !zombie.isDead {
            guard let target = players.min(by: {
                hypot($0.position.x - zombie.position.x, $0.position.y - zombie.position.y) <
                hypot($1.position.x - zombie.position.x, $1.position.y - zombie.position.y)
            }) else { continue }

            zombie.updateAI(towards: target.position, dt: deltaTime)
            let distance = hypot(target.position.x - zombie.position.x, target.position.y - zombie.position.y)
            if distance < 32, zombie.canAttack(currentTime: currentTime) {
                onPlayerDamage(target, 12)
                zombie.recordAttack(currentTime: currentTime)
            }
        }
    }

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
