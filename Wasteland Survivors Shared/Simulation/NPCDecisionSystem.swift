import Foundation

enum NPCDecisionSystem {
    static func target(
        for zombie: GameZombieState,
        players: [GamePlayerState]
    ) -> GamePlayerState? {
        players
            .filter { $0.health > 0 }
            .min {
                let firstDistance = zombie.position.distance(to: $0.position)
                let secondDistance = zombie.position.distance(to: $1.position)
                if firstDistance == secondDistance {
                    return $0.id < $1.id
                }
                return firstDistance < secondDistance
            }
    }

    static func nextPosition(
        for zombie: GameZombieState,
        toward target: GamePlayerState,
        speed: Double,
        tickRate: Double
    ) -> CGPointValue {
        let distance = zombie.position.distance(to: target.position)
        guard distance > 24, distance > 0 else {
            return zombie.position
        }

        let ratio = speed / tickRate / distance
        return zombie.position.adding(
            x: (target.position.x - zombie.position.x) * ratio,
            y: (target.position.y - zombie.position.y) * ratio
        )
    }
}
