//
//  PlayerNode.swift
//  example-game Shared
//

import SpriteKit

final class PlayerNode: SKNode {
    static let hitFlashDuration: TimeInterval = 0.1

    let maxHealth: CGFloat = 100
    private(set) var currentHealth: CGFloat = 100
    private(set) var currentWeapon: WeaponType = .pistol
    private(set) var multiplayerColor: MultiplayerPlayerColor = .blue
    private var appliedPowerUps: Set<PowerUpType> = []

    var appliedPowerUpTypes: [PowerUpType] {
        PowerUpType.allCases.filter { appliedPowerUps.contains($0) }
    }

    var currentWeaponDamage: CGFloat {
        currentWeapon.damage * (appliedPowerUps.contains(.damage) ? 1.25 : 1)
    }

    var currentWeaponRange: CGFloat {
        currentWeapon.range * (appliedPowerUps.contains(.range) ? 1.25 : 1)
    }

    var currentWeaponFireRate: TimeInterval {
        currentWeapon.fireRate * (appliedPowerUps.contains(.fireRate) ? 0.75 : 1)
    }
    
    let healthRegenerationDelay: TimeInterval = 4
    let healthRegenerationRate: CGFloat = 10
    private var regenerationCooldownRemaining: TimeInterval = 0
    private var lastFireTime: TimeInterval = 0
    private let moveSpeed: CGFloat = 180
    
    private let bodySprite = SKShapeNode(circleOfRadius: 16)
    private let gunSprite = SKShapeNode(rectOf: CGSize(width: 14, height: 5), cornerRadius: 1.5)
    
    override init() {
        super.init()
        setupVisuals()
        setupPhysics()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupVisuals() {
        bodySprite.fillColor = multiplayerColor.spriteColor
        bodySprite.strokeColor = .white
        bodySprite.lineWidth = 2
        addChild(bodySprite)
        
        gunSprite.fillColor = .lightGray
        gunSprite.strokeColor = .clear
        gunSprite.position = CGPoint(x: 14, y: 0)
        addChild(gunSprite)
        
        let vest = SKShapeNode(rectOf: CGSize(width: 18, height: 8), cornerRadius: 2)
        vest.fillColor = .darkGray
        vest.strokeColor = .clear
        addChild(vest)
    }
    
    private func setupPhysics() {
        let body = SKPhysicsBody(circleOfRadius: 16)
        body.isDynamic = true
        body.categoryBitMask = PhysicsCategory.player
        body.contactTestBitMask = PhysicsCategory.zombie | PhysicsCategory.chest | PhysicsCategory.powerUp
        body.collisionBitMask = PhysicsCategory.none
        body.allowsRotation = false
        physicsBody = body
    }
    
    func move(in direction: CGVector, dt: TimeInterval) {
        guard direction.dx != 0 || direction.dy != 0 else { return }
        
        let dx = direction.dx * moveSpeed * CGFloat(dt)
        let dy = direction.dy * moveSpeed * CGFloat(dt)
        position = CGPoint(x: position.x + dx, y: position.y + dy)
        
        zRotation = atan2(direction.dy, direction.dx)
    }
    
    func aim(towards angle: CGFloat) {
        zRotation = angle
    }
    
    func canFire(currentTime: TimeInterval) -> Bool {
        return currentTime - lastFireTime >= currentWeaponFireRate
    }
    
    func recordFire(currentTime: TimeInterval) {
        lastFireTime = currentTime
    }
    
    func equip(weapon: WeaponType) {
        self.currentWeapon = weapon
        appliedPowerUps.removeAll()
        gunSprite.fillColor = weapon.color
    }

    func apply(multiplayerColor: MultiplayerPlayerColor) {
        self.multiplayerColor = multiplayerColor
        bodySprite.fillColor = multiplayerColor.spriteColor
    }

    func apply(multiplayerState state: MultiplayerPlayerState) {
        currentHealth = CGFloat(state.health)
        currentWeapon = state.weapon
        appliedPowerUps = Set(state.powerUps)
        zRotation = state.rotationAngle
        apply(multiplayerColor: state.color)
        gunSprite.fillColor = currentWeapon.color
    }

    func apply(multiplayerHealth health: CGFloat) {
        let synchronizedHealth = max(0, min(maxHealth, health))
        if synchronizedHealth < currentHealth {
            regenerationCooldownRemaining = healthRegenerationDelay
        }
        currentHealth = synchronizedHealth
    }

    @discardableResult
    func apply(powerUp: PowerUpType) -> Bool {
        guard appliedPowerUps.insert(powerUp).inserted else { return false }
        return true
    }
    
    func takeDamage(amount: CGFloat) {
        guard amount > 0 else { return }
        
        currentHealth = Swift.max(0, currentHealth - amount)
        regenerationCooldownRemaining = healthRegenerationDelay
        
        bodySprite.fillColor = .systemRed
        bodySprite.run(.sequence([
            .wait(forDuration: Self.hitFlashDuration),
            .run { [weak self] in
                self?.bodySprite.fillColor = self?.multiplayerColor.spriteColor ?? MultiplayerPlayerColor.blue.spriteColor
            }
        ]), withKey: "damageFlash")
    }
    
    @discardableResult
    func updateHealth(deltaTime: TimeInterval) -> Bool {
        guard deltaTime > 0, currentHealth > 0, currentHealth < maxHealth else { return false }
        
        let regenerationTime: TimeInterval
        if regenerationCooldownRemaining > deltaTime {
            regenerationCooldownRemaining -= deltaTime
            return false
        }

        regenerationTime = deltaTime - regenerationCooldownRemaining
        regenerationCooldownRemaining = 0
        
        let previousHealth = currentHealth
        currentHealth = Swift.min(
            maxHealth,
            currentHealth + healthRegenerationRate * CGFloat(regenerationTime)
        )
        return currentHealth != previousHealth
    }
    
    func reset() {
        currentHealth = maxHealth
        regenerationCooldownRemaining = 0
        currentWeapon = .pistol
        multiplayerColor = .blue
        bodySprite.fillColor = multiplayerColor.spriteColor
        appliedPowerUps.removeAll()
        equip(weapon: .pistol)
    }
}
