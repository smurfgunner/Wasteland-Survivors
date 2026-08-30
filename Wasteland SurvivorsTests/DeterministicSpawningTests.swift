import Testing
@testable import Wasteland_Survivors

@Suite("Deterministic Spawning")
struct DeterministicSpawningTests {
    @Test("Chest spawning is timed, seeded, and capped by the simulation")
    func chestSpawningIsTimedSeededAndCapped() {
        let configuration = GameSimulation.Configuration(
            playerSpeed: 180,
            zombieSpeed: 55,
            tickRate: 60,
            zombieDamage: 12,
            attackRange: 160,
            maxZombies: 18,
            zombieSpawnIntervalTicks: 10_000,
            chestSpawnIntervalTicks: 2,
            maxChests: 2,
            projectileSpeed: 420,
            projectileCollisionRadius: 20,
            projectileLifetimeTicks: 120,
            playerContactRadius: 24
        )
        let simulation = GameSimulation(configuration: configuration)
        let initial = GameState.initial(seed: 42, playerID: "player")

        let beforeInterval = simulation.advance(initial, inputs: [], tick: 1).state
        let firstSpawn = simulation.advance(beforeInterval, inputs: [], tick: 2).state
        let secondSpawn = simulation.advance(firstSpawn, inputs: [], tick: 4).state
        let capped = simulation.advance(secondSpawn, inputs: [], tick: 6).state
        let repeated = simulation.advance(
            simulation.advance(initial, inputs: [], tick: 1).state,
            inputs: [],
            tick: 2
        ).state

        #expect(beforeInterval.chests.isEmpty)
        #expect(firstSpawn.chests.count == 1)
        #expect(firstSpawn.chests == repeated.chests)
        #expect(secondSpawn.chests.count == 2)
        #expect(capped.chests.count == 2)
        #expect(firstSpawn.chests[0].id == "chest-2-0")
    }
}
