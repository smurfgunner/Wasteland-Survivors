//
//  ZombieNode.swift
//  example-game Shared
//

import SpriteKit

final class ZombieNode: SKNode {
    let multiplayerID: String
    static let hitFlashDuration: TimeInterval = 0.06
    static let deathAnimationDuration: TimeInterval = 0.25

    private(set) var health: CGFloat = 60
    private(set) var isDead: Bool = false
    private let moveSpeed: CGFloat
    private let randomSource: RandomSource
    private var lastAttackTime: TimeInterval = 0
    private let attackCooldown: TimeInterval = 0.6
    
    private let bodySprite = SKShapeNode(circleOfRadius: 15)
    private let healthBar = SKShapeNode(rectOf: CGSize(width: 24, height: 4), cornerRadius: 1)
    
    init(randomSource: RandomSource = SystemRandomSource(), multiplayerID: String = UUID().uuidString) {
        self.multiplayerID = multiplayerID
        self.randomSource = randomSource
        moveSpeed = randomSource.nextCGFloat(in: 60...95)
        super.init()
        setupVisuals()
        setupPhysics()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupVisuals() {
        bodySprite.fillColor = SKColor(red: 0.28, green: 0.55, blue: 0.22, alpha: 1.0)
        bodySprite.strokeColor = SKColor(red: 0.15, green: 0.35, blue: 0.10, alpha: 1.0)
        bodySprite.lineWidth = 1.5
        addChild(bodySprite)
        
        let leftEye = SKShapeNode(circleOfRadius: 2.5)
        leftEye.fillColor = .systemRed
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: 8, y: 5)
        addChild(leftEye)
        
        let rightEye = SKShapeNode(circleOfRadius: 2.5)
        rightEye.fillColor = .systemRed
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: 8, y: -5)
        addChild(rightEye)
        
        healthBar.fillColor = .systemGreen
        healthBar.strokeColor = .clear
        healthBar.position = CGPoint(x: 0, y: 22)
        addChild(healthBar)
    }
    
    private func setupPhysics() {
        let body = SKPhysicsBody(circleOfRadius: 15)
        body.isDynamic = true
        body.categoryBitMask = PhysicsCategory.zombie
        body.contactTestBitMask = PhysicsCategory.projectile | PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.zombie
        body.allowsRotation = false
        physicsBody = body
    }
    
    func updateAI(towards playerPos: CGPoint, dt: TimeInterval) {
        guard !isDead else { return }
        
        let dx = playerPos.x - position.x
        let dy = playerPos.y - position.y
        let angle = atan2(dy, dx)
        zRotation = angle
        
        let distance = hypot(dx, dy)
        if distance > 20 {
            let moveX = cos(angle) * moveSpeed * CGFloat(dt)
            let moveY = sin(angle) * moveSpeed * CGFloat(dt)
            position = CGPoint(x: position.x + moveX, y: position.y + moveY)
        }
    }
    
    func canAttack(currentTime: TimeInterval) -> Bool {
        return currentTime - lastAttackTime >= attackCooldown
    }
    
    func recordAttack(currentTime: TimeInterval) {
        lastAttackTime = currentTime
    }
    
    func takeDamage(amount: CGFloat) {
        guard !isDead else { return }
        health = Swift.max(0, health - amount)
        
        let ratio = max(0, health / 60)
        healthBar.xScale = ratio
        
        bodySprite.fillColor = .white
        bodySprite.run(.sequence([
            .wait(forDuration: Self.hitFlashDuration),
            .run { [weak self] in
                self?.bodySprite.fillColor = SKColor(red: 0.28, green: 0.55, blue: 0.22, alpha: 1.0)
            }
        ]), withKey: "damageFlash")
        
        if health <= 0 {
            die()
        }
    }

    func apply(multiplayerHealth: CGFloat) {
        let authoritativeHealth = Swift.max(0, Swift.min(60, multiplayerHealth))
        if authoritativeHealth > 0, isDead {
            revive()
        }

        health = authoritativeHealth
        healthBar.xScale = health / 60
        if health <= 0 {
            die()
        }
    }

    private func revive() {
        isDead = false
        removeAllActions()
        alpha = 1
        setScale(1)
        setupPhysics()
    }
    
    private func die() {
        isDead = true
        physicsBody = nil
        removeAllActions()
        
        run(.sequence([
            .group([
                .scale(to: 0.2, duration: Self.deathAnimationDuration),
                .fadeOut(withDuration: Self.deathAnimationDuration)
            ]),
            .removeFromParent()
        ]), withKey: "deathAnimation")
    }
}
