import Foundation

enum ProjectileResolutionSystem {
    static func advance(
        state: inout GameState,
        speed: Double,
        tickRate: Double,
        collisionRadius: Double,
        lifetimeTicks: UInt64,
        events: inout [GameplayEvent]
    ) {
        var activeProjectiles: [GameProjectileState] = []
        let projectiles = state.projectiles.sorted { $0.id < $1.id }

        for var projectile in projectiles {
            guard state.tick < projectile.spawnedTick + lifetimeTicks else { continue }

            let previousPosition = projectile.position
            let nextPosition = projectile.position.adding(
                x: cos(projectile.angle) * speed / tickRate,
                y: sin(projectile.angle) * speed / tickRate
            )
            projectile.position = nextPosition

            guard let zombieIndex = nearestLivingZombie(
                from: previousPosition,
                to: nextPosition,
                in: state.zombies,
                within: collisionRadius
            ) else {
                activeProjectiles.append(projectile)
                continue
            }

            let zombie = state.zombies[zombieIndex]
            let damageID = "damage-\(projectile.id)-\(zombie.id)"
            state.zombies[zombieIndex].health = max(
                0,
                zombie.health - projectile.damage
            )
            events.append(.zombieDamaged(id: damageID, amount: projectile.damage))

            if state.zombies[zombieIndex].health == 0 {
                state.score += 1
                events.append(.zombieKilled(
                    id: zombie.id,
                    ownerID: projectile.ownerID
                ))
            }
        }

        state.projectiles = activeProjectiles
    }

    private static func nearestLivingZombie(
        from start: CGPointValue,
        to end: CGPointValue,
        in zombies: [GameZombieState],
        within radius: Double
    ) -> Int? {
        zombies.indices
            .filter {
                zombies[$0].health > 0
                    && distance(from: start, to: end, point: zombies[$0].position) <= radius
            }
            .min {
                let firstProgress = progress(from: start, to: end, point: zombies[$0].position)
                let secondProgress = progress(from: start, to: end, point: zombies[$1].position)
                if firstProgress == secondProgress {
                    return zombies[$0].id < zombies[$1].id
                }
                return firstProgress < secondProgress
            }
    }

    private static func progress(
        from start: CGPointValue,
        to end: CGPointValue,
        point: CGPointValue
    ) -> Double {
        let segmentX = end.x - start.x
        let segmentY = end.y - start.y
        let segmentLengthSquared = segmentX * segmentX + segmentY * segmentY
        guard segmentLengthSquared > 0 else { return 0 }

        let pointX = point.x - start.x
        let pointY = point.y - start.y
        return max(
            0,
            min(1, (pointX * segmentX + pointY * segmentY) / segmentLengthSquared)
        )
    }

    private static func distance(
        from start: CGPointValue,
        to end: CGPointValue,
        point: CGPointValue
    ) -> Double {
        let segmentX = end.x - start.x
        let segmentY = end.y - start.y
        let segmentLengthSquared = segmentX * segmentX + segmentY * segmentY
        guard segmentLengthSquared > 0 else {
            return point.distance(to: start)
        }

        let projection = progress(from: start, to: end, point: point)
        let closestPoint = CGPointValue(
            x: start.x + projection * segmentX,
            y: start.y + projection * segmentY
        )
        return point.distance(to: closestPoint)
    }
}
