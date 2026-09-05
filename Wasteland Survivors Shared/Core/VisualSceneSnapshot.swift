import SpriteKit

struct VisualSceneSnapshot: Codable, Equatable {
    let sceneSize: VisualSizeSnapshot
    let nodes: [VisualNodeSnapshot]

    static func capture(from scene: SKScene) -> VisualSceneSnapshot {
        VisualSceneSnapshot(
            sceneSize: VisualSizeSnapshot(scene.size),
            nodes: VisualNodeSnapshot.captureTree(from: scene)
        )
    }

    func fingerprint() throws -> UInt64 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encodedSnapshot = try encoder.encode(self)
        return encodedSnapshot.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

struct VisualNodeSnapshot: Codable, Equatable {
    let identifier: String
    let type: String
    let parentIdentifier: String?
    let position: VisualPointSnapshot
    let accumulatedFrame: VisualRectSnapshot
    let scale: VisualPointSnapshot
    let rotation: Double
    let alpha: Double
    let zPosition: Double
    let isHidden: Bool
    let text: String?
    let physics: VisualPhysicsSnapshot?

    static func captureTree(from root: SKNode) -> [VisualNodeSnapshot] {
        capture(node: root, identifier: "root", parentIdentifier: nil)
    }

    private static func capture(
        node: SKNode,
        identifier: String,
        parentIdentifier: String?
    ) -> [VisualNodeSnapshot] {
        let current = VisualNodeSnapshot(
            identifier: identifier,
            type: String(describing: Swift.type(of: node)),
            parentIdentifier: parentIdentifier,
            position: VisualPointSnapshot(node.position),
            accumulatedFrame: VisualRectSnapshot(node.calculateAccumulatedFrame()),
            scale: VisualPointSnapshot(x: node.xScale, y: node.yScale),
            rotation: Double(node.zRotation),
            alpha: Double(node.alpha),
            zPosition: Double(node.zPosition),
            isHidden: node.isHidden,
            text: (node as? SKLabelNode)?.text,
            physics: node.physicsBody.map(VisualPhysicsSnapshot.init)
        )

        return node.children.enumerated().reduce(into: [current]) { snapshots, child in
            snapshots += capture(
                node: child.element,
                identifier: "\(identifier).\(child.offset)",
                parentIdentifier: identifier
            )
        }
    }
}

struct VisualPointSnapshot: Codable, Equatable {
    let x: Double
    let y: Double

    init(_ point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }

    init(x: CGFloat, y: CGFloat) {
        self.x = Double(x)
        self.y = Double(y)
    }
}

struct VisualSizeSnapshot: Codable, Equatable {
    let width: Double
    let height: Double

    init(_ size: CGSize) {
        width = Double(size.width)
        height = Double(size.height)
    }
}

struct VisualRectSnapshot: Codable, Equatable {
    let origin: VisualPointSnapshot
    let size: VisualSizeSnapshot

    init(_ rect: CGRect) {
        origin = VisualPointSnapshot(rect.origin)
        size = VisualSizeSnapshot(rect.size)
    }
}

struct VisualPhysicsSnapshot: Codable, Equatable {
    let categoryBitMask: UInt32
    let contactTestBitMask: UInt32
    let collisionBitMask: UInt32
    let isDynamic: Bool

    init(_ body: SKPhysicsBody) {
        categoryBitMask = body.categoryBitMask
        contactTestBitMask = body.contactTestBitMask
        collisionBitMask = body.collisionBitMask
        isDynamic = body.isDynamic
    }
}
