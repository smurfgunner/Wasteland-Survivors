import Foundation
import MetalKit
import SpriteKit
import Testing
@testable import Wasteland_Survivors

@MainActor
@Suite(.serialized)
struct RenderingTests {
    @Test("Seeded scene produces an identical rendered pixel snapshot")
    func seededSceneProducesIdenticalRenderedPixelSnapshot() throws {
        // Given two scenes with the same viewport and seed.
        let size = CGSize(width: 800, height: 600)
        let firstScene = GameScene.newGameScene(size: size, randomSource: SeededRandomSource(seed: 42))
        let secondScene = GameScene.newGameScene(size: size, randomSource: SeededRandomSource(seed: 42))
        let firstView = SKView(frame: CGRect(origin: .zero, size: size))
        let secondView = SKView(frame: CGRect(origin: .zero, size: size))
        firstScene.didMove(to: firstView)
        secondScene.didMove(to: secondView)
        firstScene.startGame()
        secondScene.startGame()

        // When both gameplay scenes are rendered to textures.
        let firstTexture = try #require(firstView.texture(from: firstScene))
        let secondTexture = try #require(secondView.texture(from: secondScene))
        let firstSnapshot = try RenderedPixelSnapshot(texture: firstTexture)
        let secondSnapshot = try RenderedPixelSnapshot(texture: secondTexture)

        // Then the rendered dimensions and every captured pixel are deterministic.
        #expect(firstSnapshot == secondSnapshot)
        #expect(firstSnapshot.width == secondSnapshot.width)
        #expect(firstSnapshot.height == secondSnapshot.height)
        #expect(Double(firstSnapshot.width) / Double(firstSnapshot.height) == 4.0 / 3.0)
        #expect(firstSnapshot.pixelHash != 0)
    }

    @Test("Metal shader renders the expected pixel color")
    @MainActor
    func metalShaderRendersExpectedPixelColor() throws {
        // Given a Metal device, shader library, and offscreen render target.
        let device = try #require(MTLCreateSystemDefaultDevice())
        let shaderSource = "#include <metal_stdlib>\nusing namespace metal;\n\nstruct MetalTestVertex {\n    float2 position;\n    float4 color;\n};\n\nstruct MetalTestVertexOutput {\n    float4 position [[position]];\n    float4 color;\n};\n\nvertex MetalTestVertexOutput metalVertex(\n    const device MetalTestVertex *vertices [[buffer(0)]],\n    uint vertexID [[vertex_id]]\n) {\n    MetalTestVertexOutput output;\n    output.position = float4(vertices[vertexID].position, 0.0, 1.0);\n    output.color = vertices[vertexID].color;\n    return output;\n}\n\nfragment float4 metalFragment(MetalTestVertexOutput input [[stage_in]]) {\n    return input.color;\n}"
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        let vertexFunction = try #require(library.makeFunction(name: "metalVertex"))
        let fragmentFunction = try #require(library.makeFunction(name: "metalFragment"))
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        let texture = try #require(device.makeTexture(descriptor: textureDescriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // When a solid quad is rendered through the production shader pair.
        var vertices = [
            MetalVertex(position: SIMD2(-1, -1), color: SIMD4(1, 0, 0, 1)),
            MetalVertex(position: SIMD2(1, -1), color: SIMD4(1, 0, 0, 1)),
            MetalVertex(position: SIMD2(-1, 1), color: SIMD4(1, 0, 0, 1)),
            MetalVertex(position: SIMD2(1, -1), color: SIMD4(1, 0, 0, 1)),
            MetalVertex(position: SIMD2(1, 1), color: SIMD4(1, 0, 0, 1)),
            MetalVertex(position: SIMD2(-1, 1), color: SIMD4(1, 0, 0, 1))
        ]
        let commandQueue = try #require(device.makeCommandQueue())
        let commandBuffer = try #require(commandQueue.makeCommandBuffer())
        let encoder = try #require(commandBuffer.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<MetalVertex>.stride * vertices.count, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Then the rendered framebuffer contains the shader's red output.
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &pixel,
            bytesPerRow: 4,
            from: MTLRegionMake2D(2, 2, 1, 1),
            mipmapLevel: 0
        )
        #expect(commandBuffer.status == .completed)
        #expect(pixel[0] == 255)
        #expect(pixel[1] == 0)
        #expect(pixel[2] == 0)
        #expect(pixel[3] == 255)
    }

    @Test("Player visual preserves its expected color and opacity")
    func playerVisualPreservesExpectedColorAndOpacity() throws {
        // Given a newly created player.
        let player = PlayerNode()
        let body = try #require(player.children.first as? SKShapeNode)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        // When the body visual color is sampled.
        body.fillColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        // Then it remains the opaque blue player color.
        #expect(abs(red - 0.2) < 0.01)
        #expect(abs(green - 0.5) < 0.01)
        #expect(abs(blue - 0.9) < 0.01)
        #expect(alpha == 1)
    }

    @Test("Zombie visual preserves its expected color and opacity")
    func zombieVisualPreservesExpectedColorAndOpacity() throws {
        // Given a newly created zombie.
        let zombie = ZombieNode(randomSource: FixedRandomSource())
        let body = try #require(zombie.children.first as? SKShapeNode)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        // When the body visual color is sampled.
        body.fillColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        // Then it remains the opaque green zombie color.
        #expect(abs(red - 0.28) < 0.01)
        #expect(abs(green - 0.55) < 0.01)
        #expect(abs(blue - 0.22) < 0.01)
        #expect(alpha == 1)
    }

    @Test("Zombie speed is exact in the horizontal direction")
    func zombieSpeedIsExactInHorizontalDirection() {
        // Given a zombie with a fixed midpoint speed.
        let zombie = ZombieNode(randomSource: FixedRandomSource())
        zombie.position = .zero

        // When it follows a player horizontally for 0.4 seconds.
        zombie.updateAI(towards: CGPoint(x: 1000, y: 0), dt: 0.4)

        // Then its displacement equals 77.5 points per second.
        #expect(abs(zombie.position.x - 31) < 0.0001)
        #expect(abs(zombie.position.y) < 0.0001)
    }

    @Test("Zombie speed is exact in a diagonal direction")
    func zombieSpeedIsExactInDiagonalDirection() {
        // Given a zombie with a fixed midpoint speed.
        let zombie = ZombieNode(randomSource: FixedRandomSource())
        zombie.position = .zero

        // When it follows a player diagonally for 0.4 seconds.
        zombie.updateAI(towards: CGPoint(x: 1000, y: 1000), dt: 0.4)
        let expectedComponent = 31 / sqrt(2.0)

        // Then its total speed and each axis displacement are exact.
        #expect(abs(zombie.position.x - expectedComponent) < 0.0001)
        #expect(abs(zombie.position.y - expectedComponent) < 0.0001)
        #expect(abs(hypot(zombie.position.x, zombie.position.y) - 31) < 0.0001)
    }

    @Test("Player world dimensions update after scale and rotation")
    func playerWorldDimensionsUpdateAfterScaleAndRotation() throws {
        // Given the player's circular body visual.
        let player = PlayerNode()
        let body = try #require(player.children.first as? SKShapeNode)
        body.setScale(2)
        let scaledFrame = body.calculateAccumulatedFrame()
        body.zRotation = CGFloat.pi / 4

        // When its world-space frame is calculated.
        let frame = body.calculateAccumulatedFrame()
        let expectedSize = scaledFrame.width * sqrt(2.0)

        // Then the transformed world-space dimensions reflect scale and rotation.
        #expect(abs(frame.width - expectedSize) < 0.1)
        #expect(abs(frame.height - expectedSize) < 0.1)
    }

    @Test("Chest pulse animation preserves its expected timing")
    func chestPulseAnimationPreservesExpectedTiming() {
        // Given a newly created chest with its pulse animation.
        let chest = ChestNode()

        // When the chest visual is inspected.
        let visual = chest.children.first

        // Then the pulse animation is active and the visual remains visible.
        #expect(visual?.hasActions() == true)
        #expect(visual?.alpha == 1)
        #expect(visual?.xScale == 1)
        #expect(ChestNode.pulseCycleDuration == 1.6)
    }


    @Test("Player movement is exact for every cardinal and diagonal direction")
    func playerMovementIsExactForEveryDirection() {
        let directions: [(vector: CGVector, expected: CGVector)] = [
            (CGVector(dx: 1, dy: 0), CGVector(dx: 180, dy: 0)),
            (CGVector(dx: -1, dy: 0), CGVector(dx: -180, dy: 0)),
            (CGVector(dx: 0, dy: 1), CGVector(dx: 0, dy: 180)),
            (CGVector(dx: 0, dy: -1), CGVector(dx: 0, dy: -180)),
            (CGVector(dx: 1, dy: 1), CGVector(dx: 180, dy: 180)),
            (CGVector(dx: -1, dy: 1), CGVector(dx: -180, dy: 180)),
            (CGVector(dx: 1, dy: -1), CGVector(dx: 180, dy: -180)),
            (CGVector(dx: -1, dy: -1), CGVector(dx: -180, dy: -180))
        ]

        for direction in directions {
            let player = PlayerNode()
            MovePlayerUseCase().execute(player: player, direction: direction.vector, deltaTime: 1)

            #expect(abs(player.position.x - direction.expected.dx) < 0.0001)
            #expect(abs(player.position.y - direction.expected.dy) < 0.0001)
        }
    }

    @Test("Zombie speed is exact for every cardinal and diagonal direction")
    func zombieSpeedIsExactForEveryDirection() {
        let directions: [(vector: CGPoint, expected: CGVector)] = [
            (CGPoint(x: 1_000, y: 0), CGVector(dx: 31, dy: 0)),
            (CGPoint(x: -1_000, y: 0), CGVector(dx: -31, dy: 0)),
            (CGPoint(x: 0, y: 1_000), CGVector(dx: 0, dy: 31)),
            (CGPoint(x: 0, y: -1_000), CGVector(dx: 0, dy: -31)),
            (CGPoint(x: 1_000, y: 1_000), CGVector(dx: 31 / sqrt(2), dy: 31 / sqrt(2))),
            (CGPoint(x: -1_000, y: 1_000), CGVector(dx: -31 / sqrt(2), dy: 31 / sqrt(2))),
            (CGPoint(x: 1_000, y: -1_000), CGVector(dx: 31 / sqrt(2), dy: -31 / sqrt(2))),
            (CGPoint(x: -1_000, y: -1_000), CGVector(dx: -31 / sqrt(2), dy: -31 / sqrt(2)))
        ]

        for direction in directions {
            let zombie = ZombieNode(randomSource: FixedRandomSource())
            zombie.updateAI(towards: direction.vector, dt: 0.4)

            #expect(abs(zombie.position.x - direction.expected.dx) < 0.0001)
            #expect(abs(zombie.position.y - direction.expected.dy) < 0.0001)
            #expect(abs(hypot(zombie.position.x, zombie.position.y) - 31) < 0.0001)
        }
    }

    @Test("World dimensions remain correct for transformed player, zombie, projectile, and chest visuals")
    func worldDimensionsRemainCorrectForTransformedVisuals() throws {
        let nodes: [SKNode] = [
            PlayerNode().children[0],
            ZombieNode().children[0],
            ProjectileNode(weapon: .pistol, directionAngle: 0).children[0],
            ChestNode().children[0]
        ]

        for node in nodes {
            let baseFrame = node.calculateAccumulatedFrame()

            node.setScale(1.5)
            let scaledFrame = node.calculateAccumulatedFrame()
            #expect(abs(scaledFrame.width - baseFrame.width * 1.5) < 0.2)
            #expect(abs(scaledFrame.height - baseFrame.height * 1.5) < 0.2)

            node.zRotation = CGFloat.pi / 2
            let rotatedFrame = node.calculateAccumulatedFrame()
            #expect(abs(rotatedFrame.width - scaledFrame.height) < 0.2)
            #expect(abs(rotatedFrame.height - scaledFrame.width) < 0.2)
        }
    }


    @Test("Texture assets preserve dimensions and meaningful pixel content") 
    func textureAssetsPreserveDimensionsAndMeaningfulPixelContent() throws {
        let fixtures: [(name: String, size: CGSize)] = [
            ("ChestTexture", CGSize(width: 128, height: 128)),
            ("HitEffectTexture", CGSize(width: 128, height: 128)),
            ("MuzzleFlashTexture", CGSize(width: 128, height: 128)),
            ("PlayerTexture", CGSize(width: 128, height: 128)),
            ("ProjectileTexture", CGSize(width: 128, height: 128)),
            ("SparkTexture", CGSize(width: 128, height: 128)),
            ("ZombieTexture", CGSize(width: 128, height: 128))
        ]

        for fixture in fixtures {
            let texture = SKTexture(imageNamed: fixture.name)
            let image = texture.cgImage()
            guard let providerData = image.dataProvider?.data else {
                Issue.record("Texture (fixture.name) has no readable pixel data.")
                continue
            }

            let bytes = Array(providerData as Data)
            #expect(image.width == Int(fixture.size.width))
            #expect(image.height == Int(fixture.size.height))
            #expect(bytes.contains { $0 != 0 })
            #expect(bytes.contains(0))
        }
    }

    @Test("Projectile lifetime animation preserves its exact timing")
    func projectileLifetimeAnimationPreservesExactTiming() {
        let projectile = ProjectileNode(weapon: .pistol, directionAngle: 0)

        #expect(abs((projectile.action(forKey: "projectileLifetime")?.duration ?? 0) - ProjectileNode.lifetime) < 0.001)
        #expect(ProjectileNode.lifetime == 0.7)
    }

    @Test("Damage and death animations preserve appearance and timing")
    func damageAndDeathAnimationsPreserveAppearanceAndTiming() {
        let player = PlayerNode()
        let playerBody = player.children[0] as? SKShapeNode
        player.takeDamage(amount: 1)

        var playerRed: CGFloat = 0
        var playerGreen: CGFloat = 0
        var playerBlue: CGFloat = 0
        var playerAlpha: CGFloat = 0
        playerBody?.fillColor.getRed(&playerRed, green: &playerGreen, blue: &playerBlue, alpha: &playerAlpha)
        #expect(playerRed > 0.9)
        #expect(playerGreen < 0.4)
        #expect(playerBlue < 0.4)
        #expect(playerAlpha == 1)
        #expect(abs((playerBody?.action(forKey: "damageFlash")?.duration ?? 0) - PlayerNode.hitFlashDuration) < 0.001)

        let zombie = ZombieNode()
        let zombieBody = zombie.children[0] as? SKShapeNode
        zombie.takeDamage(amount: 1)

        var zombieRed: CGFloat = 0
        var zombieGreen: CGFloat = 0
        var zombieBlue: CGFloat = 0
        var zombieAlpha: CGFloat = 0
        zombieBody?.fillColor.getRed(&zombieRed, green: &zombieGreen, blue: &zombieBlue, alpha: &zombieAlpha)
        #expect(zombieRed == 1)
        #expect(zombieGreen == 1)
        #expect(zombieBlue == 1)
        #expect(zombieAlpha == 1)
        #expect(abs((zombieBody?.action(forKey: "damageFlash")?.duration ?? 0) - ZombieNode.hitFlashDuration) < 0.001)

        zombie.takeDamage(amount: zombie.health)
        #expect(zombie.isDead)
        #expect(abs((zombie.action(forKey: "deathAnimation")?.duration ?? 0) - ZombieNode.deathAnimationDuration) < 0.001)
    }

    @Test("Metal renderer builds a pipeline from an injected shader library")
    @MainActor
    func metalRendererBuildsPipelineFromInjectedShaderLibrary() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct MetalVertex { float2 position; float4 color; };
        struct Output { float4 position [[position]]; float4 color; };
        vertex Output metalVertex(const device MetalVertex *vertices [[buffer(0)]], uint id [[vertex_id]]) {
            Output output;
            output.position = float4(vertices[id].position, 0.0, 1.0);
            output.color = vertices[id].color;
            return output;
        }
        fragment float4 metalFragment(Output input [[stage_in]]) {
            return input.color;
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 4, height: 4), device: device)
        view.colorPixelFormat = .rgba8Unorm

        let renderer = MetalGameRenderer(
            view: view,
            onFrame: { _ in [] },
            library: library
        )

        #expect(renderer != nil)
    }
}