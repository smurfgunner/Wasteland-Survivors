import SpriteKit

final class ResolveMeleeHitsUseCase {
    func execute(
        player: PlayerNode,
        zombies: [ZombieNode],
        weapon: WeaponType,
        targetAngle: CGFloat,
        onHit: (ZombieNode, CGFloat) -> Void
    ) {
        let playerPosition = player.position

        for zombie in zombies where !zombie.isDead {
            let zombiePosition = zombie.position
            let distance = hypot(
                zombiePosition.x - playerPosition.x,
                zombiePosition.y - playerPosition.y
            )

            guard distance <= weapon.range else {
                continue
            }

            let zombieAngle = atan2(
                zombiePosition.y - playerPosition.y,
                zombiePosition.x - playerPosition.x
            )
            let angleDifference = shortestAngleDifference(
                from: targetAngle,
                to: zombieAngle
            )

            guard abs(angleDifference) < 1.1 else {
                continue
            }

            onHit(zombie, weapon.damage)
        }
    }

    private func shortestAngleDifference(from lhs: CGFloat, to rhs: CGFloat) -> CGFloat {
        var difference = rhs - lhs

        while difference > CGFloat.pi {
            difference -= 2 * CGFloat.pi
        }

        while difference < -CGFloat.pi {
            difference += 2 * CGFloat.pi
        }

        return difference
    }
}
