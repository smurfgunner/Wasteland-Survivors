//
//  ChestNode.swift
//  example-game Shared
//

import SpriteKit

final class ChestNode: SKNode {
    static let pulseCycleDuration: TimeInterval = 1.6

    private(set) var isOpened: Bool = false
    
    private let box = SKShapeNode(rectOf: CGSize(width: 28, height: 22), cornerRadius: 4)
    private let latch = SKShapeNode(circleOfRadius: 4)
    
    override init() {
        super.init()
        setupVisuals()
        setupPhysics()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupVisuals() {
        box.fillColor = SKColor(red: 0.72, green: 0.45, blue: 0.20, alpha: 1.0)
        box.strokeColor = .systemYellow
        box.lineWidth = 2
        addChild(box)
        
        latch.fillColor = .systemYellow
        latch.strokeColor = .white
        latch.position = CGPoint(x: 0, y: -2)
        addChild(latch)
        
        box.run(.repeatForever(.sequence([
            .scale(to: 1.08, duration: Self.pulseCycleDuration / 2),
            .scale(to: 1.0, duration: Self.pulseCycleDuration / 2)
        ])), withKey: "chestPulse")
    }
    
    private func setupPhysics() {
        let body = SKPhysicsBody(rectangleOf: CGSize(width: 32, height: 28))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.chest
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.none
        physicsBody = body
    }
    
    func open() {
        guard !isOpened else { return }
        isOpened = true
        physicsBody = nil
        
        run(.sequence([
            .group([
                .scale(to: 1.4, duration: 0.15),
                .fadeOut(withDuration: 0.25)
            ]),
            .removeFromParent()
        ]))
    }
}
