import Foundation

enum NPCSpawnSystem {
    static func zombie(
        seed: UInt64,
        tick: UInt64,
        index: Int,
        players: [GamePlayerState]
    ) -> GameZombieState? {
        guard let anchor = players
            .filter({ $0.health > 0 })
            .sorted(by: { $0.id < $1.id })
            .first else { return nil }

        let entityID = "zombie-\(tick)-\(index)"
        let angle = DeterministicRandom.value(
            seed: seed,
            entityID: entityID,
            tick: tick,
            purpose: "spawn-angle"
        ) * Double.pi * 2
        let radius = 500.0 + DeterministicRandom.value(
            seed: seed,
            entityID: entityID,
            tick: tick,
            purpose: "spawn-radius"
        ) * 200.0

        return GameZombieState(
            id: entityID,
            position: anchor.position.adding(
                x: cos(angle) * radius,
                y: sin(angle) * radius
            ),
            rotation: angle,
            health: 100
        )
    }
}
