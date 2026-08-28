import SpriteKit

final class PowerUpNode: SKNode {
    let powerUp: PowerUpType

    init(powerUp: PowerUpType) {
        self.powerUp = powerUp
        super.init()

        let glow = SKShapeNode(circleOfRadius: 12)
        glow.fillColor = powerUp == .damage ? .systemRed : .systemPurple
        glow.strokeColor = .white
        glow.lineWidth = 2
        addChild(glow)

        let symbol = SKShapeNode(rectOf: CGSize(width: 4, height: 16), cornerRadius: 2)
        symbol.fillColor = .white
        symbol.strokeColor = .clear
        symbol.zRotation = powerUp == .damage ? 0 : CGFloat.pi / 2
        addChild(symbol)

        let body = SKPhysicsBody(circleOfRadius: 14)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.powerUp
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.none
        physicsBody = body

        run(.repeatForever(.sequence([
            .scale(to: 1.15, duration: 0.5),
            .scale(to: 1.0, duration: 0.5)
        ])), withKey: "powerUpPulse")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
