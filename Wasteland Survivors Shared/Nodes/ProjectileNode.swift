import SpriteKit

final class ProjectileNode: SKNode {
    let weapon: WeaponType
    private let projectileSpeed: CGFloat = 600
    private let lifetime: TimeInterval = 0.7

    init(weapon: WeaponType, directionAngle: CGFloat) {
        self.weapon = weapon
        super.init()

        zRotation = directionAngle

        let shape = SKShapeNode(rectOf: CGSize(width: 10, height: 3), cornerRadius: 1)
        shape.fillColor = weapon.color
        shape.strokeColor = .white
        shape.lineWidth = 1
        addChild(shape)

        let body = SKPhysicsBody(circleOfRadius: 4)
        body.isDynamic = true
        body.categoryBitMask = PhysicsCategory.projectile
        body.contactTestBitMask = PhysicsCategory.zombie
        body.collisionBitMask = PhysicsCategory.none
        body.velocity = CGVector(dx: cos(directionAngle) * projectileSpeed, dy: sin(directionAngle) * projectileSpeed)
        physicsBody = body

        run(.sequence([
            .wait(forDuration: lifetime),
            .removeFromParent()
        ]))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
