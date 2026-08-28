import Foundation
import SpriteKit
import Testing
@testable import Wasteland_Survivors

private final class VisualRegressionBundleMarker: NSObject {}

private struct VisualRegressionBaselineManifest: Decodable {
    let nodeCount: Int
    let structuralFingerprint: String
}

@Suite(.serialized)
struct VisualSceneTests {
    @Test("Every powerup has a distinct visual identity")
    func everyPowerUpHasDistinctVisualIdentity() {
        // Given one visual node for every supported powerup.
        let powerUpNodes = PowerUpType.allCases.map(PowerUpNode.init)

        // When each node is reduced to its visible glow color and symbol rotation.
        let visualSignatures = powerUpNodes.map { node in
            let shapeNodes = node.children.compactMap { $0 as? SKShapeNode }
            let glowSignature = shapeNodes.first?.fillColor.description ?? ""
            let symbolSignature = shapeNodes.dropFirst().first?.zRotation ?? 0
            return "\(glowSignature)|\(symbolSignature)"
        }

        // Then no two powerups share the same visual identity.
        #expect(Set(visualSignatures).count == PowerUpType.allCases.count)
    }

    @Test("A seeded visual scenario builds the same world twice")
    func seededVisualScenarioBuildsTheSameWorldTwice() throws {
        // Given a fixed viewport and identical replay seeds.
        let size = CGSize(width: 800, height: 600)
        let firstScene = GameScene.newGameScene(size: size, randomSource: SeededRandomSource(seed: 42))
        let secondScene = GameScene.newGameScene(size: size, randomSource: SeededRandomSource(seed: 42))
        let view = SKView(frame: CGRect(origin: .zero, size: size))

        // When both scenes are initialized.
        firstScene.didMove(to: view)
        secondScene.didMove(to: view)

        // Then their visual world geometry is identical.
        let firstSnapshot = VisualSceneSnapshot.capture(from: firstScene)
        let secondSnapshot = VisualSceneSnapshot.capture(from: secondScene)

        let baselineURL = try #require(
            Bundle(for: VisualRegressionBundleMarker.self).url(
                forResource: "initial-world.manifest",
                withExtension: "json"
            )
        )
        let baseline = try JSONDecoder().decode(
            VisualRegressionBaselineManifest.self,
            from: Data(contentsOf: baselineURL)
        )

        #expect(firstSnapshot == secondSnapshot)
        #expect(firstSnapshot.nodes.count == baseline.nodeCount)
        let actualFingerprint = try firstSnapshot.fingerprint()
        #expect(
            String(actualFingerprint) == baseline.structuralFingerprint,
            "Actual structural fingerprint: \(actualFingerprint)"
        )
    }

    @Test("Terrain preserves individual visual elements")
    func terrainPreservesIndividualVisualElements() {
        // Given a seeded initial game scene.
        let scene = makeScene()

        // When the static terrain is inspected.
        let terrainShapeCount = scene.worldNode.children.filter { $0 is SKShapeNode }.count

        // Then rocks and cracks remain individually renderable visual elements.
        #expect(terrainShapeCount > 100)
    }

    @Test("Player uses the expected shape-based visual composition")
    func playerUsesExpectedShapeBasedVisualComposition() {
        // Given a newly created player.
        let player = PlayerNode()

        // When its visual children are inspected.
        let visualChildren = player.children

        // Then the player contains the body, weapon, and vest shape nodes.
        #expect(visualChildren.count == 3)
        #expect(visualChildren.allSatisfy { $0 is SKShapeNode })
    }

    @Test("Zombie uses the expected shape-based visual composition")
    func zombieUsesExpectedShapeBasedVisualComposition() {
        // Given a newly created zombie.
        let zombie = ZombieNode(randomSource: SeededRandomSource(seed: 42))

        // When its visual children are inspected.
        let visualChildren = zombie.children

        // Then the zombie contains a body, two eyes, and a health bar.
        #expect(visualChildren.count == 4)
        #expect(visualChildren.allSatisfy { $0 is SKShapeNode })
    }

    @Test("Chest uses the expected box and latch visuals")
    func chestUsesExpectedBoxAndLatchVisuals() {
        // Given a newly created chest.
        let chest = ChestNode()

        // When its visual children are inspected.
        let visualChildren = chest.children

        // Then the chest contains separate box and latch shape nodes.
        #expect(visualChildren.count == 2)
        #expect(visualChildren.allSatisfy { $0 is SKShapeNode })
    }

    @Test("Projectile uses the expected shape-based visual")
    func projectileUsesExpectedShapeBasedVisual() {
        // Given a projectile fired by the pistol.
        let projectile = ProjectileNode(weapon: .pistol, directionAngle: 0)

        // When its visual children are inspected.
        let visualChildren = projectile.children

        // Then the projectile contains one shape-based projectile visual.
        #expect(visualChildren.count == 1)
        #expect(visualChildren.allSatisfy { $0 is SKShapeNode })
    }

    @Test("Player body remains a shape visual")
    func playerBodyRemainsAShapeVisual() {
        // Given a newly created player.
        let player = PlayerNode()

        // When the first visual child is inspected.
        let body = player.children.first

        // Then the body remains an individually renderable shape.
        #expect(body is SKShapeNode)
    }

    @Test("Zombie body remains a shape visual")
    func zombieBodyRemainsAShapeVisual() {
        // Given a newly created zombie.
        let zombie = ZombieNode(randomSource: SeededRandomSource(seed: 42))

        // When the first visual child is inspected.
        let body = zombie.children.first

        // Then the body remains an individually renderable shape.
        #expect(body is SKShapeNode)
    }

    @Test("Player diagonal movement uses both axes and preserves facing")
    func playerDiagonalMovementUsesBothAxesAndPreservesFacing() {
        // Given a player and a normalized diagonal movement direction.
        let player = PlayerNode()
        let movement = MovePlayerUseCase()

        // When the player moves for a quarter second.
        movement.execute(
            player: player,
            direction: CGVector(dx: 0.6, dy: 0.8),
            deltaTime: 0.25
        )

        // Then both axes use the configured movement speed and facing matches the direction.
        #expect(player.position.x == 27)
        #expect(player.position.y == 36)
        #expect(abs(player.zRotation - atan2(0.8, 0.6)) < 0.0001)
    }

    @Test("Zombie stops at the player contact distance")
    func zombieStopsAtPlayerContactDistance() {
        // Given a zombie already within the non-overlap distance of the player.
        let zombie = ZombieNode(randomSource: FixedRandomSource())
        zombie.position = CGPoint(x: 10, y: 0)

        // When the zombie updates its behavior.
        zombie.updateAI(towards: .zero, dt: 1)

        // Then it rotates toward the player but does not move through the contact distance.
        #expect(zombie.position == CGPoint(x: 10, y: 0))
        #expect(abs(zombie.zRotation - CGFloat.pi) < 0.0001)
    }

    @Test("Enemy behavior ignores zombies outside attack range")
    func enemyBehaviorIgnoresZombiesOutsideAttackRange() {
        // Given a zombie outside the player attack distance.
        let player = PlayerNode()
        let zombie = ZombieNode()
        zombie.position = CGPoint(x: 100, y: 0)
        var damageEvents = 0

        // When enemy behavior updates.
        UpdateEnemyBehaviorUseCase().execute(
            zombies: [zombie],
            playerPosition: player.position,
            deltaTime: 0,
            currentTime: 1,
            onPlayerDamage: { _ in damageEvents += 1 }
        )

        // Then no player damage is produced.
        #expect(damageEvents == 0)
        #expect(zombie.canAttack(currentTime: 1))
    }

    @Test("Player aiming positions the weapon at the expected offset")
    func playerAimingPositionsWeaponAtExpectedOffset() {
        // Given a newly created player.
        let player = PlayerNode()

        // When the player aims upward.
        player.aim(towards: CGFloat.pi / 2)

        // Then the player rotates and the weapon keeps its local offset.
        #expect(abs(player.zRotation - CGFloat.pi / 2) < 0.0001)
        #expect(player.children[1].position == CGPoint(x: 14, y: 0))
    }

    @Test("Player body has the expected dimensions")
    func playerBodyHasExpectedDimensions() throws {
        // Given a newly created player.
        let player = PlayerNode()
        let body = try #require(player.children.first as? SKShapeNode)

        // When the body path dimensions are inspected.
        let bounds = body.path?.boundingBox

        // Then the body remains a 32-point diameter circle.
        #expect(bounds?.width == 32)
        #expect(bounds?.height == 32)
    }

    @Test("Zombie body and health bar have expected dimensions")
    func zombieBodyAndHealthBarHaveExpectedDimensions() throws {
        // Given a newly created zombie.
        let zombie = ZombieNode(randomSource: FixedRandomSource())
        let body = try #require(zombie.children[0] as? SKShapeNode)
        let healthBar = try #require(zombie.children[3] as? SKShapeNode)

        // When the visual path dimensions are inspected.
        let bodyBounds = body.path?.boundingBox
        let healthBarBounds = healthBar.path?.boundingBox

        // Then the body and health bar retain their designed dimensions.
        #expect(bodyBounds?.width == 30)
        #expect(bodyBounds?.height == 30)
        #expect(healthBarBounds?.width == 24)
        #expect(healthBarBounds?.height == 4)
    }

    @Test("Projectile has the expected visual dimensions")
    func projectileHasExpectedVisualDimensions() throws {
        // Given a projectile fired by the pistol.
        let projectile = ProjectileNode(weapon: .pistol, directionAngle: 0)
        let visual = try #require(projectile.children.first as? SKShapeNode)

        // When the projectile path dimensions are inspected.
        let bounds = visual.path?.boundingBox

        // Then the projectile remains a 10 by 3 point visual.
        #expect(bounds?.width == 10)
        #expect(bounds?.height == 3)
    }
    private func makeScene() -> GameScene {
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        return scene
    }

}
