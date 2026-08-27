import SpriteKit

final class MeleeSlashNode: SKNode {
    init(weapon: WeaponType, angle: CGFloat) {
        super.init()
        zRotation = angle

        let path = CGMutablePath()
        let r = weapon.range
        path.move(to: .zero)
        path.addArc(center: .zero, radius: r, startAngle: -0.6, endAngle: 0.6, clockwise: false)
        path.closeSubpath()

        let arc = SKShapeNode(path: path)
        arc.fillColor = weapon.color.withAlphaComponent(0.4)
        arc.strokeColor = .white
        arc.lineWidth = 2
        addChild(arc)

        run(.sequence([
            .group([
                .scale(to: 1.2, duration: 0.15),
                .fadeOut(withDuration: 0.15)
            ]),
            .removeFromParent()
        ]))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
