//
//  GameScene.swift
//  example-game Shared
//
//  Created by Vahid Ghanbarpour on 17/08/2026.
//

import SpriteKit
import GameplayKit
#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class GameScene: SKScene {
    enum MenuState: Equatable {
        case main
        case playing
        case paused
    }
    
    // MARK: - Core Nodes & Systems
    let worldNode = SKNode()
    private let terrainNode: SKEffectNode = {
        let node = SKEffectNode()
        node.name = "rasterizedTerrain"
        node.shouldRasterize = true
        return node
    }()
    let cameraNode = SKCameraNode()
    let hudManager = HUDManager()
    let combatSystem = CombatSystem()
    private let movePlayerUseCase = MovePlayerUseCase()
    private let updateEnemyBehaviorUseCase = UpdateEnemyBehaviorUseCase()
    private let randomSource: RandomSource
    private let clock: (TimeInterval) -> TimeInterval
    private let selectWeaponRewardUseCase: SelectWeaponRewardUseCase
    private let selectPowerUpDropUseCase: SelectPowerUpDropUseCase
    private let effectsRenderer: GameEffectsRenderer
    private let multiplayerSessionFactory: () -> LocalMultiplayerNetworkSession?
    
    private(set) var playerNode: PlayerNode!
    private(set) var zombies: [ZombieNode] = []
    private(set) var chests: [ChestNode] = []
    private(set) var powerUps: [PowerUpNode] = []
    private(set) var remotePlayers: [String: PlayerNode] = [:]
    private var localMultiplayerSession: LocalMultiplayerNetworkSession?
    private var multiplayerColor: MultiplayerPlayerColor = .blue
    private var lastMultiplayerSyncTime: TimeInterval = 0
    private var hasSpawnedNearHost = false
    private var knownPlayerStates: [String: MultiplayerPlayerState] = [:]
    private var hostID: String?
    private var localSessionStartedAt: TimeInterval = 0
    private var multiplayerTargetPositions: [String: CGPoint] = [:]
    private var initializedMultiplayerTargets: Set<String> = []
    private var multiplayerSnapshotSequence: UInt64 = 0
    private var receivedSnapshotBuffer = MultiplayerSnapshotBuffer()
    private var acceptedHostID: String?
    private var isMultiplayerClient: Bool {
        guard localMultiplayerSession != nil else { return false }
        return hostID != nil && hostID != localMultiplayerSession?.localPlayerID
    }
    
    // MARK: - State & Controls
    var isGameOver: Bool = false
    private(set) var hasStartedGame: Bool = false
    private(set) var menuState: MenuState = .main
    private var selectedMenuButtonName = "startButton"
    var onExitRequested: (() -> Void)?
    var killCount: Int = 0
    var movementVector: CGVector = .zero
    var keysPressed: Set<UInt16> = []
    
    // Joystick state for touch input
    var isJoystickActive: Bool = false
    var joystickTouchOrigin: CGPoint = .zero
    
    // Timers & Balancing
    private var lastUpdateTime: TimeInterval = 0
    private var lastZombieSpawnTime: TimeInterval = 0
    private let initialZombieSpawnInterval: TimeInterval = 2.0 / 3.0
    private let minimumZombieSpawnInterval: TimeInterval = 0.8 / 3.0
    private var zombieSpawnInterval: TimeInterval = 2.0 / 3.0
    private var lastChestSpawnTime: TimeInterval = 0
    private var chestSpawnInterval: TimeInterval = 8.0
    private let maxZombies: Int = 18
    private let maxChests: Int = 8
    
    init(
        size: CGSize,
        randomSource: RandomSource = SystemRandomSource(),
        clock: @escaping (TimeInterval) -> TimeInterval = { $0 },
        multiplayerSessionFactory: @escaping () -> LocalMultiplayerNetworkSession? = {
            #if canImport(MultipeerConnectivity)
            return MultipeerConnectivitySession()
            #else
            return nil
            #endif
        }
    ) {
        self.randomSource = randomSource
        self.clock = clock
        self.multiplayerSessionFactory = multiplayerSessionFactory
        selectWeaponRewardUseCase = SelectWeaponRewardUseCase(randomSource: randomSource)
        selectPowerUpDropUseCase = SelectPowerUpDropUseCase(randomSource: randomSource)
        effectsRenderer = GameEffectsRenderer(randomSource: randomSource)
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        let randomSource = SystemRandomSource()
        self.randomSource = randomSource
        self.clock = { $0 }
        self.multiplayerSessionFactory = {
            #if canImport(MultipeerConnectivity)
            return MultipeerConnectivitySession()
            #else
            return nil
            #endif
        }
        selectWeaponRewardUseCase = SelectWeaponRewardUseCase(randomSource: randomSource)
        selectPowerUpDropUseCase = SelectPowerUpDropUseCase(randomSource: randomSource)
        effectsRenderer = GameEffectsRenderer(randomSource: randomSource)
        super.init(coder: aDecoder)
    }

    // Factory method
    static func newGameScene(
        size: CGSize,
        randomSource: RandomSource = SystemRandomSource(),
        clock: @escaping (TimeInterval) -> TimeInterval = { $0 },
        multiplayerSessionFactory: @escaping () -> LocalMultiplayerNetworkSession? = {
            #if canImport(MultipeerConnectivity)
            return MultipeerConnectivitySession()
            #else
            return nil
            #endif
        }
    ) -> GameScene {
        let sceneSize = size.width > 0 && size.height > 0 ? size : CGSize(width: 1024, height: 768)
        let scene = GameScene(size: sceneSize, randomSource: randomSource, clock: clock, multiplayerSessionFactory: multiplayerSessionFactory)
        scene.scaleMode = .resizeFill
        return scene
    }
    
    // MARK: - Scene Lifecycle
    override func didMove(to view: SKView) {
        setupWorld()
        setupPhysics()
        setupCameraAndHUD()
        setupPlayer()
        setupWastelandTerrain()
        spawnInitialChests()
        setupMainMenu()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard cameraNode.parent != nil else { return }

        hudManager.setup(in: cameraNode, sceneSize: size)
        hudManager.updateHealth(
            current: playerNode?.currentHealth ?? 100,
            max: playerNode?.maxHealth ?? 100,
            sceneWidth: size.width
        )
        if let playerNode {
            hudManager.updateWeapon(
                weapon: playerNode.currentWeapon,
                damage: playerNode.currentWeaponDamage,
                range: playerNode.currentWeaponRange,
                fireRate: playerNode.currentWeaponFireRate
            )
        }
        if menuState == .main {
            cameraNode.childNode(withName: "mainMenu")?.removeFromParent()
            setupMainMenu()
        }
    }
    
    // MARK: - Setup
    private func setupWorld() {
        backgroundColor = SKColor(red: 0.14, green: 0.12, blue: 0.10, alpha: 1.0)
        addChild(worldNode)
    }
    
    private func setupPhysics() {
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
    }
    
    private func setupCameraAndHUD() {
        camera = cameraNode
        addChild(cameraNode)
        hudManager.setup(in: cameraNode, sceneSize: size)
    }
    
    private func setupPlayer() {
        playerNode = PlayerNode()
        playerNode.position = .zero
        playerNode.zPosition = 10
        worldNode.addChild(playerNode)
        hudManager.updateWeapon(weapon: playerNode.currentWeapon)
    }

    private func setupLocalMultiplayer() {
        guard let session = multiplayerSessionFactory() else { return }
        session.delegate = self
        localMultiplayerSession = session
    }
    
    private func setupWastelandTerrain() {
        // Terrain never changes during gameplay, so render its shape hierarchy once
        // into an effect-node cache instead of tessellating every shape each frame.
        worldNode.addChild(terrainNode)

        let mapRadius: CGFloat = 3000
        let gridStep: CGFloat = 160
        
        for x in stride(from: -mapRadius, through: mapRadius, by: gridStep) {
            for y in stride(from: -mapRadius, through: mapRadius, by: gridStep) {
                let ix = Int(x)
                let iy = Int(y)
                let hash = abs((ix * 73856093) ^ (iy * 19349663))
                let seed = hash % 100
                if seed < 15 {
                    let rock = SKShapeNode(circleOfRadius: randomSource.nextCGFloat(in: 4...12))
                    rock.fillColor = SKColor(red: 0.22, green: 0.19, blue: 0.16, alpha: 1.0)
                    rock.strokeColor = .clear
                    rock.position = CGPoint(x: x + randomSource.nextCGFloat(in: -40...40), y: y + randomSource.nextCGFloat(in: -40...40))
                    rock.zPosition = 1
                    terrainNode.addChild(rock)
                } else if seed < 22 {
                    let crack = SKShapeNode(rectOf: CGSize(width: randomSource.nextCGFloat(in: 20...50), height: randomSource.nextCGFloat(in: 3...6)), cornerRadius: 2)
                    crack.fillColor = SKColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 0.7)
                    crack.strokeColor = .clear
                    crack.zRotation = randomSource.nextCGFloat(in: 0...CGFloat.pi)
                    crack.position = CGPoint(x: x, y: y)
                    crack.zPosition = 1
                    terrainNode.addChild(crack)
                }
            }
        }
    }
    
    private func spawnInitialChests() {
        for _ in 0..<maxChests {
            spawnChest(near: .zero, radius: randomSource.nextCGFloat(in: 250...900))
        }
    }
    
    // MARK: - Spawning System
    private func spawnChest(near origin: CGPoint, radius: CGFloat) {
        let angle = randomSource.nextCGFloat(in: 0...(CGFloat.pi * 2))
        let distance = radius
        let pos = CGPoint(x: origin.x + cos(angle) * distance, y: origin.y + sin(angle) * distance)
        
        let chest = ChestNode()
        chest.position = pos
        chest.zPosition = 5
        worldNode.addChild(chest)
        chests.append(chest)
    }
    
    private func spawnZombieOffscreen() {
        guard zombies.count < maxZombies, !isGameOver else { return }
        
        let angle = randomSource.nextCGFloat(in: 0...(CGFloat.pi * 2))
        let spawnDist: CGFloat = Swift.max(size.width, size.height) * 0.7 + randomSource.nextCGFloat(in: 50...150)
        let pos = CGPoint(
            x: playerNode.position.x + cos(angle) * spawnDist,
            y: playerNode.position.y + sin(angle) * spawnDist
        )
        
        let zombie = ZombieNode(randomSource: randomSource)
        zombie.position = pos
        zombie.zPosition = 8
        worldNode.addChild(zombie)
        zombies.append(zombie)
    }
    
    // MARK: - Game Loop
    override func update(_ currentTime: TimeInterval) {
        let gameTime = clock(currentTime)
        if lastUpdateTime == 0 {
            lastUpdateTime = gameTime
            lastZombieSpawnTime = gameTime
            lastChestSpawnTime = gameTime
            return
        }
        
        let dt = gameTime - lastUpdateTime
        lastUpdateTime = gameTime
        
        guard menuState == .playing, !isGameOver else { return }
        
        // 1. Player Movement & Camera
        updatePlayerMovement(dt: dt)
        cameraNode.position = playerNode.position
        
        // 2. Health regeneration
        if playerNode.updateHealth(deltaTime: dt) {
            hudManager.updateHealth(current: playerNode.currentHealth, max: playerNode.maxHealth, sceneWidth: size.width)
        }
        
        syncLocalPlayerIfNeeded(at: gameTime)
        interpolateMultiplayerNodes(dt: dt)

        if isMultiplayerClient {
            cameraNode.position = playerNode.position
            return
        }

        // 3. Zombies AI and board simulation run only on the elected host.
        updateZombies(dt: dt, currentTime: gameTime)
        // 4. Auto-Combat
        guard let localPlayer = playerNode else { return }
        for player in [localPlayer] + Array(remotePlayers.values) {
            combatSystem.updateAutoCombat(
                player: player,
                zombies: zombies,
                world: worldNode,
                currentTime: gameTime,
                onDamageZombie: { [weak self] zombie, damage in
                    self?.damageZombie(zombie, amount: damage)
                }
            )
        }
        
        // 5. Spawners
        handleSpawning(currentTime: gameTime)
        
        // 6. Cleanup
        zombies.removeAll { $0.isDead && $0.parent == nil }
        chests.removeAll { $0.isOpened && $0.parent == nil }
        powerUps.removeAll { $0.parent == nil }
    }
    
    private func updatePlayerMovement(dt: TimeInterval) {
        var direction = movementVector
        
        #if os(macOS)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if keysPressed.contains(13) || keysPressed.contains(126) { dy += 1 }
        if keysPressed.contains(1)  || keysPressed.contains(125) { dy -= 1 }
        if keysPressed.contains(0)  || keysPressed.contains(123) { dx -= 1 }
        if keysPressed.contains(2)  || keysPressed.contains(124) { dx += 1 }
        
        if dx != 0 || dy != 0 {
            let length = sqrt(dx * dx + dy * dy)
            direction = CGVector(dx: dx / length, dy: dy / length)
        }
        #endif
        
        movePlayerUseCase.execute(player: playerNode, direction: direction, deltaTime: dt)
    }
    
    private func updateZombies(dt: TimeInterval, currentTime: TimeInterval) {
        guard let localPlayer = playerNode else { return }
        let players = [localPlayer] + Array(remotePlayers.values)
        updateEnemyBehaviorUseCase.execute(
            zombies: zombies,
            players: players,
            deltaTime: dt,
            currentTime: currentTime,
            onPlayerDamage: { [weak self] player, amount in
                self?.playerTakeDamage(amount: amount, player: player)
            }
        )
    }
    
    private func handleSpawning(currentTime: TimeInterval) {
        if currentTime - lastZombieSpawnTime > zombieSpawnInterval {
            lastZombieSpawnTime = currentTime
            spawnZombieOffscreen()
            zombieSpawnInterval = Swift.max(minimumZombieSpawnInterval, zombieSpawnInterval - 0.01)
        }
        
        if currentTime - lastChestSpawnTime > chestSpawnInterval {
            lastChestSpawnTime = currentTime
            if chests.count < maxChests {
                spawnChest(near: playerNode.position, radius: CGFloat.random(in: 400...1100))
            }
        }
    }
    
    // MARK: - Damage Handling
    func damageZombie(_ zombie: ZombieNode, amount: CGFloat) {
        guard !zombie.isDead else { return }
        
        zombie.takeDamage(amount: amount)
        
        effectsRenderer.renderZombieHit(at: zombie.position, in: worldNode)
        
        if zombie.isDead {
            killCount += 1
            hudManager.updateKillCount(killCount)
            effectsRenderer.renderEnemyDefeat(at: zombie.position, in: worldNode)
            spawnPowerUpIfSelected(at: zombie.position)
        }
    }

    private func spawnPowerUpIfSelected(at position: CGPoint) {
        guard let powerUp = selectPowerUpDropUseCase.execute() else { return }

        let node = PowerUpNode(powerUp: powerUp)
        node.position = position
        node.zPosition = 7
        worldNode.addChild(node)
        powerUps.append(node)
    }

    func collectPowerUp(_ powerUp: PowerUpNode) {
        guard playerNode.apply(powerUp: powerUp.powerUp) else { return }

        powerUp.removeFromParent()
        hudManager.updateWeapon(
            weapon: playerNode.currentWeapon,
            damage: playerNode.currentWeaponDamage,
            range: playerNode.currentWeaponRange,
            fireRate: playerNode.currentWeaponFireRate
        )
        hudManager.showNotification(text: "POWERUP: \(powerUp.powerUp.title)")
    }
    
    private func playerTakeDamage(amount: CGFloat, player: PlayerNode? = nil) {
        guard !isGameOver else { return }
        
        let target = player ?? playerNode
        target?.takeDamage(amount: amount)
        if target === playerNode {
            hudManager.updateHealth(current: playerNode.currentHealth, max: playerNode.maxHealth, sceneWidth: size.width)
        }
        
        effectsRenderer.renderPlayerDamage(in: cameraNode, sceneSize: size)
        
        if target?.currentHealth == 0, target === playerNode {
            triggerGameOver()
        }
    }
    
    // MARK: - Chest Opening
    func openChest(_ chest: ChestNode) {
        chest.open()
        
        let newWeapon = selectWeaponRewardUseCase.execute(excluding: playerNode.currentWeapon)
        
        playerNode.equip(weapon: newWeapon)
        hudManager.updateWeapon(weapon: newWeapon)
        hudManager.showNotification(text: "ACQUIRED: \(newWeapon.rawValue.uppercased()) [\(newWeapon.category.rawValue)]!")
        effectsRenderer.renderChestReward(
            weapon: newWeapon,
            at: chest.position,
            in: worldNode
        )
    }
    
    // MARK: - Main Menu

    private func setupMainMenu() {
        let menuNode = makeMenuNode(named: "mainMenu", title: "WASTELAND SURVIVORS")
        selectedMenuButtonName = "startButton"
        addMenuButton(named: "startButton", title: "START GAME", position: CGPoint(x: 0, y: 0), to: menuNode)
        addMenuButton(named: "multiplayerButton", title: "LOCAL MULTIPLAYER", position: CGPoint(x: 0, y: -70), to: menuNode)
        #if os(macOS)
        addMenuButton(named: "exitButton", title: "EXIT", position: CGPoint(x: 0, y: -140), to: menuNode)
        #endif
        updateMenuHighlight(in: menuNode)
    }

    private func setupPauseMenu() {
        let menuNode = makeMenuNode(named: "pauseMenu", title: "GAME PAUSED")
        selectedMenuButtonName = "resumeButton"
        addMenuButton(named: "resumeButton", title: "RESUME GAME", position: CGPoint(x: 0, y: 0), to: menuNode)
        addMenuButton(named: "exitToMenuButton", title: "EXIT TO MENU", position: CGPoint(x: 0, y: -80), to: menuNode)
        updateMenuHighlight(in: menuNode)
    }

    private func makeMenuNode(named name: String, title: String) -> SKNode {
        let menuNode = SKNode()
        menuNode.name = name
        menuNode.zPosition = 100
        cameraNode.addChild(menuNode)

        let overlay = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height))
        overlay.name = "menuOverlay"
        overlay.fillColor = SKColor(red: 0.04, green: 0.03, blue: 0.02, alpha: 0.92)
        overlay.strokeColor = .clear
        menuNode.addChild(overlay)

        let titleLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        titleLabel.text = title
        titleLabel.fontSize = 42
        titleLabel.fontColor = .white
        titleLabel.position = CGPoint(x: 0, y: 100)
        menuNode.addChild(titleLabel)
        return menuNode
    }

    private func addMenuButton(named name: String, title: String, position: CGPoint, to menuNode: SKNode) {
        let button = SKShapeNode(rectOf: CGSize(width: 280, height: 56), cornerRadius: 10)
        button.name = name
        button.position = position
        button.strokeColor = SKColor(red: 0.95, green: 0.65, blue: 0.25, alpha: 1)
        button.lineWidth = 2

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = title
        label.fontSize = 22
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.name = name
        button.addChild(label)
        #if os(tvOS)
        button.focusBehavior = .focusable
        #endif
        menuNode.addChild(button)
    }

    private func updateMenuHighlight(in menuNode: SKNode) {
        for button in menuNode.children.compactMap({ $0 as? SKShapeNode }) {
            button.fillColor = button.name == selectedMenuButtonName
                ? SKColor(red: 0.85, green: 0.32, blue: 0.08, alpha: 1)
                : SKColor(red: 0.55, green: 0.19, blue: 0.08, alpha: 1)
        }
    }

    func startGame() {
        guard !hasStartedGame else { return }
        hasStartedGame = true
        menuState = .playing
        cameraNode.childNode(withName: "mainMenu")?.removeFromParent()
    }

    func pauseGame() {
        guard menuState == .playing, !isGameOver else { return }
        menuState = .paused
        selectedMenuButtonName = "resumeButton"
        setupPauseMenu()
    }

    func resumeGame() {
        guard menuState == .paused else { return }
        menuState = .playing
        cameraNode.childNode(withName: "pauseMenu")?.removeFromParent()
    }

    func exitToMainMenu() {
        guard menuState == .paused else { return }
        restartGame()
        menuState = .main
        hasStartedGame = false
        selectedMenuButtonName = "startButton"
        cameraNode.childNode(withName: "pauseMenu")?.removeFromParent()
        setupMainMenu()
    }

    func handleMenuInput(at location: CGPoint) {
        let menuName = menuState == .paused ? "pauseMenu" : "mainMenu"
        guard menuState != .playing,
              let menuNode = cameraNode.childNode(withName: menuName) else { return }

        let menuLocation = menuNode.convert(location, from: cameraNode)
        let buttonNames = ["startButton", "multiplayerButton", "exitButton", "resumeButton", "exitToMenuButton"]
        let buttonName = menuNode.nodes(at: menuLocation)
            .reversed()
            .compactMap { node -> String? in
                var currentNode: SKNode? = node
                while let candidate = currentNode {
                    if let name = candidate.name, buttonNames.contains(name) {
                        return name
                    }
                    currentNode = candidate.parent
                }
                return nil
            }
            .first

        guard let buttonName else { return }

        switch buttonName {
        case "startButton":
            startGame()
        case "multiplayerButton":
            startLocalMultiplayer()
        case "exitButton":
            onExitRequested?()
        case "resumeButton":
            resumeGame()
        case "exitToMenuButton":
            exitToMainMenu()
        default:
            break
        }
    }

    private func moveMenuSelection(down: Bool) {
        let names: [String]
        switch menuState {
        case .main:
            #if os(macOS)
            names = ["startButton", "multiplayerButton", "exitButton"]
            #else
            names = ["startButton"]
            #endif
        case .paused:
            names = ["resumeButton", "exitToMenuButton"]
        case .playing:
            return
        }

        guard let currentIndex = names.firstIndex(of: selectedMenuButtonName) else {
            selectedMenuButtonName = names[0]
            return
        }
        let nextIndex = down
            ? (currentIndex + 1) % names.count
            : (currentIndex - 1 + names.count) % names.count
        selectedMenuButtonName = names[nextIndex]
        let menuName = menuState == .paused ? "pauseMenu" : "mainMenu"
        if let menuNode = cameraNode.childNode(withName: menuName) {
            updateMenuHighlight(in: menuNode)
        }
    }

    private func activateSelectedMenuButton() {
        switch selectedMenuButtonName {
        case "startButton":
            startGame()
        case "multiplayerButton":
            startLocalMultiplayer()
        case "exitButton":
            onExitRequested?()
        case "resumeButton":
            resumeGame()
        case "exitToMenuButton":
            exitToMainMenu()
        default:
            break
        }
    }

    // MARK: - Game Lifecycle & Reset
    private func triggerGameOver() {
        isGameOver = true
        hudManager.showGameOver(kills: killCount, sceneSize: size)
    }
    
    func restartGame() {
        hudManager.hideGameOver()
        
        zombies.forEach { $0.removeFromParent() }
        zombies.removeAll()
        chests.forEach { $0.removeFromParent() }
        chests.removeAll()
        powerUps.forEach { $0.removeFromParent() }
        powerUps.removeAll()
        
        playerNode.reset()
        playerNode.position = .zero
        
        killCount = 0
        hudManager.updateKillCount(0)
        hudManager.updateHealth(current: playerNode.currentHealth, max: playerNode.maxHealth, sceneWidth: size.width)
        hudManager.updateWeapon(weapon: playerNode.currentWeapon)
        
        zombieSpawnInterval = initialZombieSpawnInterval
        isGameOver = false
        hasStartedGame = true
        menuState = .playing
        
        spawnInitialChests()
    }

    func startLocalMultiplayer() {
        multiplayerColor = .blue
        hasSpawnedNearHost = false
        playerNode.apply(multiplayerColor: multiplayerColor)
        knownPlayerStates.removeAll()
        acceptedHostID = nil
        if let session = localMultiplayerSession {
            hostID = session.localPlayerID
        }
        if localMultiplayerSession == nil {
            setupLocalMultiplayer()
        }
        if let session = localMultiplayerSession as? MultipeerConnectivitySession {
            localSessionStartedAt = session.sessionStartedAt
        }
        localMultiplayerSession?.start()
        startGame()
    }

    private func syncLocalPlayerIfNeeded(at currentTime: TimeInterval) {
        guard currentTime - lastMultiplayerSyncTime >= 0.1,
              let session = localMultiplayerSession else { return }
        lastMultiplayerSyncTime = currentTime
        let state = MultiplayerPlayerState(
            id: session.localPlayerID,
            position: playerNode.position,
            color: multiplayerColor,
            health: playerNode.currentHealth,
            weapon: playerNode.currentWeapon,
            powerUps: playerNode.appliedPowerUpTypes,
            rotation: playerNode.zRotation,
            sessionStartedAt: localSessionStartedAt
        )
        knownPlayerStates[state.id] = state
        hostID = MultiplayerHostSelector.hostID(for: Array(knownPlayerStates.values))
        if !isMultiplayerClient { sendBoardSnapshot(using: session) }
        guard let data = try? MultiplayerWireMessage.playerUpdate(state).encoded() else { return }
        session.send(data)
    }

    private func sendBoardSnapshot(using session: LocalMultiplayerNetworkSession) {
        multiplayerSnapshotSequence &+= 1
        let board = MultiplayerBoardState(
            sequence: multiplayerSnapshotSequence,
            timestamp: Date().timeIntervalSince1970,
            hostID: MultiplayerHostSelector.hostID(for: Array(knownPlayerStates.values)) ?? session.localPlayerID,
            players: knownPlayerStates.values.sorted { $0.id < $1.id },
            zombies: zombies.map { zombie in
                MultiplayerZombieState(id: zombie.multiplayerID, x: Double(zombie.position.x), y: Double(zombie.position.y), health: Double(zombie.health), rotation: Double(zombie.zRotation))
            },
            chests: chests.map { chest in
                MultiplayerChestState(id: chest.multiplayerID, x: Double(chest.position.x), y: Double(chest.position.y))
            },
            powerUps: powerUps.map { powerUp in
                MultiplayerPowerUpState(id: powerUp.multiplayerID, x: Double(powerUp.position.x), y: Double(powerUp.position.y), type: powerUp.powerUp)
            },
            projectiles: worldNode.children.compactMap { $0 as? ProjectileNode }.map { projectile in
                MultiplayerProjectileState(id: projectile.multiplayerID, x: Double(projectile.position.x), y: Double(projectile.position.y), angle: Double(projectile.zRotation), weapon: projectile.weapon, damage: Double(projectile.damage))
            },
            killCount: killCount
        )
        guard let data = try? MultiplayerWireMessage.boardSnapshot(board).encoded() else { return }
        session.send(data)
    }

    private func applyBoardSnapshot(_ board: MultiplayerBoardState) {
        if let acceptedHostID, acceptedHostID != board.hostID { return }
        acceptedHostID = board.hostID
        guard receivedSnapshotBuffer.append(board) else { return }
        hostID = board.hostID
        guard isMultiplayerClient else { return }
        killCount = board.killCount
        hudManager.updateKillCount(killCount)

        for state in board.players {
            if state.id == localMultiplayerSession?.localPlayerID {
                setMultiplayerTarget(state.position, for: state.id, on: playerNode)
                playerNode.apply(multiplayerState: state)
                hudManager.updateHealth(current: playerNode.currentHealth, max: playerNode.maxHealth, sceneWidth: size.width)
                hudManager.updateWeapon(
                    weapon: playerNode.currentWeapon,
                    damage: playerNode.currentWeaponDamage,
                    range: playerNode.currentWeaponRange,
                    fireRate: playerNode.currentWeaponFireRate
                )
            } else {
                applyRemotePlayer(state, shouldSpawnNearHost: false)
            }
        }

        reconcileZombies(board.zombies)
        reconcileChests(board.chests)
        reconcilePowerUps(board.powerUps)

        worldNode.children.compactMap { $0 as? ProjectileNode }.forEach { $0.removeFromParent() }
        for state in board.projectiles {
            let projectile = ProjectileNode(weapon: state.weapon, damage: CGFloat(state.damage), directionAngle: CGFloat(state.angle), multiplayerID: state.id)
            projectile.name = state.id
            projectile.position = CGPoint(x: state.x, y: state.y)
            worldNode.addChild(projectile)
        }
    }

    private func setMultiplayerTarget(_ position: CGPoint, for id: String, on node: SKNode) {
        multiplayerTargetPositions[id] = position
        if !initializedMultiplayerTargets.contains(id) {
            node.position = position
            initializedMultiplayerTargets.insert(id)
        }
    }

    private func interpolateMultiplayerNodes(dt: TimeInterval) {
        if let target = multiplayerTargetPositions[localMultiplayerSession?.localPlayerID ?? ""] {
            playerNode.position = MultiplayerInterpolation.position(current: playerNode.position, target: target, deltaTime: dt, responsiveness: 14)
        }
        for (id, player) in remotePlayers {
            guard let target = multiplayerTargetPositions[id] else { continue }
            player.position = MultiplayerInterpolation.position(current: player.position, target: target, deltaTime: dt, responsiveness: 14)
        }
        for node in zombies + chests + powerUps {
            guard let id = node.name, let target = multiplayerTargetPositions[id] else { continue }
            node.position = MultiplayerInterpolation.position(current: node.position, target: target, deltaTime: dt, responsiveness: 10)
        }
    }

    private func reconcileZombies(_ states: [MultiplayerZombieState]) {
        let incomingIDs = Set(states.map(\.id))
        for zombie in zombies where !incomingIDs.contains(zombie.name ?? "") { zombie.removeFromParent() }
        zombies.removeAll { !incomingIDs.contains($0.name ?? "") }
        for state in states {
            let zombie: ZombieNode
            if let existing = zombies.first(where: { $0.name == state.id }) {
                zombie = existing
            } else {
                zombie = ZombieNode(multiplayerID: state.id)
                zombie.name = state.id
                worldNode.addChild(zombie)
                zombies.append(zombie)
            }
            setMultiplayerTarget(CGPoint(x: state.x, y: state.y), for: state.id, on: zombie)
            zombie.zRotation = CGFloat(state.rotation)
            zombie.apply(multiplayerHealth: CGFloat(state.health))
        }
    }

    private func reconcileChests(_ states: [MultiplayerChestState]) {
        let incomingIDs = Set(states.map(\.id))
        for chest in chests where !incomingIDs.contains(chest.name ?? "") { chest.removeFromParent() }
        chests.removeAll { !incomingIDs.contains($0.name ?? "") }
        for state in states {
            let chest: ChestNode
            if let existing = chests.first(where: { $0.name == state.id }) { chest = existing }
            else { chest = ChestNode(multiplayerID: state.id); chest.name = state.id; worldNode.addChild(chest); chests.append(chest) }
            setMultiplayerTarget(CGPoint(x: state.x, y: state.y), for: state.id, on: chest)
        }
    }

    private func reconcilePowerUps(_ states: [MultiplayerPowerUpState]) {
        let incomingIDs = Set(states.map(\.id))
        for powerUp in powerUps where !incomingIDs.contains(powerUp.name ?? "") { powerUp.removeFromParent() }
        powerUps.removeAll { !incomingIDs.contains($0.name ?? "") }
        for state in states {
            let powerUp: PowerUpNode
            if let existing = powerUps.first(where: { $0.name == state.id }) { powerUp = existing }
            else { powerUp = PowerUpNode(powerUp: state.type, multiplayerID: state.id); powerUp.name = state.id; worldNode.addChild(powerUp); powerUps.append(powerUp) }
            setMultiplayerTarget(CGPoint(x: state.x, y: state.y), for: state.id, on: powerUp)
        }
    }

    private func applyRemotePlayer(_ state: MultiplayerPlayerState, shouldSpawnNearHost: Bool = true) {
        guard let session = localMultiplayerSession, state.id != session.localPlayerID else { return }

        let localColor = MultiplayerSpawnPlanner.color(
            localID: session.localPlayerID,
            remoteID: state.id
        )
        multiplayerColor = localColor
        playerNode.apply(multiplayerColor: localColor)
        if shouldSpawnNearHost && localColor == .red && !hasSpawnedNearHost {
            playerNode.position = MultiplayerSpawnPlanner.position(
                forPlayerIndex: 1,
                hostPosition: state.position
            )
            hasSpawnedNearHost = true
        }

        let remotePlayer: PlayerNode
        if let existing = remotePlayers[state.id] {
            remotePlayer = existing
        } else {
            let newPlayer = PlayerNode()
            newPlayer.apply(multiplayerColor: state.color)
            newPlayer.position = state.position
            newPlayer.zPosition = 10
            worldNode.addChild(newPlayer)
            remotePlayers[state.id] = newPlayer
            remotePlayer = newPlayer
        }
        setMultiplayerTarget(state.position, for: state.id, on: remotePlayer)
        remotePlayer.apply(multiplayerColor: state.color)
    }
}

extension GameScene: LocalMultiplayerNetworkSessionDelegate {
    func networkSession(_ session: LocalMultiplayerNetworkSession, didReceive data: Data) {
        let applyMessage = { [weak self] in
            guard let message = try? MultiplayerWireMessage.decode(data) else { return }
            if case let .playerUpdate(state) = message {
                guard let self else { return }
                self.knownPlayerStates[state.id] = state
                self.hostID = MultiplayerHostSelector.hostID(for: Array(self.knownPlayerStates.values))
                self.applyRemotePlayer(state)
            } else if case let .boardSnapshot(board) = message {
                self?.applyBoardSnapshot(board)
            }
        }

        DispatchQueue.main.async(execute: applyMessage)
    }
}

// MARK: - Physics Contacts
extension GameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let maskA = contact.bodyA.categoryBitMask
        let maskB = contact.bodyB.categoryBitMask
        
        if (maskA == PhysicsCategory.projectile && maskB == PhysicsCategory.zombie) ||
           (maskB == PhysicsCategory.projectile && maskA == PhysicsCategory.zombie) {
            
            let projectileBody = maskA == PhysicsCategory.projectile ? contact.bodyA : contact.bodyB
            let zombieBody = maskA == PhysicsCategory.zombie ? contact.bodyA : contact.bodyB
            
            if let projectile = projectileBody.node as? ProjectileNode,
               let zombie = zombieBody.node as? ZombieNode {
                damageZombie(zombie, amount: projectile.weapon.damage)
                projectile.removeFromParent()
            }
        }
        
        if (maskA == PhysicsCategory.player && maskB == PhysicsCategory.chest) ||
           (maskB == PhysicsCategory.player && maskA == PhysicsCategory.chest) {
            
            let chestBody = maskA == PhysicsCategory.chest ? contact.bodyA : contact.bodyB
            if let chest = chestBody.node as? ChestNode, !chest.isOpened {
                openChest(chest)
            }
        }

        if (maskA == PhysicsCategory.player && maskB == PhysicsCategory.powerUp) ||
           (maskB == PhysicsCategory.player && maskA == PhysicsCategory.powerUp) {
            let powerUpBody = maskA == PhysicsCategory.powerUp ? contact.bodyA : contact.bodyB
            if let powerUp = powerUpBody.node as? PowerUpNode {
                collectPowerUp(powerUp)
            }
        }
    }
}

// MARK: - Cross-Platform Input Handling
#if os(iOS) || os(tvOS)
extension GameScene {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if !hasStartedGame {
            handleMenuInput(at: touch.location(in: cameraNode))
            return
        }
        if isGameOver {
            restartGame()
            return
        }
        
        let location = touch.location(in: hudManager.containerNode)
        
        isJoystickActive = true
        joystickTouchOrigin = location
        hudManager.showJoystick(at: location)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isJoystickActive, let touch = touches.first else { return }
        let location = touch.location(in: hudManager.containerNode)
        
        let dx = location.x - joystickTouchOrigin.x
        let dy = location.y - joystickTouchOrigin.y
        let distance = hypot(dx, dy)
        let maxRadius: CGFloat = 45
        
        if distance > 0 {
            let clampedDist = Swift.min(distance, maxRadius)
            let angle = atan2(dy, dx)
            
            let knobPos = CGPoint(
                x: joystickTouchOrigin.x + cos(angle) * clampedDist,
                y: joystickTouchOrigin.y + sin(angle) * clampedDist
            )
            hudManager.updateJoystickKnob(position: knobPos)
            
            let normalized = clampedDist / maxRadius
            movementVector = CGVector(dx: cos(angle) * normalized, dy: sin(angle) * normalized)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isJoystickActive = false
        movementVector = .zero
        hudManager.hideJoystick()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
    
    #if os(tvOS)
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !hasStartedGame {
            if presses.contains(where: { $0.type == .select }) {
                startGame()
            }
            return
        }
        if isGameOver {
            restartGame()
            return
        }
        
        for press in presses {
            switch press.type {
            case .upArrow:
                movementVector = CGVector(dx: 0, dy: 1)
            case .downArrow:
                movementVector = CGVector(dx: 0, dy: -1)
            case .leftArrow:
                movementVector = CGVector(dx: -1, dy: 0)
            case .rightArrow:
                movementVector = CGVector(dx: 1, dy: 0)
            default:
                break
            }
        }
    }
    
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        movementVector = .zero
    }
    #endif
}
#endif

#if os(macOS)
extension GameScene {
    override func keyDown(with event: NSEvent) {
        if menuState != .playing {
            switch event.keyCode {
            case 126:
                moveMenuSelection(down: false)
            case 125:
                moveMenuSelection(down: true)
            case 36, 49:
                activateSelectedMenuButton()
            default:
                break
            }
            return
        }

        if event.keyCode == 53 {
            pauseGame()
            return
        }
        if isGameOver {
            restartGame()
            return
        }
        keysPressed.insert(event.keyCode)
    }
    
    override func keyUp(with event: NSEvent) {
        keysPressed.remove(event.keyCode)
    }

    override func mouseDown(with event: NSEvent) {
        handleMenuInput(at: event.location(in: cameraNode))
    }
}
#endif
