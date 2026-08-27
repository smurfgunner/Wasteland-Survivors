//
//  PlayerNode.swift
//  example-game Shared
//

import SpriteKit

final class PlayerNode: SKNode {
    let maxHealth: CGFloat = 100
    private(set) var currentHealth: CGFloat = 100
    private(set) var currentWeapon: WeaponType = .pistol
    
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
        bodySprite.fillColor = SKColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0)
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
        body.contactTestBitMask = PhysicsCategory.zombie | PhysicsCategory.chest
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
        return currentTime - lastFireTime >= currentWeapon.fireRate
    }
    
    func recordFire(currentTime: TimeInterval) {
        lastFireTime = currentTime
    }
    
    func equip(weapon: WeaponType) {
        self.currentWeapon = weapon
        gunSprite.fillColor = weapon.color
    }
    
    func takeDamage(amount: CGFloat) {
        guard amount > 0 else { return }
        
        currentHealth = Swift.max(0, currentHealth - amount)
        regenerationCooldownRemaining = healthRegenerationDelay
        
        bodySprite.fillColor = .systemRed
        bodySprite.run(.sequence([
            .wait(forDuration: 0.1),
            .run { [weak self] in
                self?.bodySprite.fillColor = SKColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0)
            }
        ]))
    }
    
    @discardableResult
    func updateHealth(deltaTime: TimeInterval) -> Bool {
        guard deltaTime > 0, currentHealth > 0, currentHealth < maxHealth else { return false }
        
        regenerationCooldownRemaining = Swift.max(0, regenerationCooldownRemaining - deltaTime)
        guard regenerationCooldownRemaining <= 0.000_001 else { return false }
        regenerationCooldownRemaining = 0
        
        let previousHealth = currentHealth
        currentHealth = Swift.min(maxHealth, currentHealth + healthRegenerationRate * CGFloat(deltaTime))
        return currentHealth != previousHealth
    }
    
    func reset() {
        currentHealth = maxHealth
        regenerationCooldownRemaining = 0
        currentWeapon = .pistol
        equip(weapon: .pistol)
    }
}
