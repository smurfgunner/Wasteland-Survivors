import SpriteKit
import Testing
@testable import Wasteland_Survivors

struct WastelandSurvivorsIntegrationTests {
    @Test("Weapon definitions expose stable combat behavior")
    func weaponDefinitionsRemainStable() {
        #expect(WeaponType.pistol.category == .ranged)
        #expect(WeaponType.shotgun.damage == 22)
        #expect(WeaponType.rifle.range == 340)
        #expect(WeaponType.sword.category == .melee)
        #expect(WeaponType.spear.fireRate == 0.38)
        #expect(WeaponType.allCases.count == 5)
    }
    
    @Test("Player movement updates position and facing")
    func playerMovementUpdatesPositionAndFacing() {
        let player = PlayerNode()
        let movement = MovePlayerUseCase()
        
        movement.execute(
            player: player,
            direction: CGVector(dx: 1, dy: 0),
            deltaTime: 0.5
        )
        
        #expect(player.position.x == 90)
        #expect(player.position.y == 0)
        #expect(player.zRotation == 0)
    }
    
    @Test("Player firing cooldown is enforced")
    func playerFiringCooldownIsEnforced() {
        let player = PlayerNode()
        
        #expect(player.canFire(currentTime: 1))
        player.recordFire(currentTime: 1)
        
        #expect(!player.canFire(currentTime: 1.34))
        #expect(player.canFire(currentTime: 1.35))
    }
    
    @Test("Zombie movement follows the player")
    func zombieMovementFollowsPlayer() {
        let zombie = ZombieNode()
        
        zombie.updateAI(
            towards: CGPoint(x: 100, y: 0),
            dt: 0.5
        )
        
        #expect(zombie.position.x > 0)
        #expect(zombie.position.y == 0)
        #expect(zombie.zRotation == 0)
    }
    
    @Test("Target selection chooses the nearest living zombie in weapon range")
    func targetSelectionChoosesNearestLivingZombieInRange() {
        let player = PlayerNode()
        let nearZombie = ZombieNode()
        let farZombie = ZombieNode()
        let deadZombie = ZombieNode()
        
        nearZombie.position = CGPoint(x: 100, y: 0)
        farZombie.position = CGPoint(x: 200, y: 0)
        deadZombie.position = CGPoint(x: 50, y: 0)
        deadZombie.takeDamage(amount: deadZombie.health)
        
        let target = SelectCombatTargetUseCase().execute(
            player: player,
            zombies: [farZombie, deadZombie, nearZombie]
        )
        
        #expect(target === nearZombie)
    }
    
    @Test("Melee hit resolution damages only zombies in the attack cone")
    func meleeHitResolutionDamagesOnlyZombiesInAttackCone() {
        let player = PlayerNode()
        let inRange = ZombieNode()
        let outOfRange = ZombieNode()
        let outsideCone = ZombieNode()
        let hitResolution = ResolveMeleeHitsUseCase()
        
        inRange.position = CGPoint(x: 50, y: 0)
        outOfRange.position = CGPoint(x: 200, y: 0)
        outsideCone.position = CGPoint(x: 0, y: 50)
        
        var hitZombies: [ZombieNode] = []
        hitResolution.execute(
            player: player,
            zombies: [inRange, outOfRange, outsideCone],
            weapon: .sword,
            targetAngle: 0,
            onHit: { zombie, _ in hitZombies.append(zombie) }
        )
        
        #expect(hitZombies.count == 1)
        #expect(hitZombies.first === inRange)
    }
    
    @Test("Enemy behavior damages the player only when an attack is ready")
    func enemyBehaviorDamagesPlayerOnlyWhenAttackIsReady() {
        let player = PlayerNode()
        let zombie = ZombieNode()
        zombie.position = CGPoint(x: 25, y: 0)
        
        var damageEvents = 0
        let behavior = UpdateEnemyBehaviorUseCase()
        
        behavior.execute(
            zombies: [zombie],
            playerPosition: player.position,
            deltaTime: 0,
            currentTime: 1,
            onPlayerDamage: { amount in
                #expect(amount == 12)
                damageEvents += 1
            }
        )
        
        behavior.execute(
            zombies: [zombie],
            playerPosition: player.position,
            deltaTime: 0,
            currentTime: 1.1,
            onPlayerDamage: { _ in damageEvents += 1 }
        )
        
        #expect(damageEvents == 1)
        #expect(zombie.canAttack(currentTime: 1.1) == false)
    }
    
    @Test("Player regeneration waits four seconds after the latest damage")
    func playerRegenerationWaitsAfterLatestDamage() {
        let player = PlayerNode()
        
        player.takeDamage(amount: 40)
        #expect(player.currentHealth == 60)
        #expect(!player.updateHealth(deltaTime: 3.9))
        #expect(player.currentHealth == 60)
        #expect(player.updateHealth(deltaTime: 0.1))
        #expect(player.currentHealth == 61)
        
        player.takeDamage(amount: 10)
        #expect(!player.updateHealth(deltaTime: 3.9))
        #expect(player.currentHealth == 51)
        #expect(player.updateHealth(deltaTime: 0.1))
        #expect(player.currentHealth == 52)
    }
    
    @Test("Player regeneration stops at maximum health")
    func playerRegenerationStopsAtMaximumHealth() {
        let player = PlayerNode()
        
        player.takeDamage(amount: 1)
        #expect(player.updateHealth(deltaTime: 5))
        #expect(player.currentHealth == player.maxHealth)
        #expect(!player.updateHealth(deltaTime: 1))
    }
    
    @Test("Zombie damage updates health and death state")
    func zombieDamageUpdatesHealthAndDeathState() {
        let zombie = ZombieNode()
        
        zombie.takeDamage(amount: 30)
        #expect(zombie.health == 30)
        #expect(!zombie.isDead)
        
        zombie.takeDamage(amount: 30)
        #expect(zombie.health == 0)
        #expect(zombie.isDead)
        #expect(zombie.physicsBody == nil)
    }
    
    @Test("Projectile uses the selected weapon and physics category")
    func projectileUsesSelectedWeaponAndPhysicsCategory() {
        let projectile = ProjectileNode(weapon: .rifle, directionAngle: 0)
        
        #expect(projectile.weapon == .rifle)
        #expect(projectile.physicsBody?.categoryBitMask == PhysicsCategory.projectile)
        #expect(projectile.physicsBody?.contactTestBitMask == PhysicsCategory.zombie)
        #expect(projectile.physicsBody?.velocity.dx == 600)
        #expect(projectile.physicsBody?.velocity.dy == 0)
    }
    
    @Test("Opening a chest consumes its physics body")
    func openingAChestConsumesItsPhysicsBody() {
        let chest = ChestNode()
        #expect(chest.physicsBody != nil)
        #expect(!chest.isOpened)
        
        chest.open()
        
        #expect(chest.isOpened)
        #expect(chest.physicsBody == nil)
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
    
    @Test("Ranged combat creates a real projectile and muzzle effect")
    func rangedCombatCreatesProjectileAndMuzzleEffect() {
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
            currentTime: 1,
            onDamageZombie: { zombie, damage in zombie.takeDamage(amount: damage) }
        )
        
        #expect(world.children.contains { $0 is ProjectileNode })
        #expect(world.children.count == 4)
        #expect(player.zRotation == 0)
        #expect(player.canFire(currentTime: 1.1) == false)
    }
    
    @Test("Melee combat creates a slash and applies weapon damage")
    func meleeCombatCreatesSlashAndAppliesWeaponDamage() {
        let player = PlayerNode()
        let zombie = ZombieNode()
        let world = SKNode()
        let combat = CombatSystem()
        
        player.equip(weapon: .sword)
        zombie.position = CGPoint(x: 50, y: 0)
        world.addChild(player)
        world.addChild(zombie)
        
        combat.updateAutoCombat(
            player: player,
            zombies: [zombie],
            world: world,
            currentTime: 1,
            onDamageZombie: { zombie, damage in zombie.takeDamage(amount: damage) }
        )
        
        #expect(zombie.health == 0)
        #expect(zombie.isDead)
        #expect(world.children.contains { $0 is MeleeSlashNode })
    }
    
    @Test("Weapon rewards never return the currently equipped weapon")
    func weaponRewardsNeverReturnCurrentWeapon() {
        let rewardSelector = SelectWeaponRewardUseCase()
        
        for currentWeapon in WeaponType.allCases {
            for _ in 0..<20 {
                let reward = rewardSelector.execute(excluding: currentWeapon)
                #expect(reward != currentWeapon)
            }
        }
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
    
    @Test("Game loop spawns a zombie after the spawn interval")
    func gameLoopSpawnsZombieAfterSpawnInterval() {
        let scene = makeScene()
        
        scene.update(1)
        scene.update(3.1)
        
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
        let scene = makeScene()
        scene.update(1)
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
