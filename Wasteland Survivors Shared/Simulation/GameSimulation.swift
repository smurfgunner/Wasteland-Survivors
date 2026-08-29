import CoreGraphics
import Foundation

struct GamePlayerState: Codable, Equatable, Sendable {
    let id: String
    var position: CGPointValue
    var rotation: Double
    var health: Double
    var weapon: WeaponType
    var powerUps: [PowerUpType]
}

struct GameZombieState: Codable, Equatable, Sendable {
    let id: String
    var position: CGPointValue
    var rotation: Double
    var health: Double
}

struct GameChestState: Codable, Equatable, Sendable {
    let id: String
    let position: CGPointValue
    var isOpened: Bool
}

struct GamePowerUpState: Codable, Equatable, Sendable {
    let id: String
    let position: CGPointValue
    let type: PowerUpType
}

struct GameProjectileState: Codable, Equatable, Sendable {
    let id: String
    let ownerID: String
    var position: CGPointValue
    let angle: Double
    let weapon: WeaponType
    let damage: Double
    let spawnedTick: UInt64

    init(
        id: String,
        ownerID: String = "",
        position: CGPointValue,
        angle: Double,
        weapon: WeaponType,
        damage: Double,
        spawnedTick: UInt64 = 0
    ) {
        self.id = id
        self.ownerID = ownerID
        self.position = position
        self.angle = angle
        self.weapon = weapon
        self.damage = damage
        self.spawnedTick = spawnedTick
    }
}

struct CGPointValue: Codable, Equatable, Sendable {
    let x: Double
    let y: Double

    static let zero = CGPointValue(x: 0, y: 0)

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ vector: CGVector) {
        self.init(x: Double(vector.dx), y: Double(vector.dy))
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    func adding(x: Double, y: Double) -> Self {
        Self(x: self.x + x, y: self.y + y)
    }

    func distance(to other: Self) -> Double {
        hypot(x - other.x, y - other.y)
    }
}

struct PlayerInput: Codable, Equatable, Sendable {
    let playerID: String
    let sequence: UInt64
    let movement: CGPointValue
    let aimAngle: Double
    let wantsToAttack: Bool
    let wantsToOpenChestID: String?
    let wantsToCollectPowerUpID: String?

    init(
        playerID: String,
        sequence: UInt64,
        movement: CGPointValue,
        aimAngle: Double = 0,
        wantsToAttack: Bool = false,
        wantsToOpenChestID: String? = nil,
        wantsToCollectPowerUpID: String? = nil
    ) {

        self.playerID = playerID
        self.sequence = sequence
        self.movement = movement
        self.aimAngle = aimAngle
        self.wantsToAttack = wantsToAttack
        self.wantsToOpenChestID = wantsToOpenChestID
        self.wantsToCollectPowerUpID = wantsToCollectPowerUpID
    }
}

enum GameplayEvent: Codable, Equatable, Sendable {
    case projectileSpawned(id: String, ownerID: String)
    case meleeAttack(id: String, ownerID: String)
    case zombieDamaged(id: String, amount: Double)
    case zombieKilled(id: String, ownerID: String)
    case chestOpened(id: String, playerID: String, weapon: WeaponType)
    case powerUpCollected(id: String, playerID: String, type: PowerUpType)
    case playerDamaged(id: String, amount: Double)
    case playerEliminated(id: String)
    case matchEnded

    var id: String {
        switch self {
        case let .projectileSpawned(id, _), let .meleeAttack(id, _),
             let .zombieDamaged(id, _), let .zombieKilled(id, _),
             let .chestOpened(id, _, _), let .powerUpCollected(id, _, _),
             let .playerDamaged(id, _), let .playerEliminated(id):
            return id
        case .matchEnded:
            return "match-ended"
        }
    }
}

struct GameState: Codable, Equatable, Sendable {
    let seed: UInt64
    var tick: UInt64
    var players: [GamePlayerState]
    var zombies: [GameZombieState]
    var chests: [GameChestState]
    var powerUps: [GamePowerUpState]
    var projectiles: [GameProjectileState]
    var score: Int
    var isGameOver: Bool
    var lastAttackTickByPlayer: [String: UInt64]
    var lastDamageTickByPlayer: [String: UInt64]

    init(
        seed: UInt64,
        tick: UInt64,
        players: [GamePlayerState],
        zombies: [GameZombieState],
        chests: [GameChestState],
        powerUps: [GamePowerUpState],
        projectiles: [GameProjectileState],
        score: Int,
        isGameOver: Bool,
        lastAttackTickByPlayer: [String: UInt64] = [:],
        lastDamageTickByPlayer: [String: UInt64] = [:]
    ) {
        self.seed = seed
        self.tick = tick
        self.players = players
        self.zombies = zombies
        self.chests = chests
        self.powerUps = powerUps
        self.projectiles = projectiles
        self.score = score
        self.isGameOver = isGameOver
        self.lastAttackTickByPlayer = lastAttackTickByPlayer
        self.lastDamageTickByPlayer = lastDamageTickByPlayer
    }

    static func initial(seed: UInt64, playerID: String) -> Self {
        Self(
            seed: seed,
            tick: 0,
            players: [GamePlayerState(
                id: playerID,
                position: .zero,
                rotation: 0,
                health: 100,
                weapon: .pistol,
                powerUps: []
            )],
            zombies: [],
            chests: [],
            powerUps: [],
            projectiles: [],
            score: 0,
            isGameOver: false
        )
    }
}

struct SimulationStep: Equatable, Sendable {
    let state: GameState
    let events: [GameplayEvent]
}

struct GameSimulation {
    struct Configuration: Sendable {
        let playerSpeed: Double
        let zombieSpeed: Double
        let tickRate: Double
        let zombieDamage: Double
        let playerDamageCooldownTicks: UInt64 = 60
        let attackRange: Double
        let maxZombies: Int
        let zombieSpawnIntervalTicks: UInt64
        let chestSpawnIntervalTicks: UInt64
        let maxChests: Int
        let projectileSpeed: Double
        let projectileCollisionRadius: Double
        let projectileLifetimeTicks: UInt64
        let playerContactRadius: Double

        var healthRegenerationDelayTicks: UInt64 {
            UInt64((4 * tickRate).rounded())
        }

        var healthRegenerationPerTick: Double {
            10 / tickRate
        }

        func damage(for player: GamePlayerState) -> Double {
            let multiplier = player.powerUps.contains(.damage) ? 1.25 : 1
            return Double(player.weapon.damage) * multiplier
        }

        func attackRange(for player: GamePlayerState) -> Double {
            let multiplier = player.powerUps.contains(.range) ? 1.25 : 1
            return Double(player.weapon.range) * multiplier
        }

        func attackCooldownTicks(for player: GamePlayerState) -> UInt64 {
            let multiplier = player.powerUps.contains(.fireRate) ? 0.75 : 1
            return max(1, UInt64((player.weapon.fireRate * multiplier * tickRate).rounded()))
        }

        static let standard = Self(
            playerSpeed: 180,
            zombieSpeed: 55,
            tickRate: 60,
            zombieDamage: 12,
            attackRange: 160,
            maxZombies: 18,
            zombieSpawnIntervalTicks: 40,
            chestSpawnIntervalTicks: 600,
            maxChests: 3,
            projectileSpeed: 420,
            projectileCollisionRadius: 20,
            projectileLifetimeTicks: 120,
            playerContactRadius: 24
        )
    }

    private let configuration: Configuration

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    func advance(
        _ state: GameState,
        inputs: [PlayerInput],
        tick: UInt64
    ) -> SimulationStep {
        guard !state.isGameOver else {
            return SimulationStep(state: state, events: [])
        }

        var next = state
        next.tick = tick
        for index in next.players.indices {
            next.players[index].powerUps = Array(
                Set(next.players[index].powerUps)
            ).sorted { $0.rawValue < $1.rawValue }
        }
        var events: [GameplayEvent] = []
        let inputByPlayer = Dictionary(
            inputs.filter {
                $0.movement.x.isFinite &&
                $0.movement.y.isFinite &&
                $0.aimAngle.isFinite
            }.map { ($0.playerID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for index in next.players.indices {
            guard let input = inputByPlayer[next.players[index].id] else { continue }
            let length = hypot(input.movement.x, input.movement.y)
            let scale = length > 1 ? 1 / length : 1
            next.players[index].position = next.players[index].position.adding(
                x: input.movement.x * scale * configuration.playerSpeed / configuration.tickRate,
                y: input.movement.y * scale * configuration.playerSpeed / configuration.tickRate
            )
            next.players[index].rotation = input.aimAngle

            InteractionResolutionSystem.resolve(
                input: input,
                playerIndex: index,
                state: &next,
                proximity: 80,
                seed: next.seed,
                events: &events
            )

            let cooldownTicks = configuration.attackCooldownTicks(for: next.players[index])
            let canAttack = next.lastAttackTickByPlayer[next.players[index].id]
                .map { tick >= $0 + cooldownTicks } ?? true
            if input.wantsToAttack, canAttack,
               next.players[index].weapon.category == .melee,
               let zombieIndex = nearestLivingZombie(to: next.players[index].position, in: next.zombies),
               next.players[index].position.distance(to: next.zombies[zombieIndex].position) <= configuration.attackRange(for: next.players[index]) {
                next.lastAttackTickByPlayer[next.players[index].id] = tick
                let eventID = "melee-\(next.tick)-\(next.players[index].id)"
                let damage = configuration.damage(for: next.players[index])
                next.zombies[zombieIndex].health = max(0, next.zombies[zombieIndex].health - damage)
                events.append(.meleeAttack(id: eventID, ownerID: next.players[index].id))
                events.append(.zombieDamaged(id: "damage-\(next.tick)-\(next.zombies[zombieIndex].id)", amount: damage))
                if next.zombies[zombieIndex].health == 0 {
                    next.score += 1
                    events.append(.zombieKilled(id: next.zombies[zombieIndex].id, ownerID: next.players[index].id))
                }
            } else if input.wantsToAttack, canAttack,
                      next.players[index].weapon.category == .ranged {
                let player = next.players[index]
                next.lastAttackTickByPlayer[player.id] = tick
                let projectileID = "projectile-\(tick)-\(player.id)"
                next.projectiles.append(GameProjectileState(
                    id: projectileID,
                    ownerID: player.id,
                    position: player.position,
                    angle: player.rotation,
                    weapon: player.weapon,
                    damage: configuration.damage(for: player),
                    spawnedTick: tick
                ))
                events.append(.projectileSpawned(id: projectileID, ownerID: player.id))
            }
        }

        let crossedZombieSpawnInterval = tick > state.tick &&
            tick / configuration.zombieSpawnIntervalTicks >
            state.tick / configuration.zombieSpawnIntervalTicks
        if crossedZombieSpawnInterval,
           next.zombies.count < configuration.maxZombies,
           let spawnedZombie = NPCSpawnSystem.zombie(
               seed: next.seed,
               tick: tick,
               index: next.zombies.count,
               players: next.players
           ) {
            next.zombies.append(spawnedZombie)
        }

        let crossedChestSpawnInterval = tick > state.tick &&
            tick / configuration.chestSpawnIntervalTicks >
            state.tick / configuration.chestSpawnIntervalTicks
        if crossedChestSpawnInterval,
           next.chests.count < configuration.maxChests,
           let spawnedChest = ChestSpawnSystem.chest(
               seed: next.seed,
               tick: tick,
               index: next.chests.count,
               players: next.players
           ) {
            next.chests.append(spawnedChest)
        }

        ProjectileResolutionSystem.advance(
            state: &next,
            speed: configuration.projectileSpeed,
            tickRate: configuration.tickRate,
            collisionRadius: configuration.projectileCollisionRadius,
            lifetimeTicks: configuration.projectileLifetimeTicks,
            events: &events
        )

        for index in next.zombies.indices {
            guard let target = NPCDecisionSystem.target(
                for: next.zombies[index],
                players: next.players
            ) else { continue }
            next.zombies[index].position = NPCDecisionSystem.nextPosition(
                for: next.zombies[index],
                toward: target,
                speed: configuration.zombieSpeed,
                tickRate: configuration.tickRate
            )
        }

        PlayerDamageSystem.advance(
            state: &next,
            damage: configuration.zombieDamage,
            contactRadius: configuration.playerContactRadius,
            cooldownTicks: configuration.playerDamageCooldownTicks,
            tick: tick,
            events: &events
        )
        regeneratePlayers(in: &next)

        if next.players.allSatisfy({ $0.health <= 0 }) {
            next.isGameOver = true
            events.append(.matchEnded)
        }

        return SimulationStep(state: next, events: events)
    }

    private func regeneratePlayers(in state: inout GameState) {
        for index in state.players.indices {
            let player = state.players[index]
            guard player.health > 0, player.health < 100 else { continue }
            let lastDamageTick = state.lastDamageTickByPlayer[player.id] ?? 0
            guard state.tick >= lastDamageTick + configuration.healthRegenerationDelayTicks else { continue }
            state.players[index].health = min(100, player.health + configuration.healthRegenerationPerTick)
        }
    }

    private func nearestLivingZombie(to position: CGPointValue, in zombies: [GameZombieState]) -> Int? {
        zombies.indices
            .filter { zombies[$0].health > 0 }
            .min {
                let firstDistance = zombies[$0].position.distance(to: position)
                let secondDistance = zombies[$1].position.distance(to: position)
                if firstDistance == secondDistance {
                    return zombies[$0].id < zombies[$1].id
                }
                return firstDistance < secondDistance
            }
    }
}
