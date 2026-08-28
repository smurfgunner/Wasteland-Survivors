import SpriteKit

final class GameEffectsRenderer {
    private let randomSource: RandomSource

    init(randomSource: RandomSource = SystemRandomSource()) {
        self.randomSource = randomSource
    }

    func renderZombieHit(at position: CGPoint, in world: SKNode) {
        let hitEffect = SKShapeNode(circleOfRadius: 8)
        hitEffect.fillColor = .systemRed
        hitEffect.strokeColor = .white
        hitEffect.position = position
        hitEffect.zPosition = 16
        world.addChild(hitEffect)
        hitEffect.run(.sequence([
            .scale(to: 1.5, duration: 0.08),
            .fadeOut(withDuration: 0.05),
            .removeFromParent()
        ]))
    }

    func renderEnemyDefeat(at position: CGPoint, in world: SKNode) {
        let floatText = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        floatText.text = "+1 PURGE"
        floatText.fontSize = 12
        floatText.fontColor = .systemYellow
        floatText.position = position
        floatText.zPosition = 20
        world.addChild(floatText)
        floatText.run(.sequence([
            .group([
                .moveBy(x: 0, y: 25, duration: 0.5),
                .fadeOut(withDuration: 0.5)
            ]),
            .removeFromParent()
        ]))
    }

    func renderPlayerDamage(in camera: SKCameraNode, sceneSize: CGSize) {
        let flash = SKShapeNode(
            rectOf: CGSize(width: sceneSize.width * 2, height: sceneSize.height * 2)
        )
        flash.fillColor = SKColor(red: 1.0, green: 0, blue: 0, alpha: 0.25)
        flash.strokeColor = .clear
        camera.addChild(flash)
        flash.run(.sequence([
            .fadeOut(withDuration: 0.15),
            .removeFromParent()
        ]))
    }

    func renderChestReward(
        weapon: WeaponType,
        at position: CGPoint,
        in world: SKNode
    ) {
        for _ in 0..<12 {
            let spark = SKShapeNode(circleOfRadius: randomSource.nextCGFloat(in: 2...5))
            spark.fillColor = weapon.color
            spark.strokeColor = .white
            spark.position = position
            spark.zPosition = 15
            world.addChild(spark)

            let angle = randomSource.nextCGFloat(in: 0...(2 * CGFloat.pi))
            let distance = randomSource.nextCGFloat(in: 20...60)
            let destination = CGPoint(
                x: position.x + cos(angle) * distance,
                y: position.y + sin(angle) * distance
            )

            spark.run(.sequence([
                .group([
                    .move(to: destination, duration: 0.4),
                    .fadeOut(withDuration: 0.4)
                ]),
                .removeFromParent()
            ]))
        }
    }

    func renderMuzzleFlash(
        weapon: WeaponType,
        at position: CGPoint,
        angle: CGFloat,
        in world: SKNode
    ) {
        let flash = SKShapeNode(circleOfRadius: 6)
        flash.fillColor = weapon.color
        flash.strokeColor = .white
        flash.position = CGPoint(
            x: position.x + cos(angle) * 22,
            y: position.y + sin(angle) * 22
        )
        flash.zPosition = 15
        world.addChild(flash)
        flash.run(.sequence([
            .fadeOut(withDuration: 0.06),
            .removeFromParent()
        ]))
    }
}
