import Foundation

enum ChestSpawnSystem {
    static func chest(
        seed: UInt64,
        tick: UInt64,
        index: Int,
        players: [GamePlayerState]
    ) -> GameChestState? {
        guard let anchor = players
            .filter({ $0.health > 0 })
            .sorted(by: { $0.id < $1.id })
            .first else { return nil }

        let entityID = "chest-\(tick)-\(index)"
        let angle = DeterministicRandom.value(
            seed: seed,
            entityID: entityID,
            tick: tick,
            purpose: "spawn-angle"
        ) * Double.pi * 2
        let radius = 400.0 + DeterministicRandom.value(
            seed: seed,
            entityID: entityID,
            tick: tick,
            purpose: "spawn-radius"
        ) * 700.0

        return GameChestState(
            id: entityID,
            position: anchor.position.adding(
                x: cos(angle) * radius,
                y: sin(angle) * radius
            ),
            isOpened: false
        )
    }
}
