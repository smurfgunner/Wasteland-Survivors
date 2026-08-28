//
//  GameScene.swift
//  example-game Shared
//
//  Created by Vahid Ghanbarpour on 17/08/2026.
//

import SpriteKit
import GameplayKit
#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class GameScene: SKScene {
    
    // MARK: - Core Nodes & Systems
    let worldNode = SKNode()
    private let terrainNode: SKEffectNode = {
        let node = SKEffectNode()
        node.name = "rasterizedTerrain"
        node.shouldRasterize = true
        return node
    }()
    let cameraNode = SKCameraNode()
    let hudManager = HUDManager()
    let combatSystem = CombatSystem()
    private let movePlayerUseCase = MovePlayerUseCase()
    private let updateEnemyBehaviorUseCase = UpdateEnemyBehaviorUseCase()
    private let randomSource: RandomSource
    private let clock: (TimeInterval) -> TimeInterval
    private let selectWeaponRewardUseCase: SelectWeaponRewardUseCase
    private let selectPowerUpDropUseCase: SelectPowerUpDropUseCase
    private let effectsRenderer: GameEffectsRenderer
    
    private(set) var playerNode: PlayerNode!
    private(set) var zombies: [ZombieNode] = []
    private(set) var chests: [ChestNode] = []
    private(set) var powerUps: [PowerUpNode] = []
    
    // MARK: - State & Controls
    var isGameOver: Bool = false
    var killCount: Int = 0
    var movementVector: CGVector = .zero
    var keysPressed: Set<UInt16> = []
    
    // Joystick state for touch input
    var isJoystickActive: Bool = false
    var joystickTouchOrigin: CGPoint = .zero
    
    // Timers & Balancing
    private var lastUpdateTime: TimeInterval = 0
    private var lastZombieSpawnTime: TimeInterval = 0
    private let initialZombieSpawnInterval: TimeInterval = 2.0 / 3.0
    private let minimumZombieSpawnInterval: TimeInterval = 0.8 / 3.0
    private var zombieSpawnInterval: TimeInterval = 2.0 / 3.0
    private var lastChestSpawnTime: TimeInterval = 0
    private var chestSpawnInterval: TimeInterval = 8.0
    private let maxZombies: Int = 18
    private let maxChests: Int = 8
    
    init(
        size: CGSize,
        randomSource: RandomSource = SystemRandomSource(),
        clock: @escaping (TimeInterval) -> TimeInterval = { $0 }
    ) {
        self.randomSource = randomSource
        self.clock = clock
        selectWeaponRewardUseCase = SelectWeaponRewardUseCase(randomSource: randomSource)
        selectPowerUpDropUseCase = SelectPowerUpDropUseCase(randomSource: randomSource)
        effectsRenderer = GameEffectsRenderer(randomSource: randomSource)
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        let randomSource = SystemRandomSource()
        self.randomSource = randomSource
        self.clock = { $0 }
        selectWeaponRewardUseCase = SelectWeaponRewardUseCase(randomSource: randomSource)
        selectPowerUpDropUseCase = SelectPowerUpDropUseCase(randomSource: randomSource)
        effectsRenderer = GameEffectsRenderer(randomSource: randomSource)
        super.init(coder: aDecoder)
    }

    // Factory method
    static func newGameScene(
        size: CGSize,
        randomSource: RandomSource = SystemRandomSource(),
        clock: @escaping (TimeInterval) -> TimeInterval = { $0 }
    ) -> GameScene {
        let sceneSize = size.width > 0 && size.height > 0 ? size : CGSize(width: 1024, height: 768)
        let scene = GameScene(size: sceneSize, randomSource: randomSource, clock: clock)
        scene.scaleMode = .resizeFill
        return scene
    }
    
    // MARK: - Scene Lifecycle
    override func didMove(to view: SKView) {
        setupWorld()
        setupPhysics()
        setupCameraAndHUD()
        setupPlayer()
        setupWastelandTerrain()
        spawnInitialChests()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard cameraNode.parent != nil else { return }

        hudManager.setup(in: cameraNode, sceneSize: size)
        hudManager.updateHealth(
            current: playerNode?.currentHealth ?? 100,
            max: playerNode?.maxHealth ?? 100,
            sceneWidth: size.width
        )
        if let playerNode {
            hudManager.updateWeapon(
                weapon: playerNode.currentWeapon,
                damage: playerNode.currentWeaponDamage,
                range: playerNode.currentWeaponRange,
                fireRate: playerNode.currentWeaponFireRate
            )
        }
    }
    
    // MARK: - Setup
    private func setupWorld() {
        backgroundColor = SKColor(red: 0.14, green: 0.12, blue: 0.10, alpha: 1.0)
        addChild(worldNode)
    }
    
    private func setupPhysics() {
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
    }
    
    private func setupCameraAndHUD() {
        camera = cameraNode
        addChild(cameraNode)
        hudManager.setup(in: cameraNode, sceneSize: size)
    }
    
    private func setupPlayer() {
        playerNode = PlayerNode()
        playerNode.position = .zero
        playerNode.zPosition = 10
        worldNode.addChild(playerNode)
        hudManager.updateWeapon(weapon: playerNode.currentWeapon)
    }
    
    private func setupWastelandTerrain() {
        // Terrain never changes during gameplay, so render its shape hierarchy once
        // into an effect-node cache instead of tessellating every shape each frame.
        worldNode.addChild(terrainNode)

        let mapRadius: CGFloat = 3000
        let gridStep: CGFloat = 160
        
        for x in stride(from: -mapRadius, through: mapRadius, by: gridStep) {
            for y in stride(from: -mapRadius, through: mapRadius, by: gridStep) {
                let ix = Int(x)
                let iy = Int(y)
                let hash = abs((ix * 73856093) ^ (iy * 19349663))
                let seed = hash % 100
                if seed < 15 {
                    let rock = SKShapeNode(circleOfRadius: randomSource.nextCGFloat(in: 4...12))
                    rock.fillColor = SKColor(red: 0.22, green: 0.19, blue: 0.16, alpha: 1.0)
                    rock.strokeColor = .clear
                    rock.position = CGPoint(x: x + randomSource.nextCGFloat(in: -40...40), y: y + randomSource.nextCGFloat(in: -40...40))
                    rock.zPosition = 1
                    terrainNode.addChild(rock)
                } else if seed < 22 {
                    let crack = SKShapeNode(rectOf: CGSize(width: randomSource.nextCGFloat(in: 20...50), height: randomSource.nextCGFloat(in: 3...6)), cornerRadius: 2)
                    crack.fillColor = SKColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 0.7)
                    crack.strokeColor = .clear
                    crack.zRotation = randomSource.nextCGFloat(in: 0...CGFloat.pi)
                    crack.position = CGPoint(x: x, y: y)
                    crack.zPosition = 1
                    terrainNode.addChild(crack)
                }
            }
        }
    }
    
    private func spawnInitialChests() {
        for _ in 0..<maxChests {
            spawnChest(near: .zero, radius: randomSource.nextCGFloat(in: 250...900))
        }
    }
    
    // MARK: - Spawning System
    private func spawnChest(near origin: CGPoint, radius: CGFloat) {
        let angle = randomSource.nextCGFloat(in: 0...(CGFloat.pi * 2))
        let distance = radius
        let pos = CGPoint(x: origin.x + cos(angle) * distance, y: origin.y + sin(angle) * distance)
        
        let chest = ChestNode()
        chest.position = pos
        chest.zPosition = 5
        worldNode.addChild(chest)
        chests.append(chest)
    }
    
    private func spawnZombieOffscreen() {
        guard zombies.count < maxZombies, !isGameOver else { return }
        
        let angle = randomSource.nextCGFloat(in: 0...(CGFloat.pi * 2))
        let spawnDist: CGFloat = Swift.max(size.width, size.height) * 0.7 + randomSource.nextCGFloat(in: 50...150)
        let pos = CGPoint(
            x: playerNode.position.x + cos(angle) * spawnDist,
            y: playerNode.position.y + sin(angle) * spawnDist
        )
        
        let zombie = ZombieNode(randomSource: randomSource)
        zombie.position = pos
        zombie.zPosition = 8
        worldNode.addChild(zombie)
        zombies.append(zombie)
    }
    
    // MARK: - Game Loop
    override func update(_ currentTime: TimeInterval) {
        let gameTime = clock(currentTime)
        if lastUpdateTime == 0 {
            lastUpdateTime = gameTime
            lastZombieSpawnTime = gameTime
            lastChestSpawnTime = gameTime
            return
        }
        
        let dt = gameTime - lastUpdateTime
        lastUpdateTime = gameTime
        
        guard !isGameOver else { return }
        
        // 1. Player Movement & Camera
        updatePlayerMovement(dt: dt)
        cameraNode.position = playerNode.position
        
        // 2. Health regeneration
        if playerNode.updateHealth(deltaTime: dt) {
            hudManager.updateHealth(current: playerNode.currentHealth, max: playerNode.maxHealth, sceneWidth: size.width)
        }
        
        // 3. Zombies AI
        updateZombies(dt: dt, currentTime: currentTime)
        
        // 4. Auto-Combat
        combatSystem.updateAutoCombat(
            player: playerNode,
            zombies: zombies,
            world: worldNode,
            currentTime: gameTime,
            onDamageZombie: { [weak self] zombie, damage in
                self?.damageZombie(zombie, amount: damage)
            }
        )
        
        // 5. Spawners
        handleSpawning(currentTime: gameTime)
        
        // 6. Cleanup
        zombies.removeAll { $0.isDead && $0.parent == nil }
        chests.removeAll { $0.isOpened && $0.parent == nil }
        powerUps.removeAll { $0.parent == nil }
    }
    
    private func updatePlayerMovement(dt: TimeInterval) {
        var direction = movementVector
        
        #if os(macOS)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if keysPressed.contains(13) || keysPressed.contains(126) { dy += 1 }
        if keysPressed.contains(1)  || keysPressed.contains(125) { dy -= 1 }
        if keysPressed.contains(0)  || keysPressed.contains(123) { dx -= 1 }
        if keysPressed.contains(2)  || keysPressed.contains(124) { dx += 1 }
        
        if dx != 0 || dy != 0 {
            let length = sqrt(dx * dx + dy * dy)
            direction = CGVector(dx: dx / length, dy: dy / length)
        }
        #endif
        
        movePlayerUseCase.execute(player: playerNode, direction: direction, deltaTime: dt)
    }
    
    private func updateZombies(dt: TimeInterval, currentTime: TimeInterval) {
        updateEnemyBehaviorUseCase.execute(
            zombies: zombies,
            playerPosition: playerNode.position,
            deltaTime: dt,
            currentTime: currentTime,
            onPlayerDamage: { [weak self] amount in
                self?.playerTakeDamage(amount: amount)
            }
        )
    }
    
    private func handleSpawning(currentTime: TimeInterval) {
        if currentTime - lastZombieSpawnTime > zombieSpawnInterval {
            lastZombieSpawnTime = currentTime
            spawnZombieOffscreen()
            zombieSpawnInterval = Swift.max(minimumZombieSpawnInterval, zombieSpawnInterval - 0.01)
        }
        
        if currentTime - lastChestSpawnTime > chestSpawnInterval {
            lastChestSpawnTime = currentTime
            if chests.count < maxChests {
                spawnChest(near: playerNode.position, radius: CGFloat.random(in: 400...1100))
            }
        }
    }
    
    // MARK: - Damage Handling
    func damageZombie(_ zombie: ZombieNode, amount: CGFloat) {
        guard !zombie.isDead else { return }
        
        zombie.takeDamage(amount: amount)
        
        effectsRenderer.renderZombieHit(at: zombie.position, in: worldNode)
        
        if zombie.isDead {
            killCount += 1
            hudManager.updateKillCount(killCount)
            effectsRenderer.renderEnemyDefeat(at: zombie.position, in: worldNode)
            spawnPowerUpIfSelected(at: zombie.position)
        }
    }

    private func spawnPowerUpIfSelected(at position: CGPoint) {
        guard let powerUp = selectPowerUpDropUseCase.execute() else { return }

        let node = PowerUpNode(powerUp: powerUp)
        node.position = position
        node.zPosition = 7
        worldNode.addChild(node)
        powerUps.append(node)
    }

    func collectPowerUp(_ powerUp: PowerUpNode) {
        guard playerNode.apply(powerUp: powerUp.powerUp) else { return }

        powerUp.removeFromParent()
        hudManager.updateWeapon(
            weapon: playerNode.currentWeapon,
            damage: playerNode.currentWeaponDamage,
            range: playerNode.currentWeaponRange,
            fireRate: playerNode.currentWeaponFireRate
        )
        hudManager.showNotification(text: "POWERUP: \(powerUp.powerUp.title)")
    }
    
    private func playerTakeDamage(amount: CGFloat) {
        guard !isGameOver else { return }
        
        playerNode.takeDamage(amount: amount)
        hudManager.updateHealth(current: playerNode.currentHealth, max: playerNode.maxHealth, sceneWidth: size.width)
        
        effectsRenderer.renderPlayerDamage(in: cameraNode, sceneSize: size)
        
        if playerNode.currentHealth <= 0 {
            triggerGameOver()
        }
    }
    
    // MARK: - Chest Opening
    func openChest(_ chest: ChestNode) {
        chest.open()
        
        let newWeapon = selectWeaponRewardUseCase.execute(excluding: playerNode.currentWeapon)
        
        playerNode.equip(weapon: newWeapon)
        hudManager.updateWeapon(weapon: newWeapon)
        hudManager.showNotification(text: "ACQUIRED: \(newWeapon.rawValue.uppercased()) [\(newWeapon.category.rawValue)]!")
        effectsRenderer.renderChestReward(
            weapon: newWeapon,
            at: chest.position,
            in: worldNode
        )
    }
    
    // MARK: - Game Lifecycle & Reset
    private func triggerGameOver() {
        isGameOver = true
        hudManager.showGameOver(kills: killCount, sceneSize: size)
    }
    
    func restartGame() {
        hudManager.hideGameOver()
        
        zombies.forEach { $0.removeFromParent() }
        zombies.removeAll()
        chests.forEach { $0.removeFromParent() }
        chests.removeAll()
        powerUps.forEach { $0.removeFromParent() }
        powerUps.removeAll()
        
        playerNode.reset()
        playerNode.position = .zero
        
        killCount = 0
        hudManager.updateKillCount(0)
        hudManager.updateHealth(current: playerNode.currentHealth, max: playerNode.maxHealth, sceneWidth: size.width)
        hudManager.updateWeapon(weapon: playerNode.currentWeapon)
        
        zombieSpawnInterval = initialZombieSpawnInterval
        isGameOver = false
        
        spawnInitialChests()
    }
}

// MARK: - Physics Contacts
extension GameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let maskA = contact.bodyA.categoryBitMask
        let maskB = contact.bodyB.categoryBitMask
        
        if (maskA == PhysicsCategory.projectile && maskB == PhysicsCategory.zombie) ||
           (maskB == PhysicsCategory.projectile && maskA == PhysicsCategory.zombie) {
            
            let projectileBody = maskA == PhysicsCategory.projectile ? contact.bodyA : contact.bodyB
            let zombieBody = maskA == PhysicsCategory.zombie ? contact.bodyA : contact.bodyB
            
            if let projectile = projectileBody.node as? ProjectileNode,
               let zombie = zombieBody.node as? ZombieNode {
                damageZombie(zombie, amount: projectile.weapon.damage)
                projectile.removeFromParent()
            }
        }
        
        if (maskA == PhysicsCategory.player && maskB == PhysicsCategory.chest) ||
           (maskB == PhysicsCategory.player && maskA == PhysicsCategory.chest) {
            
            let chestBody = maskA == PhysicsCategory.chest ? contact.bodyA : contact.bodyB
            if let chest = chestBody.node as? ChestNode, !chest.isOpened {
                openChest(chest)
            }
        }

        if (maskA == PhysicsCategory.player && maskB == PhysicsCategory.powerUp) ||
           (maskB == PhysicsCategory.player && maskA == PhysicsCategory.powerUp) {
            let powerUpBody = maskA == PhysicsCategory.powerUp ? contact.bodyA : contact.bodyB
            if let powerUp = powerUpBody.node as? PowerUpNode {
                collectPowerUp(powerUp)
            }
        }
    }
}

// MARK: - Cross-Platform Input Handling
#if os(iOS) || os(tvOS)
extension GameScene {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isGameOver {
            restartGame()
            return
        }
        
        guard let touch = touches.first else { return }
        let location = touch.location(in: hudManager.containerNode)
        
        isJoystickActive = true
        joystickTouchOrigin = location
        hudManager.showJoystick(at: location)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isJoystickActive, let touch = touches.first else { return }
        let location = touch.location(in: hudManager.containerNode)
        
        let dx = location.x - joystickTouchOrigin.x
        let dy = location.y - joystickTouchOrigin.y
        let distance = hypot(dx, dy)
        let maxRadius: CGFloat = 45
        
        if distance > 0 {
            let clampedDist = Swift.min(distance, maxRadius)
            let angle = atan2(dy, dx)
            
            let knobPos = CGPoint(
                x: joystickTouchOrigin.x + cos(angle) * clampedDist,
                y: joystickTouchOrigin.y + sin(angle) * clampedDist
            )
            hudManager.updateJoystickKnob(position: knobPos)
            
            let normalized = clampedDist / maxRadius
            movementVector = CGVector(dx: cos(angle) * normalized, dy: sin(angle) * normalized)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isJoystickActive = false
        movementVector = .zero
        hudManager.hideJoystick()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
    
    #if os(tvOS)
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if isGameOver {
            restartGame()
            return
        }
        
        for press in presses {
            switch press.type {
            case .upArrow:
                movementVector = CGVector(dx: 0, dy: 1)
            case .downArrow:
                movementVector = CGVector(dx: 0, dy: -1)
            case .leftArrow:
                movementVector = CGVector(dx: -1, dy: 0)
            case .rightArrow:
                movementVector = CGVector(dx: 1, dy: 0)
            default:
                break
            }
        }
    }
    
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        movementVector = .zero
    }
    #endif
}
#endif

#if os(macOS)
extension GameScene {
    override func keyDown(with event: NSEvent) {
        if isGameOver {
            restartGame()
            return
        }
        keysPressed.insert(event.keyCode)
    }
    
    override func keyUp(with event: NSEvent) {
        keysPressed.remove(event.keyCode)
    }
}
#endif
