import Foundation
import SpriteKit
import Testing
@testable import Wasteland_Survivors

@MainActor
@Suite(.serialized)
struct GameplayTests {
    @Test("A zombie drops a random powerup one time in ten")
    func zombieDropChanceIsOneInTen() {
        let dropSelector = SelectPowerUpDropUseCase(randomSource: FixedRandomSource())

        #expect(dropSelector.execute() != nil)
        #expect(SelectPowerUpDropUseCase(randomSource: NoDropRandomSource()).execute() == nil)
    }

    @Test("Each powerup upgrades the equipped weapon only once")
    func powerupUpgradesWeaponOnlyOncePerType() {
        let player = PlayerNode()

        #expect(player.currentWeaponDamage == WeaponType.pistol.damage)
        #expect(player.currentWeaponRange == WeaponType.pistol.range)
        #expect(player.currentWeaponFireRate == WeaponType.pistol.fireRate)
        #expect(player.apply(powerUp: .damage))
        #expect(!player.apply(powerUp: .damage))
        #expect(player.currentWeaponDamage == WeaponType.pistol.damage * 1.25)

        #expect(player.apply(powerUp: .range))
        #expect(!player.apply(powerUp: .range))
        #expect(player.currentWeaponRange == WeaponType.pistol.range * 1.25)

        #expect(player.apply(powerUp: .fireRate))
        #expect(!player.apply(powerUp: .fireRate))
        #expect(player.currentWeaponFireRate == WeaponType.pistol.fireRate * 0.75)

        player.equip(weapon: .rifle)
        #expect(player.currentWeaponDamage == WeaponType.rifle.damage)
        #expect(player.currentWeaponRange == WeaponType.rifle.range)
        #expect(player.currentWeaponFireRate == WeaponType.rifle.fireRate)
        player.equip(weapon: .pistol)
        #expect(player.currentWeaponDamage == WeaponType.pistol.damage)
        #expect(player.currentWeaponRange == WeaponType.pistol.range)
        #expect(player.currentWeaponFireRate == WeaponType.pistol.fireRate)
    }

    @Test("Weapon upgrades are used by combat range and damage")
    func weaponUpgradesAreUsedByCombat() {
        let player = PlayerNode()
        let zombie = ZombieNode(randomSource: FixedRandomSource())
        let world = SKNode()
        let combat = CombatSystem()

        player.equip(weapon: .sword)
        #expect(player.apply(powerUp: .damage))
        #expect(player.apply(powerUp: .range))
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

        #expect(zombie.health == 0)
        #expect(zombie.isDead)
    }

    @Test("Killing a zombie creates its selected powerup in the world")
    func killingZombieCreatesPowerupInWorld() {
        let scene = GameScene.newGameScene(
            size: CGSize(width: 800, height: 600),
            randomSource: FixedRandomSource()
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        scene.startGame()
        let zombie = ZombieNode(randomSource: FixedRandomSource())
        zombie.position = CGPoint(x: 100, y: 0)
        scene.worldNode.addChild(zombie)

        scene.damageZombie(zombie, amount: zombie.health)

        #expect(scene.worldNode.children.contains { $0 is PowerUpNode })
    }

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
        player.equip(weapon: .sword)
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
        #expect(!player.updateHealth(deltaTime: 0.1))
        #expect(player.currentHealth == 60)
        #expect(player.updateHealth(deltaTime: 0.1))
        #expect(player.currentHealth == 61)
        
        player.takeDamage(amount: 10)
        #expect(!player.updateHealth(deltaTime: 3.9))
        #expect(player.currentHealth == 51)
        #expect(!player.updateHealth(deltaTime: 0.1))
        #expect(player.currentHealth == 51)
        #expect(player.updateHealth(deltaTime: 0.1))
        #expect(player.currentHealth == 52)
    }
    
    @Test("Player regeneration uses only time after the delay")
    func playerRegenerationUsesOnlyTimeAfterDelay() {
        let player = PlayerNode()

        // Given the player has lost 40 health and regeneration is delayed by four seconds.
        player.takeDamage(amount: 40)

        // When one update crosses the delay by only half a second.
        let didRegenerate = player.updateHealth(deltaTime: 4.5)

        // Then only half a second of regeneration is applied.
        #expect(didRegenerate)
        #expect(player.currentHealth == 65)
    }

    @Test("Player regeneration stops at maximum health")
    func playerRegenerationStopsAtMaximumHealth() {
        let player = PlayerNode()
        
        player.takeDamage(amount: 1)
        #expect(player.updateHealth(deltaTime: 5))
        #expect(player.currentHealth == player.maxHealth)
        #expect(!player.updateHealth(deltaTime: 1))
    }
    
    @Test("Replicated zero zombie health transitions the node to its death state")
    func replicatedZeroZombieHealthTransitionsNodeToDeathState() {
        // Given a live zombie node receiving an authoritative health update.
        let zombie = ZombieNode()
        let world = SKNode()
        world.addChild(zombie)

        // When the authoritative state reports zero health.
        zombie.apply(multiplayerHealth: 0)

        // Then the presentation node is dead and no longer participates in physics.
        #expect(zombie.health == 0)
        #expect(zombie.isDead)
        #expect(zombie.physicsBody == nil)
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
    
    @Test("Zombies do not request unnecessary zombie-to-zombie collision solving")
    func zombiesDoNotRequestZombieToZombieCollisionSolving() {
        let zombie = ZombieNode()
        
        // Then zombies still use their original collision behavior before optimization.
        #expect(zombie.physicsBody?.collisionBitMask == PhysicsCategory.zombie)
        #expect(zombie.physicsBody?.contactTestBitMask == PhysicsCategory.projectile | PhysicsCategory.player)
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
}