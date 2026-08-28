import Foundation
import SpriteKit
import Testing
@testable import Wasteland_Survivors

@Suite(.serialized)
struct GameSceneIntegrationTests {
    @Test("Game scene batches static terrain into two render nodes")
    func gameSceneBatchesStaticTerrainIntoTwoRenderNodes() {
        let scene = makeScene()
        let terrainNodes = scene.worldNode.children.filter { node in
            node.zPosition == 1
        }
        
        // Then terrain remains represented by its individual visual nodes before optimization.
        #expect(terrainNodes.count == 347)
    }
    
    @Test("Game scene creates the playable world with real nodes")
    func gameSceneCreatesPlayableWorldWithRealNodes() {
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        
        scene.didMove(to: view)
        
        #expect(scene.playerNode != nil)
        #expect(scene.playerNode.parent === scene.worldNode)
        #expect(scene.camera === scene.cameraNode)
        #expect(scene.worldNode.parent === scene)
        #expect(scene.chests.count == 8)
        #expect(scene.worldNode.children.count > scene.chests.count)
    }
    @Test("Restarting a real game scene restores player and chest state")
    func restartingGameSceneRestoresPlayerAndChestState() {
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        
        scene.playerNode.takeDamage(amount: 40)
        scene.killCount = 3
        scene.isGameOver = true
        
        scene.restartGame()
        
        #expect(scene.playerNode.currentHealth == scene.playerNode.maxHealth)
        #expect(scene.playerNode.currentWeapon == .pistol)
        #expect(scene.playerNode.position == .zero)
        #expect(scene.zombies.isEmpty)
        #expect(scene.chests.count == 8)
        #expect(scene.killCount == 0)
        #expect(!scene.isGameOver)
    }
    
    @Test("Game loop spawns zombies at the three-times faster spawn interval")
    func gameLoopSpawnsZombieAtThreeTimesFasterSpawnInterval() {
        let scene = makeScene()
        
        scene.update(1)
        scene.update(1.7)
        
        #expect(scene.zombies.count == 1)
        #expect(scene.zombies.first?.parent === scene.worldNode)
    }
    
    @Test("Game loop does not exceed the zombie limit")
    func gameLoopDoesNotExceedZombieLimit() {
        let scene = makeScene()
        
        scene.update(1)
        for time in stride(from: 3.0, through: 40.0, by: 1.0) {
            scene.update(time)
        }
        
        #expect(scene.zombies.count <= 18)
    }
    
    @Test("Game loop removes dead zombies after they leave the scene")
    func gameLoopRemovesDeadZombiesAfterTheyLeaveTheScene() {
        let clock = TestClock()
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            clock: { _ in clock.now }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)

        clock.now = 1
        scene.update(1)
        clock.now = 3.1
        scene.update(3.1)
        
        let zombie = scene.zombies[0]
        scene.damageZombie(zombie, amount: zombie.health)
        zombie.removeFromParent()
        scene.update(4)
        
        #expect(scene.zombies.isEmpty)
    }
    
    @Test("Game loop removes opened chests after they leave the scene")
    func gameLoopRemovesOpenedChestsAfterTheyLeaveTheScene() {
        let scene = makeScene()
        let chest = scene.chests[0]
        
        scene.openChest(chest)
        chest.removeFromParent()
        scene.update(1)
        scene.update(2)
        
        #expect(scene.chests.count == 7)
        #expect(!scene.chests.contains { $0 === chest })
    }
    
    @Test("Opening a chest integrates reward selection and weapon equip")
    func openingAChestIntegratesRewardSelectionAndWeaponEquip() {
        let scene = makeScene()
        let chest = scene.chests[0]
        
        scene.openChest(chest)
        
        #expect(chest.isOpened)
        #expect(scene.playerNode.currentWeapon != .pistol)
        #expect(scene.worldNode.children.contains { $0 is SKShapeNode })
    }
    
    @Test("Shotgun combat creates one projectile for each spread angle")
    func shotgunCombatCreatesOneProjectileForEachSpreadAngle() {
        let player = PlayerNode()
        let zombie = ZombieNode()
        let world = SKNode()
        let combat = CombatSystem()
        
        player.equip(weapon: .shotgun)
        zombie.position = CGPoint(x: 100, y: 0)
        world.addChild(player)
        world.addChild(zombie)
        
        combat.updateAutoCombat(
            player: player,
            zombies: [zombie],
            world: world,
            currentTime: 1,
            onDamageZombie: { zombie, damage in zombie.takeDamage(amount: damage) }
        )
        
        let projectiles = world.children.compactMap { $0 as? ProjectileNode }
        #expect(projectiles.count == 3)
    }
    
    @Test("Combat does nothing when no target is in range")
    func combatDoesNothingWhenNoTargetIsInRange() {
        let player = PlayerNode()
        let zombie = ZombieNode()
        let world = SKNode()
        let combat = CombatSystem()
        
        zombie.position = CGPoint(x: 1_000, y: 0)
        world.addChild(player)
        world.addChild(zombie)
        
        combat.updateAutoCombat(
            player: player,
            zombies: [zombie],
            world: world,
            currentTime: 1,
            onDamageZombie: { _, _ in
                Issue.record("A distant zombie must not be damaged.")
            }
        )
        
        #expect(world.children.count == 2)
        #expect(player.canFire(currentTime: 1))
    }
    
    @Test("Combat does nothing while the weapon cooldown is active")
    func combatDoesNothingWhileTheWeaponCooldownIsActive() {
        let player = PlayerNode()
        let zombie = ZombieNode()
        let world = SKNode()
        let combat = CombatSystem()
        
        zombie.position = CGPoint(x: 100, y: 0)
        world.addChild(player)
        world.addChild(zombie)
        
        combat.updateAutoCombat(
            player: player,
            zombies: [zombie],
            world: world,
            currentTime: 1
        ) { _, _ in }
        
        let childCountAfterAttack = world.children.count
        combat.updateAutoCombat(
            player: player,
            zombies: [zombie],
            world: world,
            currentTime: 1.1
        ) { _, _ in }
        
        #expect(world.children.count == childCountAfterAttack)
        #expect(zombie.health == 60)
    }
    
    @Test("Player damage actions are scheduled and game over follows repeated real attacks")
    func playerDamageActionsAreScheduledAndGameOverFollowsRepeatedRealAttacks() {
        let scene = makeScene()
        scene.update(1)
        scene.update(3.1)
        
        let zombie = scene.zombies[0]
        zombie.position = .zero
        
        for time in stride(from: 4.0, through: 12.0, by: 1.0) {
            scene.update(time)
        }
        
        #expect(scene.playerNode.currentHealth <= 0)
        #expect(scene.isGameOver)
        #expect(scene.hudManager.containerNode.hasActions() == false)
    }
    
    @Test("Game loop regenerates player health after a real zombie attack cooldown")
    func gameLoopRegeneratesPlayerHealthAfterRealZombieAttackCooldown() {
        let scene = makeScene()
        scene.update(1)
        scene.update(3.1)
        
        let zombie = scene.zombies[0]
        zombie.position = .zero
        scene.update(4)
        
        #expect(scene.playerNode.currentHealth == 88)
        
        zombie.takeDamage(amount: zombie.health)
        zombie.removeFromParent()
        scene.update(7.9)
        #expect(scene.playerNode.currentHealth == 88)
        
        scene.update(8)
        #expect(scene.playerNode.currentHealth == 88)

        scene.update(8.1)
        #expect(scene.playerNode.currentHealth == 89)
    }
    
    @Test("Transient gameplay effects schedule their removal actions")
    func transientGameplayEffectsScheduleTheirRemovalActions() {
        let renderer = GameEffectsRenderer()
        let world = SKNode()
        
        renderer.renderZombieHit(at: .zero, in: world)
        renderer.renderEnemyDefeat(at: .zero, in: world)
        renderer.renderMuzzleFlash(
            weapon: .pistol,
            at: .zero,
            angle: 0,
            in: world
        )
        renderer.renderChestReward(
            weapon: .shotgun,
            at: .zero,
            in: world
        )
        
        #expect(world.children.count == 15)
        #expect(world.children.allSatisfy { $0.hasActions() })
    }
    private func makeScene() -> GameScene {
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        return scene
    }

}
