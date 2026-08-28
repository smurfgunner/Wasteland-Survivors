import Foundation
import SpriteKit
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Wasteland_Survivors

@MainActor
@Suite(.serialized)
struct GameSceneIntegrationTests {
    @Test("Collecting a damage powerup updates the weapon HUD damage")
    func collectingDamagePowerUpUpdatesWeaponHUDDamage() {
        let scene = makeScene()
        let powerUp = PowerUpNode(powerUp: .damage)

        scene.collectPowerUp(powerUp)

        let weaponBadge = scene.hudManager.containerNode.children
            .compactMap { $0 as? SKLabelNode }
            .first { $0.text?.contains("DMG:") == true }
        #expect(weaponBadge?.text?.contains("DMG: 37") == true)
    }

    @Test("Collecting a range powerup updates the weapon HUD range")
    func collectingRangePowerUpUpdatesWeaponHUDRange() {
        let scene = makeScene()
        let powerUp = PowerUpNode(powerUp: .range)

        scene.collectPowerUp(powerUp)

        let weaponBadge = scene.hudManager.containerNode.children
            .compactMap { $0 as? SKLabelNode }
            .first { $0.text?.contains("RNG:") == true }
        #expect(weaponBadge?.text?.contains("RNG: 350") == true)
    }

    @Test("Collecting a fire rate powerup updates the weapon HUD fire rate")
    func collectingFireRatePowerUpUpdatesWeaponHUDFireRate() {
        let scene = makeScene()
        let powerUp = PowerUpNode(powerUp: .fireRate)

        scene.collectPowerUp(powerUp)

        let weaponBadge = scene.hudManager.containerNode.children
            .compactMap { $0 as? SKLabelNode }
            .first { $0.text?.contains("FIR:") == true }
        #expect(weaponBadge?.text?.contains("FIR: 0.26") == true)
    }

    @Test("Weapon HUD stats fit inside the weapon panel")
    func weaponHUDStatsFitInsideWeaponPanel() {
        // Given a fully initialized game HUD.
        let scene = makeScene()
        let weaponPanel = scene.hudManager.containerNode.children
            .compactMap { $0 as? SKShapeNode }
            .first { $0.name == "weaponPanel" }
        let statsLabel = scene.hudManager.containerNode.children
            .compactMap { $0 as? SKLabelNode }
            .first { $0.text?.contains("DMG:") == true }

        // When the weapon stats are rendered.
        let panelFrame = weaponPanel?.frame ?? .zero
        let statsFrame = statsLabel?.frame ?? .zero

        // Then all stats remain inside the weapon panel.
        #expect(statsFrame.minX >= panelFrame.minX)
        #expect(statsFrame.maxX <= panelFrame.maxX)
    }

    @Test("Every on-screen HUD element stays inside the resized screen")
    func everyOnScreenHUDElementStaysInsideResizedScreen() {
        // Given a HUD created at one size and then resized to a fullscreen-like viewport.
        let scene = makeScene()
        let oldSize = scene.size
        let resizedSize = CGSize(width: 1920, height: 1080)
        scene.size = resizedSize
        scene.didChangeSize(oldSize)
        scene.hudManager.updateHealth(
            current: 25,
            max: scene.playerNode.maxHealth,
            sceneWidth: resizedSize.width
        )

        let screenFrame = CGRect(
            x: -resizedSize.width / 2,
            y: -resizedSize.height / 2,
            width: resizedSize.width,
            height: resizedSize.height
        )
        let hudElements = scene.hudManager.containerNode.children
        let healthBar = hudElements.first { $0.name == "healthBar" }
        let healthFill = hudElements.first { $0.name == "healthBarFill" }

        // Then every persistent HUD element is inside the visible screen.
        #expect(hudElements.count == 9)
        for element in hudElements {
            #expect(screenFrame.contains(element.frame))
        }

        // And the resized health fill remains inside its background.
        #expect(healthBar?.frame.contains(healthFill?.frame ?? .zero) == true)
    }

    @Test("Game scene rasterizes static terrain into one cached render node")
    func gameSceneRasterizesStaticTerrainIntoOneCachedRenderNode() {
        let scene = makeScene()
        let terrainNode = scene.worldNode.children.first { $0.name == "rasterizedTerrain" }
        
        // Then terrain is represented by one cached render node instead of
        // submitting every static shape as a separate world-level render node.
        #expect(scene.worldNode.children.filter { $0.name == "rasterizedTerrain" }.count == 1)
        #expect(terrainNode is SKEffectNode)
        #expect((terrainNode as? SKEffectNode)?.shouldRasterize == true)
    }
    
    @Test("Game scene presents a start and exit menu before gameplay")
    func gameScenePresentsMainMenuBeforeGameplay() {
        // Given a newly presented game scene.
        let scene = makeScene(started: false)

        // Then the menu is visible and gameplay has not started.
        #expect(scene.hasStartedGame == false)
        #expect(scene.cameraNode.childNode(withName: "mainMenu") != nil)
        #expect(scene.cameraNode.childNode(withName: "mainMenu")?.childNode(withName: "startButton") != nil)
        #expect(scene.cameraNode.childNode(withName: "mainMenu")?.childNode(withName: "exitButton") != nil)
    }

    @Test("Starting from the main menu enables gameplay")
    func startingFromMainMenuEnablesGameplay() {
        // Given a newly presented game scene.
        let scene = makeScene(started: false)

        // When the player starts the game.
        scene.startGame()

        // Then the menu is removed and gameplay is enabled.
        #expect(scene.hasStartedGame)
        #expect(scene.cameraNode.childNode(withName: "mainMenu") == nil)
    }

    @Test("Selecting exit from the main menu invokes the host exit handler")
    func selectingExitFromMainMenuInvokesHostExitHandler() {
        // Given a newly presented game scene with a host exit handler.
        let scene = makeScene(started: false)
        var didRequestExit = false
        scene.onExitRequested = { didRequestExit = true }

        // When the exit button is selected.
        scene.handleMenuInput(at: CGPoint(x: 0, y: -80))

        // Then the host is notified.
        #expect(didRequestExit)
    }

    @Test("The main menu highlights its default action")
    func mainMenuHighlightsItsDefaultAction() {
        // Given a newly presented main menu.
        let scene = makeScene(started: false)
        let menu = scene.cameraNode.childNode(withName: "mainMenu")
        let startButton = menu?.childNode(withName: "startButton") as? SKShapeNode

        #if os(macOS)
        let exitButton = menu?.childNode(withName: "exitButton") as? SKShapeNode

        // Then Start Game is visibly highlighted over Exit.
        #expect(startButton?.fillColor != exitButton?.fillColor)
        #else
        // Then the mobile/tv menu contains no unsupported Exit action.
        #expect(menu?.childNode(withName: "exitButton") == nil)
        #expect(startButton != nil)
        #endif
    }

    @Test("Gameplay remains paused until the main menu starts the game")
    func gameplayRemainsPausedUntilMainMenuStartsTheGame() {
        // Given a scene that is still displaying its main menu.
        let scene = makeScene(started: false)

        // When the scene receives update ticks.
        scene.update(1)
        scene.update(1.7)

        // Then no gameplay enemies have spawned.
        #expect(scene.zombies.isEmpty)

        // When Start Game is selected.
        scene.startGame()
        scene.update(2.4)

        // Then the gameplay loop is active.
        #expect(scene.zombies.count == 1)
    }

    #if os(macOS)
    @Test("Escape opens the pause menu and stops gameplay updates")
    func escapeOpensPauseMenuAndStopsGameplayUpdates() throws {
        // Given an active game.
        let scene = makeScene()
        scene.update(1)
        scene.update(1.7)
        let zombieCount = scene.zombies.count

        // When Escape is pressed.
        scene.keyDown(with: try keyEvent(keyCode: 53))
        scene.update(3)

        // Then the pause menu is shown and gameplay is frozen.
        #expect(scene.menuState == .paused)
        #expect(scene.cameraNode.childNode(withName: "pauseMenu") != nil)
        #expect(scene.zombies.count == zombieCount)
    }

    @Test("Resume returns from the pause menu to active gameplay")
    func resumeReturnsFromPauseMenuToActiveGameplay() throws {
        // Given a paused game.
        let scene = makeScene()
        scene.keyDown(with: try keyEvent(keyCode: 53))

        // When Resume Game is selected with Return.
        scene.keyDown(with: try keyEvent(keyCode: 36))

        // Then gameplay is active and the pause menu is gone.
        #expect(scene.menuState == .playing)
        #expect(scene.hasStartedGame)
        #expect(scene.cameraNode.childNode(withName: "pauseMenu") == nil)
    }

    @Test("Exit to Menu returns a paused game to the main menu")
    func exitToMenuReturnsAPausedGameToTheMainMenu() throws {
        // Given a paused game.
        let scene = makeScene()
        scene.keyDown(with: try keyEvent(keyCode: 53))

        // When Exit to Menu is selected.
        scene.keyDown(with: try keyEvent(keyCode: 125))
        scene.keyDown(with: try keyEvent(keyCode: 36))

        // Then the main menu is restored and gameplay is no longer active.
        #expect(scene.menuState == .main)
        #expect(scene.hasStartedGame == false)
        #expect(scene.cameraNode.childNode(withName: "mainMenu") != nil)
        #expect(scene.cameraNode.childNode(withName: "pauseMenu") == nil)
    }
    #endif

    @Test("Game scene creates the playable world with real nodes")
    func gameSceneCreatesPlayableWorldWithRealNodes() {
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        
        scene.didMove(to: view)
        scene.startGame()
        
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
        scene.startGame()
        
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
        scene.startGame()

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
    private func makeScene(started: Bool = true) -> GameScene {
        let scene = GameScene.newGameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scene.didMove(to: view)
        if started {
            scene.startGame()
        }
        return scene
    }

    #if os(macOS)
    private func keyEvent(keyCode: UInt16) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
    #endif

}