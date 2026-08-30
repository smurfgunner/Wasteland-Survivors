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
    private var multiplayerCoordinator: (any MultiplayerGameplayReplication)?
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
    private var synchronizedPlayerTargets: [String: String?] = [:]
    private var synchronizedZombieTargets: [String: String?] = [:]
    private var hostID: String?
    private var localSessionStartedAt: TimeInterval = 0
    private var authoritativeGameState: GameState?
    private var authoritativeSimulationDriver: FixedTickSimulationDriver?
    private var offlineSimulationDriver: FixedTickSimulationDriver?
    private var clientPredictionDriver: FixedTickSimulationDriver?
    private var latestLocalPlayerInput: PlayerInput?
    private var multiplayerSeed: UInt64 {
        multiplayerSessionID.utf8.reduce(UInt64(1)) { ($0 &* 31) &+ UInt64($1) }
    }
    var authoritativeSimulationTick: UInt64 { authoritativeGameState?.tick ?? 0 }
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
        coordinator.onInitialization = { [weak self] payload in
            self?.applyMultiplayerInitialization(payload)
        }
        coordinator.onRecovery = { [weak self] payload in
            self?.applyMultiplayerRecovery(payload)
        }
        coordinator.onEvent = { [weak self] envelope in
            self?.applyMultiplayerEvent(envelope.payload)
        }
        coordinator.initializationProvider = { [weak self] _ in
            self?.makeMultiplayerInitializationPayload()
        }
        coordinator.recoveryProvider = { [weak self] firstSequence in
            self?.makeMultiplayerRecoveryPayload(firstSequence: firstSequence)
        }
        coordinator.onPeerJoined = { [weak self, weak coordinator] peerID in
            self?.addRemotePlayerIfNeeded(peerID)
            coordinator?.publishInitialization(for: peerID)
        }
        coordinator.onHostLost = { [weak self] _ in
            self?.handleHostMigration()
        }
        multiplayerCoordinator = coordinator
    }

    private func addRemotePlayerIfNeeded(_ peerID: String) {
        guard peerID != multiplayerTransport?.localPeerID,
              remotePlayers[peerID] == nil else { return }
        let player = PlayerNode()
        player.position = .zero
        player.zPosition = 10
        player.apply(multiplayerColor: .red)
        worldNode.addChild(player)
        remotePlayers[peerID] = player

        guard var state = authoritativeGameState,
              !state.players.contains(where: { $0.id == peerID }) else { return }
        state.players.append(GamePlayerState(
            id: peerID,
            position: .zero,
            rotation: 0,
            health: 100,
            weapon: .pistol,
            powerUps: []
        ))
        authoritativeGameState = state
        authoritativeSimulationDriver?.replaceState(state)
        clientPredictionDriver?.replaceState(state)
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
        for index in 0..<maxChests {
            if multiplayerTransport != nil {
                let chestID = "chest-\(index + 1)"
                let angle = DeterministicRandom.value(seed: multiplayerSeed, entityID: chestID, tick: 0, purpose: "spawn-angle") * Double.pi * 2
                let distance = 250 + DeterministicRandom.value(seed: multiplayerSeed, entityID: chestID, tick: 0, purpose: "spawn-radius") * 650
                spawnChest(
                    at: CGPoint(x: cos(angle) * distance, y: sin(angle) * distance),
                    multiplayerID: chestID
                )
            } else {
                spawnChest(near: .zero, radius: randomSource.nextCGFloat(in: 250...900))
            }
        }
    }
    
    // MARK: - Spawning System
    private func spawnChest(near origin: CGPoint, radius: CGFloat) {
        let angle = randomSource.nextCGFloat(in: 0...(CGFloat.pi * 2))
        let distance = radius
        let pos = CGPoint(x: origin.x + cos(angle) * distance, y: origin.y + sin(angle) * distance)
        spawnChest(at: pos, multiplayerID: UUID().uuidString)
    }

    private func spawnChest(at position: CGPoint, multiplayerID: String) {
        let pos = position
        
        let chest = ChestNode(multiplayerID: multiplayerID)
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

        // Fixed-tick simulation owns all gameplay state.
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
        for step in steps {
            renderSimulationState(step.state, localPlayerID: "offline-player")
            renderSimulationEvents(step.events, in: step.state)
        }
        authoritativeGameState = state.state
    }

    private func renderSimulationEvents(_ events: [GameplayEvent], in state: GameState) {
        for event in events {
            guard case let .projectileSpawned(id, _) = event,
                  let projectile = state.projectiles.first(where: { $0.id == id }),
                  !worldNode.children.contains(where: { ($0 as? ProjectileNode)?.multiplayerID == id }) else { continue }

            let node = ProjectileNode(
                weapon: projectile.weapon,
                damage: CGFloat(projectile.damage),
                directionAngle: CGFloat(projectile.angle),
                multiplayerID: projectile.id
            )
            node.position = projectile.position.cgPoint
            worldNode.addChild(node)
            effectsRenderer.renderMuzzleFlash(
                weapon: projectile.weapon,
                at: projectile.position.cgPoint,
                angle: CGFloat(projectile.angle),
                in: worldNode
            )
        }
    }

    private func renderSimulationState(_ state: GameState, localPlayerID: String) {
        guard let player = state.players.first(where: { $0.id == localPlayerID }) else { return }
        playerNode.position = player.position.cgPoint
        playerNode.zRotation = CGFloat(player.rotation)
        playerNode.apply(multiplayerHealth: CGFloat(player.health))
        playerNode.equip(weapon: player.weapon)

        let statePlayerIDs = Set(state.players.map(\.id).filter { $0 != localPlayerID })
        for id in remotePlayers.keys where !statePlayerIDs.contains(id) {
            remotePlayers[id]?.removeFromParent()
            remotePlayers[id] = nil
        }
        for playerState in state.players where playerState.id != localPlayerID {
            let remotePlayer = remotePlayers[playerState.id] ?? PlayerNode()
            if remotePlayer.parent == nil {
                remotePlayer.apply(multiplayerColor: .red)
                remotePlayer.zPosition = 10
                worldNode.addChild(remotePlayer)
                remotePlayers[playerState.id] = remotePlayer
            }
            remotePlayer.position = playerState.position.cgPoint
            remotePlayer.zRotation = CGFloat(playerState.rotation)
            remotePlayer.apply(multiplayerHealth: CGFloat(playerState.health))
            remotePlayer.equip(weapon: playerState.weapon)
        }

        let stateZombieIDs = Set(state.zombies.map(\.id))
        for zombie in zombies where !stateZombieIDs.contains(zombie.multiplayerID) {
            zombie.removeFromParent()
        }
        zombies.removeAll { !stateZombieIDs.contains($0.multiplayerID) }
        for zombieState in state.zombies {
            let zombie = zombies.first { $0.multiplayerID == zombieState.id } ?? ZombieNode(multiplayerID: zombieState.id)
            if zombie.parent == nil {
                worldNode.addChild(zombie)
                zombies.append(zombie)
            }
            zombie.position = zombieState.position.cgPoint
            zombie.zRotation = CGFloat(zombieState.rotation)
            zombie.apply(multiplayerHealth: CGFloat(zombieState.health))
        }

        let stateChestIDs = Set(state.chests.map(\.id))
        for chest in chests where !stateChestIDs.contains(chest.multiplayerID) { chest.removeFromParent() }
        chests.removeAll { !stateChestIDs.contains($0.multiplayerID) }
        for chestState in state.chests {
            let chest = chests.first { $0.multiplayerID == chestState.id } ?? ChestNode(multiplayerID: chestState.id)
            if chest.parent == nil { worldNode.addChild(chest); chests.append(chest) }
            chest.position = chestState.position.cgPoint
            if chestState.isOpened { chest.open() }
        }
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

    private func advanceClientPrediction(dt: TimeInterval) {
        guard var driver = clientPredictionDriver,
              let session = multiplayerTransport else { return }
        localInputSequence &+= 1
        let input = PlayerInput(
            playerID: session.localPeerID,
            sequence: localInputSequence,
            movement: CGPointValue(currentMovementDirection()),
            aimAngle: currentAimAngle(),
            wantsToAttack: true,
            wantsToOpenChestID: pendingChestInteractionID,
            wantsToCollectPowerUpID: pendingPowerUpInteractionID
        )
        pendingChestInteractionID = nil
        pendingPowerUpInteractionID = nil
        latestLocalPlayerInput = input
        multiplayerCoordinator?.submitPlayerInput(input)
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
            inputs.append(contentsOf: multiplayerCoordinator.consumePlayerInputs())
        }

        let steps = driver.advance(elapsedTime: dt, inputs: inputs)
        authoritativeSimulationDriver = driver
        for step in steps {
            renderSimulationState(step.state, localPlayerID: session.localPeerID)
            multiplayerCoordinator?.publishSimulationStep(step)
        }
        guard let state = steps.last else { return }
        authoritativeGameState = state.state
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
        authoritativeGameState = nil
        authoritativeSimulationDriver = nil
        offlineSimulationDriver = nil
        clientPredictionDriver = nil
        latestLocalPlayerInput = nil
        synchronizedPlayerTargets.removeAll()
        synchronizedZombieTargets.removeAll()
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
                seed: multiplayerSeed,
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
                seed: multiplayerSeed,
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
            seed: multiplayerSeed,
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

}

extension GameScene {
    private func makeMultiplayerInitializationPayload() -> MultiplayerInitializationPayload? {
        guard let session = multiplayerTransport else { return nil }
        let players = [
            MultiplayerInitializationPlayer(
                id: session.localPeerID,
                spawnPosition: CGPointValue(x: Double(playerNode.position.x), y: Double(playerNode.position.y)),
                facing: Double(playerNode.zRotation)
            )
        ] + remotePlayers.map { id, node in
            MultiplayerInitializationPlayer(
                id: id,
                spawnPosition: CGPointValue(x: Double(node.position.x), y: Double(node.position.y)),
                facing: Double(node.zRotation)
            )
        }
        let zombies = zombies.map {
            MultiplayerInitializationZombie(
                id: $0.multiplayerID,
                position: CGPointValue(x: Double($0.position.x), y: Double($0.position.y)),
                health: Double($0.health)
            )
        }
        return MultiplayerInitializationPayload(
            sessionID: multiplayerSessionID,
            sequence: multiplayerCoordinator?.currentEventSequence ?? 0,
            simulationTick: authoritativeGameState?.tick ?? 1,
            seed: authoritativeGameState?.seed ?? 0,
            hostID: session.localPeerID,
            players: players,
            zombies: zombies
        )
    }

    private func applyMultiplayerInitialization(_ payload: MultiplayerInitializationPayload) {
        guard let session = multiplayerTransport, payload.hostID != session.localPeerID else { return }
        hostID = payload.hostID
        rebuildSeededCollectibles(seed: payload.seed, tick: payload.simulationTick)
        for player in payload.players {
            if player.id == session.localPeerID {
                playerNode.position = player.spawnPosition.cgPoint
                playerNode.zRotation = CGFloat(player.facing)
                continue
            }
            let node = remotePlayers[player.id] ?? PlayerNode()
            if node.parent == nil {
                worldNode.addChild(node)
                remotePlayers[player.id] = node
            }
            node.position = player.spawnPosition.cgPoint
            node.zRotation = CGFloat(player.facing)
        }
        for zombie in zombies { zombie.removeFromParent() }
        zombies = payload.zombies.map {
            let node = ZombieNode(multiplayerID: $0.id)
            node.position = $0.position.cgPoint
            node.zRotation = 0
            node.apply(multiplayerHealth: CGFloat($0.health))
            worldNode.addChild(node)
            return node
        }
        let initialState = GameState(
            seed: payload.seed,
            tick: payload.simulationTick,
            players: payload.players.map {
                GamePlayerState(id: $0.id, position: $0.spawnPosition, rotation: $0.facing, health: 100, weapon: .pistol, powerUps: [])
            },
            zombies: payload.zombies.map {
                GameZombieState(id: $0.id, position: $0.position, rotation: 0, health: $0.health)
            },
            chests: chests.map {
                GameChestState(
                    id: $0.multiplayerID,
                    position: CGPointValue(x: Double($0.position.x), y: Double($0.position.y)),
                    isOpened: $0.isOpened
                )
            },
            powerUps: powerUps.map {
                GamePowerUpState(
                    id: $0.multiplayerID,
                    position: CGPointValue(x: Double($0.position.x), y: Double($0.position.y)),
                    type: $0.powerUp
                )
            },
            projectiles: [],
            score: killCount,
            isGameOver: false
        )
        authoritativeGameState = initialState
        clientPredictionDriver = FixedTickSimulationDriver(initialState: initialState)
    }

    private func makeMultiplayerRecoveryPayload(firstSequence: UInt64) -> MultiplayerRecoveryPayload? {
        let state = authoritativeGameState
        return MultiplayerRecoveryPayload(
            sessionID: multiplayerSessionID,
            firstSequence: firstSequence,
            lastSequence: multiplayerCoordinator?.currentEventSequence ?? firstSequence,
            simulationTick: state?.tick ?? 0,
            players: ([playerNode] + Array(remotePlayers.values)).enumerated().map { index, player in
                MultiplayerInitializationPlayer(
                    id: index == 0 ? multiplayerTransport?.localPeerID ?? "local" : remotePlayers.first { $0.value === player }?.key ?? "remote-\(index)",
                    spawnPosition: CGPointValue(x: Double(player.position.x), y: Double(player.position.y)),
                    facing: Double(player.zRotation)
                )
            },
            zombies: zombies.map {
                MultiplayerInitializationZombie(
                    id: $0.multiplayerID,
                    position: CGPointValue(x: Double($0.position.x), y: Double($0.position.y)),
                    health: Double($0.health)
                )
            },
            activeChests: chests.map(\.multiplayerID),
            activePowerUps: powerUps.map(\.multiplayerID),
            score: killCount,
            playerHealth: Dictionary(uniqueKeysWithValues: ([playerNode] + Array(remotePlayers.values)).enumerated().map { index, player in
                (index == 0 ? multiplayerTransport?.localPeerID ?? "local" : remotePlayers.first { $0.value === player }?.key ?? "remote-\(index)", Double(player.currentHealth))
            }),
            playerTargets: [:],
            zombieTargets: [:],
            equipment: Dictionary(uniqueKeysWithValues: remotePlayers.map { ($0.key, $0.value.currentWeapon) }),
            removedEntities: [],
            playerDeaths: []
        )
    }

    private func applyMultiplayerRecovery(_ payload: MultiplayerRecoveryPayload) {
        guard payload.sessionID == multiplayerSessionID else { return }
        killCount = payload.score

        let activePlayerIDs = Set(payload.players.map { $0.id })
        let stalePlayerIDs = remotePlayers.keys.filter { !activePlayerIDs.contains($0) }
        for id in stalePlayerIDs {
            remotePlayers[id]?.removeFromParent()
            remotePlayers[id] = nil
        }
        for player in payload.players {
            if player.id == multiplayerTransport?.localPeerID {
                playerNode.position = player.spawnPosition.cgPoint
                playerNode.zRotation = CGFloat(player.facing)
                playerNode.apply(multiplayerHealth: CGFloat(payload.playerHealth[player.id] ?? 100))
                continue
            }
            let node = remotePlayers[player.id] ?? PlayerNode()
            if node.parent == nil {
                worldNode.addChild(node)
                remotePlayers[player.id] = node
            }
            node.position = player.spawnPosition.cgPoint
            node.zRotation = CGFloat(player.facing)
            node.apply(multiplayerHealth: CGFloat(payload.playerHealth[player.id] ?? 100))
            if let weapon = payload.equipment[player.id] {
                node.equip(weapon: weapon)
            }
        }

        let activeZombieIDs = Set(payload.zombies.map { $0.id })
        for zombie in zombies where !activeZombieIDs.contains(zombie.multiplayerID) {
            zombie.removeFromParent()
        }
        zombies.removeAll { !activeZombieIDs.contains($0.multiplayerID) }
        for zombieState in payload.zombies {
            let zombie = zombies.first { $0.multiplayerID == zombieState.id } ?? ZombieNode(multiplayerID: zombieState.id)
            if zombie.parent == nil {
                worldNode.addChild(zombie)
                zombies.append(zombie)
            }
            zombie.position = zombieState.position.cgPoint
            zombie.apply(multiplayerHealth: CGFloat(zombieState.health))
        }

        let activeChestIDs = Set(payload.activeChests)
        for chest in chests where !activeChestIDs.contains(chest.multiplayerID) {
            chest.removeFromParent()
        }
        chests.removeAll { !activeChestIDs.contains($0.multiplayerID) }

        let activePowerUpIDs = Set(payload.activePowerUps)
        for powerUp in powerUps where !activePowerUpIDs.contains(powerUp.multiplayerID) {
            powerUp.removeFromParent()
        }
        powerUps.removeAll { !activePowerUpIDs.contains($0.multiplayerID) }

        for id in payload.removedEntities {
            remotePlayers[id]?.removeFromParent()
            remotePlayers[id] = nil
            zombies.removeAll { zombie in
                guard zombie.multiplayerID == id else { return false }
                zombie.removeFromParent()
                return true
            }
        }
        synchronizedPlayerTargets = payload.playerTargets.mapValues { Optional($0) }
        synchronizedZombieTargets = payload.zombieTargets.mapValues { Optional($0) }

        let recoveredState = GameSceneStateAdapter.gameState(
            localPlayer: playerNode,
            remotePlayers: remotePlayers,
            zombies: zombies,
            chests: chests,
            powerUps: powerUps,
            projectiles: worldNode.children.compactMap { $0 as? ProjectileNode },
            localPlayerID: multiplayerTransport?.localPeerID ?? "local",
            seed: authoritativeGameState?.seed ?? multiplayerSeed,
            tick: payload.simulationTick,
            score: payload.score
        )
        authoritativeGameState = recoveredState
        authoritativeSimulationDriver?.replaceState(recoveredState)
        clientPredictionDriver?.replaceState(recoveredState)
    }

    private func applyMultiplayerEvent(_ event: MultiplayerSyncEvent) {
        switch event {
        case let .playerTransformChanged(playerID, position, facing):
            guard let player = remotePlayers[playerID] else { return }
            player.position = position.cgPoint
            player.zRotation = CGFloat(facing)
        case let .weaponChanged(playerID, weapon):
            remotePlayers[playerID]?.equip(weapon: weapon)
        case let .powerUpAcquired(playerID, type):
            _ = remotePlayers[playerID]?.apply(powerUp: type)
        case let .playerTargetChanged(playerID, zombieID):
            synchronizedPlayerTargets[playerID] = zombieID
        case let .zombieHealthChanged(zombieID, _, health, _):
            zombies.first { $0.multiplayerID == zombieID }?.apply(multiplayerHealth: CGFloat(health))
        case let .playerDamaged(playerID, _, health, _):
            if playerID == multiplayerTransport?.localPeerID {
                playerNode.apply(multiplayerHealth: CGFloat(health))
            } else {
                remotePlayers[playerID]?.apply(multiplayerHealth: CGFloat(health))
            }
        case let .itemCollected(entityID, _, _):
            chests.removeAll { chest in
                guard chest.multiplayerID == entityID else { return false }
                chest.removeFromParent()
                return true
            }
            powerUps.removeAll { powerUp in
                guard powerUp.multiplayerID == entityID else { return false }
                powerUp.removeFromParent()
                return true
            }
        case let .zombieDied(zombieID, _):
            zombies.removeAll { zombie in
                guard zombie.multiplayerID == zombieID else { return false }
                zombie.removeFromParent()
                return true
            }
        case let .playerDied(playerID):
            remotePlayers[playerID]?.removeFromParent()
            remotePlayers[playerID] = nil
            if playerID == multiplayerTransport?.localPeerID { triggerGameOver() }
        case let .scoreChanged(_, total):
            killCount = total
        case let .zombieTargetChanged(zombieID, playerID):
            synchronizedZombieTargets[zombieID] = playerID
        }
    }

    private func handleHostMigration() {
        hostID = multiplayerCoordinator?.hostID
    }

    private func rebuildSeededCollectibles(seed: UInt64, tick: UInt64) {
        chests.forEach { $0.removeFromParent() }
        chests.removeAll()

        for index in 0..<maxChests {
            let id = "chest-\(index + 1)"
            let angle = DeterministicRandom.value(seed: seed, entityID: id, tick: tick, purpose: "spawn-angle") * Double.pi * 2
            let radius = 250 + DeterministicRandom.value(seed: seed, entityID: id, tick: tick, purpose: "spawn-radius") * 650
            spawnChest(at: CGPoint(x: cos(angle) * radius, y: sin(angle) * radius), multiplayerID: id)
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
