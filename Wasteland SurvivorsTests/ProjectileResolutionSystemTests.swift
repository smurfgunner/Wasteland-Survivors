import Testing
@testable import Wasteland_Survivors

@Suite("Projectile Resolution")
struct ProjectileResolutionSystemTests {
    @Test("Swept collision detects a high-speed projectile crossing a zombie")
    func sweptCollisionDetectsHighSpeedCrossing() {
        // Given a projectile whose movement crosses a zombie between simulation positions.
        var state = GameState(
            seed: 1,
            tick: 1,
            players: [],
            zombies: [
                GameZombieState(
                    id: "zombie-1",
                    position: CGPointValue(x: 50, y: 0),
                    rotation: 0,
                    health: 10
                )
            ],
            chests: [],
            powerUps: [],
            projectiles: [
                GameProjectileState(
                    id: "projectile-1",
                    ownerID: "player-1",
                    position: CGPointValue(x: 0, y: 0),
                    angle: 0,
                    weapon: .rifle,
                    damage: 10,
                    spawnedTick: 0
                )
            ],
            score: 0,
            isGameOver: false
        )
        var events: [GameplayEvent] = []

        // When one simulation step moves the projectile from x=0 to x=100.
        ProjectileResolutionSystem.advance(
            state: &state,
            speed: 100,
            tickRate: 1,
            collisionRadius: 5,
            lifetimeTicks: 10,
            events: &events
        )

        // Then the crossing collision is resolved even though the endpoint is beyond the zombie.
        #expect(state.zombies[0].health == 0)
        #expect(state.projectiles.isEmpty)
        #expect(state.score == 1)
        #expect(events.contains(.zombieKilled(id: "zombie-1", ownerID: "player-1")))
    }

    @Test("Collision at the exact boundary is resolved")
    func collisionAtExactBoundaryIsResolved() {
        // Given a projectile ending five units from a zombie and a collision radius of five.
        var state = projectileState(
            zombies: [
                GameZombieState(
                    id: "zombie-1",
                    position: CGPointValue(x: 105, y: 0),
                    rotation: 0,
                    health: 10
                )
            ]
        )
        var events: [GameplayEvent] = []

        // When the projectile advances from x=0 to x=100.
        ProjectileResolutionSystem.advance(
            state: &state,
            speed: 100,
            tickRate: 1,
            collisionRadius: 5,
            lifetimeTicks: 10,
            events: &events
        )

        // Then the inclusive boundary collision is resolved.
        #expect(state.zombies[0].health == 0)
        #expect(state.projectiles.isEmpty)
    }

    @Test("Collision just outside the boundary is not resolved")
    func collisionJustOutsideBoundaryIsNotResolved() {
        // Given a projectile ending slightly farther than the collision radius from a zombie.
        var state = projectileState(
            zombies: [
                GameZombieState(
                    id: "zombie-1",
                    position: CGPointValue(x: 105.001, y: 0),
                    rotation: 0,
                    health: 10
                )
            ]
        )
        var events: [GameplayEvent] = []

        // When the projectile advances from x=0 to x=100.
        ProjectileResolutionSystem.advance(
            state: &state,
            speed: 100,
            tickRate: 1,
            collisionRadius: 5,
            lifetimeTicks: 10,
            events: &events
        )

        // Then the projectile remains active and the zombie is unchanged.
        #expect(state.zombies[0].health == 10)
        #expect(state.projectiles.count == 1)
        #expect(events.isEmpty)
    }

    @Test("One projectile damages only one zombie during a crossing step")
    func oneProjectileDamagesOnlyOneZombieDuringCrossingStep() {
        // Given two zombies intersecting the same projectile path.
        var state = projectileState(
            zombies: [
                GameZombieState(id: "zombie-a", position: CGPointValue(x: 40, y: 0), rotation: 0, health: 20),
                GameZombieState(id: "zombie-b", position: CGPointValue(x: 60, y: 0), rotation: 0, health: 20)
            ]
        )
        var events: [GameplayEvent] = []

        // When the projectile crosses both zombies.
        ProjectileResolutionSystem.advance(
            state: &state,
            speed: 100,
            tickRate: 1,
            collisionRadius: 5,
            lifetimeTicks: 10,
            events: &events
        )

        // Then only the nearest stable target is damaged.
        #expect(state.zombies[0].health == 10)
        #expect(state.zombies[1].health == 20)
        #expect(state.projectiles.isEmpty)
        #expect(events.count == 1)
    }

    @Test("Multiple projectiles resolve collisions with multiple zombies in one step")
    func multipleProjectilesResolveMultipleZombieCollisionsInOneStep() {
        // Given two projectiles and two zombies on separate crossing paths.
        var state = projectileState(
            zombies: [
                GameZombieState(id: "zombie-a", position: CGPointValue(x: 50, y: 0), rotation: 0, health: 10),
                GameZombieState(id: "zombie-b", position: CGPointValue(x: 0, y: 50), rotation: 0, health: 10)
            ],
            projectiles: [
                GameProjectileState(id: "projectile-a", ownerID: "player", position: .zero, angle: 0, weapon: .rifle, damage: 10, spawnedTick: 0),
                GameProjectileState(id: "projectile-b", ownerID: "player", position: .zero, angle: .pi / 2, weapon: .rifle, damage: 10, spawnedTick: 0)
            ]
        )
        var events: [GameplayEvent] = []

        // When both projectiles advance during the same simulation step.
        ProjectileResolutionSystem.advance(
            state: &state,
            speed: 100,
            tickRate: 1,
            collisionRadius: 5,
            lifetimeTicks: 10,
            events: &events
        )

        // Then both independent collisions are resolved.
        #expect(state.zombies.map { $0.health } == [0, 0])
        #expect(state.projectiles.isEmpty)
        #expect(state.score == 2)
    }

    @Test("A projectile hits the first zombie encountered along its path")
    func projectileHitsFirstZombieEncounteredAlongPath() {
        // Given an aligned farther zombie whose ID sorts before the nearer zombie.
        var state = projectileState(
            zombies: [
                GameZombieState(id: "zombie-a", position: CGPointValue(x: 90, y: 0), rotation: 0, health: 10),
                GameZombieState(id: "zombie-z", position: CGPointValue(x: 40, y: 0), rotation: 0, health: 10)
            ]
        )
        var events: [GameplayEvent] = []

        // When the projectile crosses both zombies in one step.
        ProjectileResolutionSystem.advance(
            state: &state,
            speed: 100,
            tickRate: 1,
            collisionRadius: 5,
            lifetimeTicks: 10,
            events: &events
        )

        // Then the nearer zombie is hit first, regardless of ID ordering.
        #expect(state.zombies[0].health == 10)
        #expect(state.zombies[1].health == 0)
        #expect(events.contains(.zombieKilled(id: "zombie-z", ownerID: "player-1")))
    }

    @Test("Equal-distance projectile targets use the stable zombie ID tie-breaker")
    func equalDistanceProjectileTargetsUseStableZombieIDTieBreaker() {
        // Given two zombies at the same distance from a projectile's swept path.
        var state = projectileState(
            zombies: [
                GameZombieState(id: "zombie-b", position: CGPointValue(x: 50, y: 3), rotation: 0, health: 10),
                GameZombieState(id: "zombie-a", position: CGPointValue(x: 50, y: -3), rotation: 0, health: 10)
            ]
        )
        var events: [GameplayEvent] = []

        // When the projectile crosses both candidate targets.
        ProjectileResolutionSystem.advance(
            state: &state,
            speed: 100,
            tickRate: 1,
            collisionRadius: 5,
            lifetimeTicks: 10,
            events: &events
        )

        // Then the lexicographically smaller stable ID receives the single hit.
        let healthByID = Dictionary(uniqueKeysWithValues: state.zombies.map { ($0.id, $0.health) })
        #expect(healthByID["zombie-a"] == 0)
        #expect(healthByID["zombie-b"] == 10)
        #expect(events.contains(.zombieKilled(id: "zombie-a", ownerID: "player-1")))
    }

    @Test("Projectile and zombie collection ordering does not change collision results")
    func projectileAndZombieCollectionOrderingDoesNotChangeCollisionResults() {
        // Given identical entities in two different collection orders.
        let zombies = [
            GameZombieState(id: "zombie-a", position: CGPointValue(x: 50, y: 0), rotation: 0, health: 10),
            GameZombieState(id: "zombie-b", position: CGPointValue(x: 0, y: 50), rotation: 0, health: 10)
        ]
        let projectiles = [
            GameProjectileState(id: "projectile-a", ownerID: "player", position: .zero, angle: 0, weapon: .rifle, damage: 10, spawnedTick: 0),
            GameProjectileState(id: "projectile-b", ownerID: "player", position: .zero, angle: .pi / 2, weapon: .rifle, damage: 10, spawnedTick: 0)
        ]
        var firstState = projectileState(zombies: zombies, projectiles: projectiles)
        var secondState = projectileState(zombies: Array(zombies.reversed()), projectiles: Array(projectiles.reversed()))
        var firstEvents: [GameplayEvent] = []
        var secondEvents: [GameplayEvent] = []

        // When both states advance by the same simulation step.
        ProjectileResolutionSystem.advance(state: &firstState, speed: 100, tickRate: 1, collisionRadius: 5, lifetimeTicks: 10, events: &firstEvents)
        ProjectileResolutionSystem.advance(state: &secondState, speed: 100, tickRate: 1, collisionRadius: 5, lifetimeTicks: 10, events: &secondEvents)

        // Then canonical state and events are equivalent.
        #expect(firstState.zombies.sorted { $0.id < $1.id } == secondState.zombies.sorted { $0.id < $1.id })
        #expect(firstEvents == secondEvents)
    }
}

private func projectileState(
    zombies: [GameZombieState],
    projectiles: [GameProjectileState] = [
        GameProjectileState(
            id: "projectile-1",
            ownerID: "player-1",
            position: .zero,
            angle: 0,
            weapon: .rifle,
            damage: 10,
            spawnedTick: 0
        )
    ]
) -> GameState {
    GameState(
        seed: 1,
        tick: 1,
        players: [],
        zombies: zombies,
        chests: [],
        powerUps: [],
        projectiles: projectiles,
        score: 0,
        isGameOver: false
    )
}
