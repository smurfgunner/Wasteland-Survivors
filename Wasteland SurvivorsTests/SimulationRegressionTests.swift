import Foundation
import Testing
@testable import Wasteland_Survivors

@Suite(.serialized)
struct SimulationRegressionTests {
    @Test("Irregular render frames converge with fixed sixty-Hz frames over ten seconds")
    func irregularFramePartitioningRemainsDeterministicLongTerm() {
        // Given identical simulations receiving the same continuous movement intent.
        let initial = GameState.initial(seed: 42, playerID: "player")
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: .init(x: 1, y: 0)
        )
        var fixedFrames = FixedTickSimulationDriver(initialState: initial)
        var irregularFrames = FixedTickSimulationDriver(initialState: initial)

        // When ten seconds are partitioned into fixed and irregular frame durations.
        for _ in 0..<600 {
            _ = fixedFrames.advance(elapsedTime: 1.0 / 60.0, inputs: [input])
        }
        for _ in 0..<200 {
            _ = irregularFrames.advance(elapsedTime: 1.0 / 30.0, inputs: [input])
            _ = irregularFrames.advance(elapsedTime: 1.0 / 120.0, inputs: [input])
            _ = irregularFrames.advance(elapsedTime: 1.0 / 120.0, inputs: [input])
        }

        // Then render cadence has no effect on authoritative state.
        #expect(irregularFrames.state == fixedFrames.state)
        #expect(irregularFrames.state.tick == 600)
    }

    @Test("Long-running simulation keeps resources and numeric state bounded")
    func longRunningSimulationMaintainsResourceBounds() {
        // Given a deterministic game running continuously for ten thousand ticks.
        var driver = FixedTickSimulationDriver(
            initialState: GameState.initial(seed: 42, playerID: "player")
        )
        let input = PlayerInput(
            playerID: "player",
            sequence: 1,
            movement: .zero,
            wantsToAttack: true
        )

        // When the long session advances.
        for _ in 0..<10_000 {
            _ = driver.advance(elapsedTime: 1.0 / 60.0, inputs: [input])
        }

        // Then entity collections stay within production limits and values remain finite.
        #expect(driver.state.zombies.filter { $0.health > 0 }.count <= GameSimulation.Configuration.standard.maxZombies)
        #expect(driver.state.chests.count <= GameSimulation.Configuration.standard.maxChests)
        #expect(driver.state.projectiles.count <= 120)
        #expect(driver.state.players.allSatisfy {
            $0.position.x.isFinite &&
            $0.position.y.isFinite &&
            $0.rotation.isFinite &&
            $0.health.isFinite
        })
        #expect(driver.state.zombies.allSatisfy {
            $0.position.x.isFinite &&
            $0.position.y.isFinite &&
            $0.rotation.isFinite &&
            $0.health.isFinite
        })
    }

    @Test("Simulation rotates zombies toward their selected player while moving")
    func simulationRotatesZombiesTowardTheirSelectedPlayerWhileMoving() {
        // Given a zombie to the right of a player and a movement-free player input.
        let state = GameState(
            seed: 1,
            tick: 0,
            players: [
                GamePlayerState(
                    id: "player",
                    position: .zero,
                    rotation: 0,
                    health: 100,
                    weapon: .pistol,
                    powerUps: []
                )
            ],
            zombies: [
                GameZombieState(
                    id: "zombie",
                    position: CGPointValue(x: 100, y: 0),
                    rotation: 0,
                    health: 60
                )
            ],
            chests: [],
            powerUps: [],
            projectiles: [],
            score: 0,
            isGameOver: false
        )

        // When one authoritative simulation tick is advanced.
        let step = GameSimulation().advance(
            state,
            inputs: [PlayerInput(
                playerID: "player",
                sequence: 1,
                movement: .zero,
                aimAngle: 0
            )],
            tick: 1
        )

        // Then the zombie moves toward and faces the player.
        let zombie = step.state.zombies[0]
        #expect(zombie.position.x < 100)
        #expect(abs(zombie.rotation - .pi) < 0.001)
    }

    @Test("Simulation preserves the legacy zombie movement speed")
    func simulationPreservesLegacyZombieMovementSpeed() {
        let state = GameState(
            seed: 1,
            tick: 0,
            players: [
                GamePlayerState(
                    id: "player",
                    position: .zero,
                    rotation: 0,
                    health: 100,
                    weapon: .pistol,
                    powerUps: []
                )
            ],
            zombies: [
                GameZombieState(
                    id: "zombie",
                    position: CGPointValue(x: 100, y: 0),
                    rotation: 0,
                    health: 60
                )
            ],
            chests: [],
            powerUps: [],
            projectiles: [],
            score: 0,
            isGameOver: false
        )

        let step = GameSimulation().advance(
            state,
            inputs: [PlayerInput(
                playerID: "player",
                sequence: 1,
                movement: .zero,
                aimAngle: 0
            )],
            tick: 1
        )

        #expect(abs(step.state.zombies[0].position.x - (100 - 77.5 / 60)) < 0.001)
    }

    @Test("Simulation auto-aims an attack at the nearest in-range zombie")
    func simulationAutoAimsAnAttackAtTheNearestInRangeZombie() {
        let state = GameState(
            seed: 1,
            tick: 0,
            players: [
                GamePlayerState(
                    id: "player",
                    position: .zero,
                    rotation: 0,
                    health: 100,
                    weapon: .pistol,
                    powerUps: []
                )
            ],
            zombies: [
                GameZombieState(
                    id: "nearest",
                    position: CGPointValue(x: 0, y: 100),
                    rotation: 0,
                    health: 60
                ),
                GameZombieState(
                    id: "farther",
                    position: CGPointValue(x: 100, y: 100),
                    rotation: 0,
                    health: 60
                )
            ],
            chests: [],
            powerUps: [],
            projectiles: [],
            score: 0,
            isGameOver: false
        )

        let step = GameSimulation().advance(
            state,
            inputs: [PlayerInput(
                playerID: "player",
                sequence: 1,
                movement: .zero,
                aimAngle: 0,
                wantsToAttack: true
            )],
            tick: 1
        )

        #expect(abs(step.state.players[0].rotation - (.pi / 2)) < 0.001)
        #expect(step.state.projectiles.count == 1)
        #expect(abs(step.state.projectiles[0].angle - (.pi / 2)) < 0.001)
    }

    @Test("Simulation preserves shotgun spread when resolving a ranged attack")
    func simulationPreservesShotgunSpreadWhenResolvingARangedAttack() {
        // Given a player armed with a shotgun.
        let state = GameState(
            seed: 1,
            tick: 0,
            players: [
                GamePlayerState(
                    id: "player",
                    position: .zero,
                    rotation: 0,
                    health: 100,
                    weapon: .shotgun,
                    powerUps: []
                )
            ],
            zombies: [
                GameZombieState(
                    id: "target",
                    position: CGPointValue(x: 100, y: 0),
                    rotation: 0,
                    health: 60
                )
            ],
            chests: [],
            powerUps: [],
            projectiles: [],
            score: 0,
            isGameOver: false
        )

        // When one attack input is resolved.
        let step = GameSimulation().advance(
            state,
            inputs: [PlayerInput(
                playerID: "player",
                sequence: 1,
                movement: .zero,
                aimAngle: 0,
                wantsToAttack: true
            )],
            tick: 1
        )

        // Then the complete shotgun spread is represented in simulation state.
        #expect(step.state.projectiles.count == 3)
    }

    @Test("Simulation honors an explicit attack target over nearest-target auto-aim")
    func simulationHonorsExplicitAttackTargetOverNearestTargetAutoAim() {
        let state = GameState(
            seed: 1,
            tick: 0,
            players: [
                GamePlayerState(
                    id: "player",
                    position: .zero,
                    rotation: 0,
                    health: 100,
                    weapon: .pistol,
                    powerUps: []
                )
            ],
            zombies: [
                GameZombieState(
                    id: "nearest",
                    position: CGPointValue(x: 0, y: 100),
                    rotation: 0,
                    health: 60
                ),
                GameZombieState(
                    id: "selected",
                    position: CGPointValue(x: 100, y: 0),
                    rotation: 0,
                    health: 60
                )
            ],
            chests: [],
            powerUps: [],
            projectiles: [],
            score: 0,
            isGameOver: false
        )

        let step = GameSimulation().advance(
            state,
            inputs: [PlayerInput(
                playerID: "player",
                sequence: 1,
                movement: .zero,
                aimAngle: 0,
                wantsToAttack: true,
                attackTargetID: "selected"
            )],
            tick: 1
        )

        #expect(step.state.players[0].rotation == 0)
        #expect(step.state.projectiles.first?.angle == 0)
    }
}
