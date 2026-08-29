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
    private let randomSource: RandomSource
    private let clock: (TimeInterval) -> TimeInterval
    private let selectWeaponRewardUseCase: SelectWeaponRewardUseCase
    private let selectPowerUpDropUseCase: SelectPowerUpDropUseCase
    private let effectsRenderer: GameEffectsRenderer
    private let multiplayerSessionFactory: () -> MultiplayerTransport?
    let multiplayerSessionID: String
    
    private(set) var playerNode: PlayerNode!
    private(set) var zombies: [ZombieNode] = []
    private(set) var chests: [ChestNode] = []
    private(set) var powerUps: [PowerUpNode] = []
    private(set) var remotePlayers: [String: PlayerNode] = [:]
    private var multiplayerTransport: MultiplayerTransport?
    private var multiplayerCoordinator: MultiplayerSessionCoordinator?
    private var multiplayerColor: MultiplayerPlayerColor = .blue
    private var lastMultiplayerSyncTime: TimeInterval = 0
    private var nextMultiplayerSyncTime: TimeInterval?
    private var lastSentClientInputSequence: UInt64 = 0
    private var hasReceivedFirstUpdate = false
    private var localInputSequence: UInt64 = 0
    private var gameplayEventSequence: UInt64 = 0
    private var pendingChestInteractionID: String?
    private var pendingPowerUpInteractionID: String?
    private var hasSpawnedNearHost = false
    private var knownPlayerStates: [String: MultiplayerPlayerState] = [:]
    private var hostID: String?
    private var localSessionStartedAt: TimeInterval = 0
    private var multiplayerTargetPositions: [String: CGPoint] = [:]
    private var initializedMultiplayerTargets: Set<String> = []
    private var multiplayerSnapshotSequence: UInt64 = 0
    private var receivedSnapshotBuffer = MultiplayerSnapshotBuffer()
    private var multiplayerRenderTick: Double = 0
    private var authoritativeGameState: GameState?
    private var authoritativeSimulationDriver: FixedTickSimulationDriver?
    private var offlineSimulationDriver: FixedTickSimulationDriver?
    private var clientPredictionDriver: FixedTickSimulationDriver?
    private var clientPredictionHistory = LocalPredictionInputHistory()
    private var latestLocalPlayerInput: PlayerInput?
    var authoritativeSimulationTick: UInt64 { authoritativeGameState?.tick ?? 0 }
    private var acceptedHostID: String?
    private var lastClientSnapshotLogTime: TimeInterval = 0
    private var lastClientRenderLogTime: TimeInterval = 0
    private var lastClientInputLogTime: TimeInterval = 0
    private var lastClientInputSendLogTime: TimeInterval = 0
    private var lastClientInputSendGameTime: TimeInterval?
    private var clientMotionMaxRenderStep: CGFloat = 0
    private var isMultiplayerClient: Bool {
        multiplayerCoordinator?.role == .client
    }

    private var isAuthoritativeMultiplayerHost: Bool {
        multiplayerCoordinator?.role == .host
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
    
    // Frame clock and initial presentation content
    private var lastUpdateTime: TimeInterval = 0
    private let maxChests: Int = 8
    
    init(
        size: CGSize,
        randomSource: RandomSource = SystemRandomSource(),
        clock: @escaping (TimeInterval) -> TimeInterval = { $0 },
        multiplayerSessionID: String = UUID().uuidString,
        multiplayerSessionFactory: @escaping () -> MultiplayerTransport? = {
            #if canImport(MultipeerConnectivity)
            return MultipeerConnectivitySession()
            #else
            return nil
            #endif
        }
    ) {
        self.randomSource = randomSource
        self.clock = clock
        self.multiplayerSessionID = multiplayerSessionID
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
        self.multiplayerSessionID = UUID().uuidString
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
        multiplayerSessionID: String = UUID().uuidString,
        multiplayerSessionFactory: @escaping () -> MultiplayerTransport? = {
            #if canImport(MultipeerConnectivity)
            return MultipeerConnectivitySession()
            #else
            return nil
            #endif
        }
    ) -> GameScene {
        let sceneSize = size.width > 0 && size.height > 0 ? size : CGSize(width: 1024, height: 768)
        let scene = GameScene(size: sceneSize, randomSource: randomSource, clock: clock, multiplayerSessionID: multiplayerSessionID, multiplayerSessionFactory: multiplayerSessionFactory)
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
        let offlineState = GameSceneStateAdapter.gameState(
            localPlayer: playerNode,
            remotePlayers: remotePlayers,
            zombies: zombies,
            chests: chests,
            powerUps: powerUps,
            projectiles: worldNode.children.compactMap { $0 as? ProjectileNode },
            localPlayerID: "offline-player",
            seed: 0,
            tick: 0,
            score: killCount
        )
        offlineSimulationDriver = FixedTickSimulationDriver(initialState: offlineState)
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
        multiplayerTransport = session

        let coordinator = MultiplayerSessionCoordinator(
            transport: session,
            sessionID: multiplayerSessionID,
            startedAt: Date().timeIntervalSince1970
        )
        coordinator.onRoleChanged = { [weak self] role in
            guard let self else { return }
            switch role {
            case .host:
                self.hostID = session.localPeerID
            case .client:
                self.hostID = self.multiplayerCoordinator?.hostID
            default:
                break
            }
        }
        coordinator.onMessage = { [weak self] message in
            self?.handleMultiplayerMessage(message)
        }
        coordinator.onPeerJoined = { [weak self] peerID in
            guard let self, let transport = self.multiplayerTransport else { return }
            self.addJoinedPlayerToAuthoritativeState(peerID: peerID)
            self.sendBoardSnapshot(using: transport)
        }
        coordinator.onHostLost = { [weak self] _ in
            self?.triggerGameOver()
        }
        multiplayerCoordinator = coordinator
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
    
    // MARK: - Game Loop
    override func update(_ currentTime: TimeInterval) {
        let gameTime = clock(currentTime)
        if !hasReceivedFirstUpdate {
            hasReceivedFirstUpdate = true
            lastUpdateTime = gameTime
            return
        }
        
        let dt = gameTime - lastUpdateTime
        lastUpdateTime = gameTime
        
        guard menuState == .playing, !isGameOver else { return }
        
        // 1. Player Movement & Camera
        if isAuthoritativeMultiplayerHost, authoritativeGameState != nil {
            advanceAuthoritativePlayerMovement(dt: dt)
        } else if isMultiplayerClient {
            advanceClientPrediction(dt: dt)
        } else {
            advanceOfflineSimulation(dt: dt)
        }
        cameraNode.position = playerNode.position

        if !isAuthoritativeMultiplayerHost && !isMultiplayerClient {
            return
        }

        // Fixed-tick simulation and snapshot rendering own all gameplay state.
        syncLocalPlayerIfNeeded(at: gameTime)
        interpolateMultiplayerNodes(dt: dt)
    }

    private func advanceOfflineSimulation(dt: TimeInterval) {
        guard var driver = offlineSimulationDriver else { return }
        synchronizeOfflinePresentationMutations(&driver)
        let input = PlayerInput(
            playerID: "offline-player",
            sequence: driver.state.tick &+ 1,
            movement: CGPointValue(currentMovementDirection()),
            aimAngle: currentAimAngle(),
            wantsToAttack: true
        )
        let steps = driver.advance(elapsedTime: dt, inputs: [input])
        offlineSimulationDriver = driver
        guard let state = steps.last else { return }
        authoritativeGameState = state.state
        for step in steps {
            renderSimulationAttackEvents(step.events, state: step.state)
        }
        applyAuthoritativeStateToScene(
            state.state,
            localPlayerID: "offline-player",
            playerColors: ["offline-player": .blue],
            sessionStartTimes: [:]
        )
    }

    /// Keeps the legacy node-facing helpers usable while the fixed-tick state
    /// remains the source of truth for the offline game loop. These are only
    /// compatibility inputs; normal gameplay changes enter through simulation
    /// inputs and are rendered back into nodes below.
    private func synchronizeOfflinePresentationMutations(_ driver: inout FixedTickSimulationDriver) {
        var state = driver.state
        guard let playerIndex = state.players.firstIndex(where: { $0.id == "offline-player" }) else { return }
        state.players[playerIndex].position = CGPointValue(x: Double(playerNode.position.x), y: Double(playerNode.position.y))
        state.players[playerIndex].rotation = Double(playerNode.zRotation)
        state.players[playerIndex].health = Double(playerNode.currentHealth)
        state.players[playerIndex].weapon = playerNode.currentWeapon

        let zombieNodes = Dictionary(uniqueKeysWithValues: zombies.map { ($0.multiplayerID, $0) })
        state.zombies.removeAll { zombie in
            guard let node = zombieNodes[zombie.id] else { return true }
            guard node.parent != nil else { return true }
            return node.isDead
        }
        for index in state.zombies.indices {
            guard let node = zombieNodes[state.zombies[index].id] else { continue }
            state.zombies[index].position = CGPointValue(x: Double(node.position.x), y: Double(node.position.y))
            state.zombies[index].rotation = Double(node.zRotation)
            state.zombies[index].health = Double(node.health)
        }

        let chestNodes = Dictionary(uniqueKeysWithValues: chests.map { ($0.multiplayerID, $0) })
        state.chests.removeAll { chest in
            guard let node = chestNodes[chest.id] else { return true }
            return node.parent == nil
        }
        for index in state.chests.indices {
            if let node = chestNodes[state.chests[index].id] {
                state.chests[index].isOpened = node.isOpened
            }
        }

        let powerUpIDs = Set(powerUps.filter { $0.parent != nil }.map(\.multiplayerID))
        state.powerUps.removeAll { !powerUpIDs.contains($0.id) }
        driver.replaceState(state)
    }

    private func applyAuthoritativeStateToScene(
        _ state: GameState,
        localPlayerID: String,
        playerColors: [String: MultiplayerPlayerColor],
        sessionStartTimes: [String: TimeInterval]
    ) {
        let board = GameStateMultiplayerMapper.boardState(
            from: state,
            sequence: state.tick,
            timestamp: 0,
            hostID: localPlayerID,
            playerColors: playerColors,
            sessionStartTimes: sessionStartTimes
        )
        guard let localPlayerState = board.players.first(where: { $0.id == localPlayerID }) else { return }
        playerNode.position = localPlayerState.position
        playerNode.zRotation = localPlayerState.rotation
        playerNode.apply(multiplayerState: localPlayerState)
        for playerState in board.players where playerState.id != localPlayerID {
            applyRemotePlayer(playerState, shouldSpawnNearHost: false)
        }
        killCount = board.killCount
        isGameOver = board.isGameOver
        hudManager.updateKillCount(killCount)
        hudManager.updateHealth(current: playerNode.currentHealth, max: playerNode.maxHealth, sceneWidth: size.width)
        hudManager.updateWeapon(
            weapon: playerNode.currentWeapon,
            damage: playerNode.currentWeaponDamage,
            range: playerNode.currentWeaponRange,
            fireRate: playerNode.currentWeaponFireRate
        )
        reconcileZombies(board.zombies)
        reconcileChests(board.chests)
        reconcilePowerUps(board.powerUps)
        reconcileProjectiles(board.projectiles)
        applyAuthoritativeEntityPositions(board)
    }

    private func applyAuthoritativeEntityPositions(_ board: MultiplayerBoardState) {
        let zombieStates = Dictionary(uniqueKeysWithValues: board.zombies.map { ($0.id, $0) })
        for zombie in zombies {
            guard let state = zombieStates[zombie.multiplayerID] else { continue }
            zombie.position = CGPoint(x: state.x, y: state.y)
            zombie.zRotation = CGFloat(state.rotation)
        }

        let chestStates = Dictionary(uniqueKeysWithValues: board.chests.map { ($0.id, $0) })
        for chest in chests {
            guard let state = chestStates[chest.multiplayerID] else { continue }
            chest.position = CGPoint(x: state.x, y: state.y)
        }

        let powerUpStates = Dictionary(uniqueKeysWithValues: board.powerUps.map { ($0.id, $0) })
        for powerUp in powerUps {
            guard let state = powerUpStates[powerUp.multiplayerID] else { continue }
            powerUp.position = CGPoint(x: state.x, y: state.y)
        }
    }

    private func advanceClientPrediction(dt: TimeInterval) {
        guard var driver = clientPredictionDriver,
              let session = multiplayerTransport else { return }
        localInputSequence &+= 1
        let input = PlayerInput(
            playerID: session.localPeerID,
            sequence: localInputSequence,
            movement: CGPointValue(currentMovementDirection()),
            aimAngle: currentAimAngle(),
            wantsToAttack: true
        )
        latestLocalPlayerInput = input
        initializedMultiplayerTargets.insert(session.localPeerID)
        clientPredictionHistory.record(input)
        let steps = driver.advance(elapsedTime: dt, inputs: [input])
        clientPredictionDriver = driver
        guard let state = steps.last,
              let localPlayer = state.state.players.first(where: { $0.id == session.localPeerID }) else { return }
        let previousRenderPosition = playerNode.position
        playerNode.position = MultiplayerInterpolation.position(
            current: playerNode.position,
            target: localPlayer.position.cgPoint,
            deltaTime: dt,
            responsiveness: 14
        )
        clientMotionMaxRenderStep = max(
            clientMotionMaxRenderStep,
            hypot(
                playerNode.position.x - previousRenderPosition.x,
                playerNode.position.y - previousRenderPosition.y
            )
        )
        playerNode.zRotation = MultiplayerInterpolation.angle(
            current: playerNode.zRotation,
            target: CGFloat(localPlayer.rotation),
            deltaTime: dt,
            responsiveness: 10
        )
    }

    private func currentAimAngle() -> Double {
        let direction = currentMovementDirection()
        guard direction.dx != 0 || direction.dy != 0 else {
            return Double(playerNode.zRotation)
        }
        return Double(atan2(direction.dy, direction.dx))
    }

    private func currentMovementDirection() -> CGVector {
        var direction = movementVector

        #if os(macOS)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if keysPressed.contains(13) || keysPressed.contains(126) { dy += 1 }
        if keysPressed.contains(1) || keysPressed.contains(125) { dy -= 1 }
        if keysPressed.contains(0) || keysPressed.contains(123) { dx -= 1 }
        if keysPressed.contains(2) || keysPressed.contains(124) { dx += 1 }

        if dx != 0 || dy != 0 {
            let length = sqrt(dx * dx + dy * dy)
            direction = CGVector(dx: dx / length, dy: dy / length)
        }
        #endif

        return direction
    }

    private func advanceAuthoritativePlayerMovement(dt: TimeInterval) {
        guard var driver = authoritativeSimulationDriver,
              let session = multiplayerTransport,
              driver.state.players.contains(where: { $0.id == session.localPeerID }) else {
            return
        }

        var inputs = [PlayerInput(
            playerID: session.localPeerID,
            sequence: driver.state.tick &+ 1,
            movement: CGPointValue(currentMovementDirection()),
            aimAngle: currentAimAngle(),
            wantsToAttack: true
        )]
        if let multiplayerCoordinator {
            inputs.append(contentsOf: multiplayerCoordinator.consumeQueuedInputs().map {
                PlayerInput(
                    playerID: $0.playerID,
                    sequence: $0.sequence,
                    movement: CGPointValue($0.movement),
                    aimAngle: $0.aimAngle,
                    wantsToAttack: $0.wantsToAttack,
                    wantsToOpenChestID: $0.wantsToOpenChestID,
                    wantsToCollectPowerUpID: $0.wantsToCollectPowerUpID
                )
            })
        }

        let steps = driver.advance(elapsedTime: dt, inputs: inputs)
        authoritativeSimulationDriver = driver
        for step in steps {
            renderSimulationAttackEvents(step.events, state: step.state)
            for event in step.events {
                gameplayEventSequence &+= 1
                multiplayerCoordinator?.broadcastGameplayEvent(
                    event,
                    sequence: gameplayEventSequence,
                    tick: step.state.tick
                )
            }
        }
        guard let state = steps.last else { return }
        authoritativeGameState = state.state
        applyAuthoritativeStateToScene(
            state.state,
            localPlayerID: session.localPeerID,
            playerColors: knownPlayerStates.mapValues(\.color),
            sessionStartTimes: knownPlayerStates.mapValues(\.sessionStartedAt)
        )
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
        if isMultiplayerClient {
            pendingPowerUpInteractionID = powerUp.multiplayerID
            return
        }
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
        if isMultiplayerClient {
            pendingChestInteractionID = chest.multiplayerID
            return
        }
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
        
        isGameOver = false
        hasStartedGame = true
        menuState = .playing
        lastUpdateTime = 0
        hasReceivedFirstUpdate = false
        lastMultiplayerSyncTime = 0
        multiplayerSnapshotSequence = 0
        multiplayerTargetPositions.removeAll()
        initializedMultiplayerTargets.removeAll()
        receivedSnapshotBuffer = MultiplayerSnapshotBuffer()
        multiplayerRenderTick = 0
        authoritativeGameState = nil
        authoritativeSimulationDriver = nil
        offlineSimulationDriver = nil
        clientPredictionDriver = nil
        clientPredictionHistory = LocalPredictionInputHistory()
        latestLocalPlayerInput = nil
        localInputSequence = 0
        gameplayEventSequence = 0
        pendingChestInteractionID = nil
        pendingPowerUpInteractionID = nil
        lastMultiplayerSyncTime = 0
        nextMultiplayerSyncTime = nil
        lastSentClientInputSequence = 0

        spawnInitialChests()
        if let session = multiplayerTransport {
            let resetState = GameSceneStateAdapter.gameState(
                localPlayer: playerNode,
                remotePlayers: remotePlayers,
                zombies: zombies,
                chests: chests,
                powerUps: powerUps,
                projectiles: worldNode.children.compactMap { $0 as? ProjectileNode },
                localPlayerID: session.localPeerID,
                seed: 0,
                tick: 0,
                score: killCount
            )
            authoritativeGameState = resetState
            authoritativeSimulationDriver = FixedTickSimulationDriver(initialState: resetState)
        } else {
            let resetState = GameSceneStateAdapter.gameState(
                localPlayer: playerNode,
                remotePlayers: remotePlayers,
                zombies: zombies,
                chests: chests,
                powerUps: powerUps,
                projectiles: worldNode.children.compactMap { $0 as? ProjectileNode },
                localPlayerID: "offline-player",
                seed: 0,
                tick: 0,
                score: killCount
            )
            offlineSimulationDriver = FixedTickSimulationDriver(initialState: resetState)
        }
    }

    func startLocalMultiplayer() {
        multiplayerColor = .blue
        hasSpawnedNearHost = false
        playerNode.apply(multiplayerColor: multiplayerColor)
        knownPlayerStates.removeAll()
        acceptedHostID = nil
        if multiplayerTransport == nil {
            setupLocalMultiplayer()
        }
        if let session = multiplayerTransport as? MultipeerConnectivitySession {
            localSessionStartedAt = session.sessionStartedAt
        }
        guard let session = multiplayerTransport else {
            startGame()
            return
        }
        let initialState = GameSceneStateAdapter.gameState(
            localPlayer: playerNode,
            remotePlayers: remotePlayers,
            zombies: zombies,
            chests: chests,
            powerUps: powerUps,
            projectiles: worldNode.children.compactMap { $0 as? ProjectileNode },
            localPlayerID: session.localPeerID,
            seed: 0,
            tick: 0,
            score: killCount
        )
        authoritativeGameState = initialState
        authoritativeSimulationDriver = FixedTickSimulationDriver(initialState: initialState)
        clientPredictionDriver = FixedTickSimulationDriver(initialState: initialState)
        if let multiplayerCoordinator {
            multiplayerCoordinator.start()
        } else {
            multiplayerTransport?.connect()
        }
        startGame()
    }

    private func syncLocalPlayerIfNeeded(at currentTime: TimeInterval) {
        let syncInterval = isMultiplayerClient ? (1.0 / 30.0) : MultiplayerSnapshotTiming.hostSnapshotInterval
        if isMultiplayerClient {
            guard let latestInput = latestLocalPlayerInput,
                  latestInput.sequence == 1
                    || latestInput.sequence >= lastSentClientInputSequence &+ 2 else {
                return
            }
        } else {
            let scheduledTime = nextMultiplayerSyncTime ?? currentTime
            guard currentTime >= scheduledTime else { return }
            nextMultiplayerSyncTime = currentTime + syncInterval
        }
        guard let session = multiplayerTransport else { return }
        lastMultiplayerSyncTime = currentTime
        let state = MultiplayerPlayerState(
            id: session.localPeerID,
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
        if isMultiplayerClient {
            guard let input = latestLocalPlayerInput else { return }
            let outgoingInput = MultiplayerPlayerInput(
                playerID: input.playerID,
                sequence: input.sequence,
                movement: CGVector(dx: input.movement.x, dy: input.movement.y),
                aimAngle: input.aimAngle,
                wantsToAttack: input.wantsToAttack,
                attackTargetID: input.attackTargetID,
                wantsToOpenChestID: pendingChestInteractionID ?? input.wantsToOpenChestID,
                wantsToCollectPowerUpID: pendingPowerUpInteractionID ?? input.wantsToCollectPowerUpID
            )
            multiplayerCoordinator?.sendPlayerInput(outgoingInput)
            lastSentClientInputSequence = outgoingInput.sequence
            pendingChestInteractionID = nil
            pendingPowerUpInteractionID = nil
            return
        }
        sendBoardSnapshot(using: session)
        guard let data = try? MultiplayerWireMessage.playerUpdate(state).encoded() else { return }
        try? session.broadcast(data, delivery: .replaceable)
    }

    private func sendBoardSnapshot(using session: MultiplayerTransport) {
        multiplayerSnapshotSequence &+= 1
        let timestamp = Date().timeIntervalSince1970
        let state = (isAuthoritativeMultiplayerHost ? authoritativeSimulationDriver?.state : nil)
            ?? authoritativeGameState
            ?? GameSceneStateAdapter.gameState(
            localPlayer: playerNode,
            remotePlayers: remotePlayers,
            zombies: zombies,
            chests: chests,
            powerUps: powerUps,
            projectiles: worldNode.children.compactMap { $0 as? ProjectileNode },
            localPlayerID: session.localPeerID,
            seed: 0,
            tick: multiplayerSnapshotSequence,
            score: killCount
        )
        let playerColors = knownPlayerStates.mapValues(\.color)
        let sessionStartTimes = knownPlayerStates.mapValues(\.sessionStartedAt)
        let hostID = isAuthoritativeMultiplayerHost
            ? session.localPeerID
            : MultiplayerHostSelector.hostID(for: Array(knownPlayerStates.values)) ?? session.localPeerID
        let board = GameStateMultiplayerMapper.boardState(
            from: state,
            sequence: multiplayerSnapshotSequence,
            timestamp: timestamp,
            hostID: hostID,
            playerColors: playerColors,
            sessionStartTimes: sessionStartTimes,
            acknowledgedInputSequences: (multiplayerCoordinator?.acknowledgedInputSequences ?? [:])
        )
        guard let data = try? MultiplayerWireMessage.boardSnapshot(board).encoded() else { return }
        try? session.broadcast(data, delivery: .replaceable)
    }

    private func applyBoardSnapshot(_ board: MultiplayerBoardState) {
        if let acceptedHostID, acceptedHostID != board.hostID { return }
        acceptedHostID = board.hostID
        guard receivedSnapshotBuffer.append(board) else { return }
        multiplayerRenderTick = max(multiplayerRenderTick, Double(board.simulationTick))
        hostID = board.hostID
        guard isMultiplayerClient else { return }

        let predictionTick = clientPredictionDriver?.state.tick
        let predictionSeed = clientPredictionDriver?.state.seed ?? 0
        let authoritativeState = GameStateMultiplayerMapper.gameState(from: board, seed: predictionSeed)
        clientPredictionHistory.acknowledge(
            sequence: board.acknowledgedInputSequences[multiplayerTransport?.localPeerID ?? ""] ?? 0,
            for: multiplayerTransport?.localPeerID
        )
        let reconciledState = LocalPredictionReconciler.reconcile(
            authoritativeState: authoritativeState,
            acknowledgedInputSequence: board.acknowledgedInputSequences[multiplayerTransport?.localPeerID ?? ""] ?? 0,
            pendingInputs: clientPredictionHistory.pendingInputs,
            simulation: GameSimulation(),
            targetTick: max(predictionTick ?? board.simulationTick, authoritativeState.tick)
        )
        clientPredictionDriver = FixedTickSimulationDriver(initialState: reconciledState)

        killCount = board.killCount
        hudManager.updateKillCount(killCount)

        for state in board.players {
            if state.id == multiplayerTransport?.localPeerID {
                if !initializedMultiplayerTargets.contains(state.id) {
                    playerNode.position = state.position
                    initializedMultiplayerTargets.insert(state.id)
                }
                playerNode.apply(multiplayerState: state)
                hudManager.updateHealth(current: playerNode.currentHealth, max: playerNode.maxHealth, sceneWidth: size.width)
                hudManager.updateWeapon(
                    weapon: playerNode.currentWeapon,
                    damage: playerNode.currentWeaponDamage,
                    range: playerNode.currentWeaponRange,
                    fireRate: playerNode.currentWeaponFireRate
                )
                if let predictedPlayer = reconciledState.players.first(where: { $0.id == state.id }) {
                    // Keep the simulation state authoritative while blending the
                    // visible node toward it to avoid a correction teleport.
                    playerNode.position = MultiplayerInterpolation.position(
                        current: playerNode.position,
                        target: predictedPlayer.position.cgPoint,
                        deltaTime: 0.1,
                        responsiveness: 2.5
                    )
                    playerNode.zRotation = MultiplayerInterpolation.angle(
                        current: playerNode.zRotation,
                        target: CGFloat(predictedPlayer.rotation),
                        deltaTime: 0.1,
                        responsiveness: 2.5
                    )
                }
            } else {
                applyRemotePlayer(state, shouldSpawnNearHost: false)
            }
        }

        reconcileZombies(board.zombies)
        reconcileChests(board.chests)
        reconcilePowerUps(board.powerUps)

        reconcileProjectiles(board.projectiles)
    }

    private func setMultiplayerTarget(_ position: CGPoint, for id: String, on node: SKNode) {
        multiplayerTargetPositions[id] = position
        if !initializedMultiplayerTargets.contains(id) {
            node.position = position
            initializedMultiplayerTargets.insert(id)
        }
    }

    private func interpolateMultiplayerNodes(dt: TimeInterval) {
        if isMultiplayerClient {
            multiplayerRenderTick += max(0, dt * 60)
            let renderTick = UInt64(max(0, multiplayerRenderTick.rounded(.down)))
            let snapshotIntervalTicks: UInt64 = {
                let ticks = receivedSnapshotBuffer.snapshots.suffix(2).map { $0.simulationTick }
                guard ticks.count == 2 else { return 2 }
                return max(1, ticks[1] - ticks[0])
            }()
            let delayTicks = min(
                6,
                MultiplayerSnapshotTiming.interpolationDelayTicks(
                    snapshotIntervalTicks: snapshotIntervalTicks
                )
            )
            let maxExtrapolationTicks: UInt64 = 3
            for (id, player) in remotePlayers {
                if let sampled = receivedSnapshotBuffer.position(
                    for: id,
                    renderTick: renderTick,
                    delayTicks: delayTicks,
                    maxExtrapolationTicks: maxExtrapolationTicks
                ) {
                    multiplayerTargetPositions[id] = sampled
                    player.position = MultiplayerInterpolation.position(current: player.position, target: sampled, deltaTime: dt, responsiveness: 10)
                }
            }
            for node in zombies.filter({ !$0.isDead }) + chests + powerUps {
                guard let id = node.name,
                      let sampled = receivedSnapshotBuffer.position(
                          for: id,
                          renderTick: renderTick,
                          delayTicks: delayTicks,
                          maxExtrapolationTicks: maxExtrapolationTicks
                      ) else { continue }
                multiplayerTargetPositions[id] = sampled
                node.position = MultiplayerInterpolation.position(current: node.position, target: sampled, deltaTime: dt, responsiveness: 10)
            }
            return
        }
        if let target = multiplayerTargetPositions[multiplayerTransport?.localPeerID ?? ""] {
            playerNode.position = MultiplayerInterpolation.position(current: playerNode.position, target: target, deltaTime: dt, responsiveness: 14)
        }
        for (id, player) in remotePlayers {
            guard let target = multiplayerTargetPositions[id] else { continue }
            player.position = MultiplayerInterpolation.position(current: player.position, target: target, deltaTime: dt, responsiveness: 14)
        }
        for node in zombies.filter({ !$0.isDead }) + chests + powerUps {
            guard let id = node.name, let target = multiplayerTargetPositions[id] else { continue }
            node.position = MultiplayerInterpolation.position(current: node.position, target: target, deltaTime: dt, responsiveness: 10)
        }
    }

    private func reconcileZombies(_ states: [MultiplayerZombieState]) {
        var entities = Dictionary(uniqueKeysWithValues: zombies.map { ($0.multiplayerID, $0) })
        MultiplayerEntityReconciler.reconcile(
            states: states,
            entities: &entities,
            id: \.id,
            create: { [worldNode] state in
                let zombie = ZombieNode(multiplayerID: state.id)
                zombie.name = state.id
                worldNode.addChild(zombie)
                return zombie
            },
            update: { [weak self, worldNode] zombie, state in
                if state.health > 0, zombie.parent == nil {
                    worldNode.addChild(zombie)
                }
                self?.setMultiplayerTarget(CGPoint(x: state.x, y: state.y), for: state.id, on: zombie)
                zombie.zRotation = CGFloat(state.rotation)
                zombie.apply(multiplayerHealth: CGFloat(state.health))
            },
            remove: { $0.removeFromParent() }
        )
        zombies = states.compactMap { entities[$0.id] }
    }

    private func reconcileChests(_ states: [MultiplayerChestState]) {
        var entities = Dictionary(uniqueKeysWithValues: chests.map { ($0.multiplayerID, $0) })
        MultiplayerEntityReconciler.reconcile(
            states: states,
            entities: &entities,
            id: \.id,
            create: { [worldNode] state in
                let chest = ChestNode(multiplayerID: state.id)
                chest.name = state.id
                worldNode.addChild(chest)
                return chest
            },
            update: { [weak self] chest, state in
                self?.setMultiplayerTarget(CGPoint(x: state.x, y: state.y), for: state.id, on: chest)
            },
            remove: { $0.removeFromParent() }
        )
        chests = states.compactMap { entities[$0.id] }
    }

    private func reconcileProjectiles(_ states: [MultiplayerProjectileState]) {
        var entities: [String: ProjectileNode] = Dictionary(uniqueKeysWithValues: worldNode.children.compactMap { node in
            guard let projectile = node as? ProjectileNode else { return nil }
            return (projectile.multiplayerID, projectile)
        })
        let incomingIDs = Set(states.map(\.id))
        for projectile in entities.values where !incomingIDs.contains(projectile.multiplayerID) {
            projectile.removeFromParent()
        }
        for state in states {
            if let projectile = entities[state.id], projectile.weapon == state.weapon, projectile.damage == CGFloat(state.damage) {
                projectile.position = CGPoint(x: state.x, y: state.y)
                projectile.zRotation = CGFloat(state.angle)
            } else {
                entities[state.id]?.removeFromParent()
                let projectile = ProjectileNode(weapon: state.weapon, damage: CGFloat(state.damage), directionAngle: CGFloat(state.angle), multiplayerID: state.id)
                projectile.name = state.id
                projectile.position = CGPoint(x: state.x, y: state.y)
                worldNode.addChild(projectile)
                entities[state.id] = projectile
            }
        }
    }

    private func reconcilePowerUps(_ states: [MultiplayerPowerUpState]) {
        var entities = Dictionary(uniqueKeysWithValues: powerUps.map { ($0.multiplayerID, $0) })
        MultiplayerEntityReconciler.reconcile(
            states: states,
            entities: &entities,
            id: \.id,
            create: { [worldNode] state in
                let powerUp = PowerUpNode(powerUp: state.type, multiplayerID: state.id)
                powerUp.name = state.id
                worldNode.addChild(powerUp)
                return powerUp
            },
            update: { [weak self] powerUp, state in
                self?.setMultiplayerTarget(CGPoint(x: state.x, y: state.y), for: state.id, on: powerUp)
            },
            remove: { $0.removeFromParent() }
        )
        powerUps = states.compactMap { entities[$0.id] }
    }

    private func applyRemotePlayer(_ state: MultiplayerPlayerState, shouldSpawnNearHost: Bool = true) {
        guard let session = multiplayerTransport, state.id != session.localPeerID else { return }

        let localColor = MultiplayerSpawnPlanner.color(
            localID: session.localPeerID,
            remoteID: state.id
        )
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
        remotePlayer.apply(multiplayerState: state)
    }

    private func addJoinedPlayerToAuthoritativeState(peerID: String) {
        guard isAuthoritativeMultiplayerHost,
              let session = multiplayerTransport,
              session.localPeerID != peerID,
              var driver = authoritativeSimulationDriver else { return }
        guard !driver.state.players.contains(where: { $0.id == peerID }) else { return }

        let spawnPosition = MultiplayerSpawnPlanner.position(
            forPlayerIndex: driver.state.players.count,
            hostPosition: playerNode.position
        )
        let state = GamePlayerState(
            id: peerID,
            position: CGPointValue(x: Double(spawnPosition.x), y: Double(spawnPosition.y)),
            rotation: 0,
            health: 100,
            weapon: .pistol,
            powerUps: []
        )
        var authoritativeState = driver.state
        authoritativeState.players.append(state)
        driver.replaceState(authoritativeState)
        authoritativeSimulationDriver = driver
        authoritativeGameState = authoritativeState

        let playerState = MultiplayerPlayerState(
            id: peerID,
            position: spawnPosition,
            color: MultiplayerSpawnPlanner.color(localID: session.localPeerID, remoteID: peerID),
            sessionStartedAt: Date().timeIntervalSince1970
        )
        knownPlayerStates[peerID] = playerState
        applyRemotePlayer(playerState, shouldSpawnNearHost: false)
    }
}

extension GameScene {
    fileprivate func handleMultiplayerMessage(_ message: MultiplayerWireMessage) {
        switch message {
        case let .playerUpdate(state):
            knownPlayerStates[state.id] = state
            hostID = MultiplayerHostSelector.hostID(for: Array(knownPlayerStates.values))
            applyRemotePlayer(state)
        case let .boardSnapshot(board):
            applyBoardSnapshot(board)
        case let .gameplayEvent(envelope):
            applyGameplayEvent(envelope.event)
        default:
            break
        }
    }

    private func renderSimulationAttackEvents(_ events: [GameplayEvent], state: GameState) {
        for event in events {
            switch event {
            case let .projectileSpawned(id, ownerID):
                guard !id.hasSuffix("-1"), !id.hasSuffix("-2"),
                      let player = state.players.first(where: { $0.id == ownerID }) else { continue }
                effectsRenderer.renderMuzzleFlash(
                    weapon: player.weapon,
                    at: player.position.cgPoint,
                    angle: CGFloat(player.rotation),
                    in: worldNode
                )
            case let .meleeAttack(_, ownerID):
                guard let player = state.players.first(where: { $0.id == ownerID }) else { continue }
                let slash = MeleeSlashNode(
                    weapon: player.weapon,
                    range: CGFloat(player.weapon.range),
                    angle: CGFloat(player.rotation)
                )
                slash.position = player.position.cgPoint
                slash.zPosition = 14
                worldNode.addChild(slash)
            default:
                break
            }
        }
    }

    private func renderClientAttackEvent(_ event: GameplayEvent) {
        let ownerID: String
        switch event {
        case let .projectileSpawned(id, owner):
            guard !id.hasSuffix("-1"), !id.hasSuffix("-2") else { return }
            ownerID = owner
        case let .meleeAttack(_, owner):
            ownerID = owner
        default:
            return
        }

        let player = ownerID == multiplayerTransport?.localPeerID
            ? playerNode
            : remotePlayers[ownerID]
        guard let player else { return }

        switch event {
        case .projectileSpawned:
            effectsRenderer.renderMuzzleFlash(
                weapon: player.currentWeapon,
                at: player.position,
                angle: player.zRotation,
                in: worldNode
            )
        case .meleeAttack:
            let slash = MeleeSlashNode(
                weapon: player.currentWeapon,
                range: player.currentWeaponRange,
                angle: player.zRotation
            )
            slash.position = player.position
            slash.zPosition = 14
            worldNode.addChild(slash)
        default:
            break
        }
    }

    private func applyGameplayEvent(_ event: GameplayEvent) {
        guard isMultiplayerClient else { return }
        switch event {
        case .matchEnded:
            triggerGameOver()
        case .projectileSpawned, .meleeAttack:
            renderClientAttackEvent(event)
        case .zombieDamaged, .zombieKilled, .chestOpened, .powerUpCollected,
             .playerDamaged, .playerEliminated:
            // Entity and health changes are committed by the next authoritative snapshot.
            break
        }
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
