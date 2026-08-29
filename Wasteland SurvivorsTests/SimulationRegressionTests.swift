import Foundation
import Testing
@testable import Wasteland_Survivors

@Suite(.serialized)
struct SimulationRegressionTests {
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
