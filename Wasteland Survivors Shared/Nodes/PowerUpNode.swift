import SpriteKit

final class PowerUpNode: SKNode {
    let powerUp: PowerUpType

    init(powerUp: PowerUpType) {
        self.powerUp = powerUp
        super.init()

        let (glowColor, symbolRotation): (SKColor, CGFloat) = {
            switch powerUp {
            case .damage:
                return (.systemRed, 0)
            case .range:
                return (.systemPurple, CGFloat.pi / 2)
            case .fireRate:
                return (.systemGreen, CGFloat.pi / 4)
            }
        }()

        let glow = SKShapeNode(circleOfRadius: 12)
        glow.fillColor = glowColor
        glow.strokeColor = .white
        glow.lineWidth = 2
        addChild(glow)

        let symbol = SKShapeNode(rectOf: CGSize(width: 4, height: 16), cornerRadius: 2)
        symbol.fillColor = .white
        symbol.strokeColor = .clear
        symbol.zRotation = symbolRotation
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
