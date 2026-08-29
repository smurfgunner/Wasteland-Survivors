import SpriteKit
import Testing
@testable import Wasteland_Survivors

@Suite("Game State Multiplayer Mapping")
struct GameStateMultiplayerMapperTests {
    @Test("Maps authoritative GameState into the compatibility board snapshot")
    func mapsGameStateIntoBoardSnapshot() {
        // Given an authoritative state containing every replicated entity type.
        var state = GameState.initial(seed: 7, playerID: "player")
        state.players[0].position = CGPointValue(x: 12, y: -8)
        state.players[0].rotation = 0.5
        state.players[0].health = 72
        state.players[0].weapon = .rifle
        state.players[0].powerUps = [.damage]
        state.zombies = [
            GameZombieState(id: "zombie-1", position: CGPointValue(x: 30, y: 40), rotation: 0.25, health: 18)
        ]
        state.chests = [
            GameChestState(id: "chest-1", position: CGPointValue(x: 50, y: 60), isOpened: false)
        ]
        state.powerUps = [
            GamePowerUpState(id: "powerup-1", position: CGPointValue(x: 70, y: 80), type: .range)
        ]
        state.projectiles = [
            GameProjectileState(id: "projectile-1", ownerID: "player", position: CGPointValue(x: 90, y: 100), angle: 0.75, weapon: .pistol, damage: 30, spawnedTick: 6)
        ]
        state.score = 4
        state.tick = 12
        state.isGameOver = true
        state.lastAttackTickByPlayer = ["player": 10]
        state.lastDamageTickByPlayer = ["player": 9]

        // When the compatibility mapper converts it for the existing network path.
        let board = GameStateMultiplayerMapper.boardState(
            from: state,
            sequence: 11,
            timestamp: 3.5,
            hostID: "host",
            playerColors: ["player": .green],
            sessionStartTimes: ["player": 1.25],
            acknowledgedInputSequences: ["player": 8]
        )

        // Then all state values and stable IDs are preserved.
        #expect(board.sequence == 11)
        #expect(board.seed == 7)
        #expect(board.timestamp == 3.5)
        #expect(board.serverTime == 3.5)
        #expect(board.simulationTick == 12)
        #expect(board.hostID == "host")
        #expect(board.killCount == 4)
        #expect(board.isGameOver)
        #expect(board.lastAttackTickByPlayer == ["player": 10])
        #expect(board.lastDamageTickByPlayer == ["player": 9])
        #expect(board.players[0].position == CGPointValue(x: 12, y: -8).cgPoint)
        #expect(board.players[0].health == 72)
        #expect(board.players[0].weapon == .rifle)
        #expect(board.players[0].color == .green)
        #expect(board.players[0].sessionStartedAt == 1.25)
        #expect(board.acknowledgedInputSequences == ["player": 8])
        #expect(board.zombies[0].id == "zombie-1")
        #expect(board.chests[0].id == "chest-1")
        #expect(board.powerUps[0].type == .range)
        #expect(board.projectiles[0].id == "projectile-1")
        #expect(board.projectiles[0].ownerID == "player")
        #expect(board.projectiles[0].spawnedTick == 6)
        #expect(board.stateHash == board.contentHash)
    }

    @Test("Changes to authoritative state produce a different board state hash")
    func changesToAuthoritativeStateChangeBoardHash() {
        var original = GameState.initial(seed: 7, playerID: "player")
        original.tick = 1
        var changed = original
        changed.players[0].health -= 1

        let originalBoard = GameStateMultiplayerMapper.boardState(
            from: original,
            sequence: 1,
            timestamp: 1,
            hostID: "host",
            playerColors: [:],
            sessionStartTimes: [:]
        )
        let changedBoard = GameStateMultiplayerMapper.boardState(
            from: changed,
            sequence: 2,
            timestamp: 2,
            hostID: "host",
            playerColors: [:],
            sessionStartTimes: [:]
        )

        #expect(originalBoard.stateHash != changedBoard.stateHash)
    }

    @Test("Adapts the current scene cache into authoritative GameState")
    @MainActor
    func adaptsSceneCacheIntoGameState() {
        // Given a scene with a local player and one replicated zombie.
        let player = PlayerNode()
        player.position = CGPoint(x: 4, y: 5)
        let zombie = ZombieNode()
        zombie.position = CGPoint(x: 8, y: 9)

        // When the compatibility adapter captures the scene.
        let state = GameSceneStateAdapter.gameState(
            localPlayer: player,
            remotePlayers: [:],
            zombies: [zombie],
            chests: [],
            powerUps: [],
            projectiles: [],
            localPlayerID: "local",
            seed: 3,
            tick: 4,
            score: 2
        )

        // Then the resulting value state contains the same gameplay data.
        #expect(state.tick == 4)
        #expect(state.score == 2)
        #expect(state.players.count == 1)
        #expect(state.players[0].position == CGPointValue(x: 4, y: 5))
        #expect(state.zombies[0].position == CGPointValue(x: 8, y: 9))
    }

    @Test("Maps players deterministically regardless of input array order")
    func mapsPlayersInStableOrder() {
        // Given two authoritative players in non-deterministic input order.
        var state = GameState.initial(seed: 1, playerID: "z")
        state.players.append(GamePlayerState(
            id: "a",
            position: .zero,
            rotation: 0,
            health: 100,
            weapon: .pistol,
            powerUps: []
        ))

        // When the state is mapped.
        let board = GameStateMultiplayerMapper.boardState(
            from: state,
            sequence: 1,
            timestamp: 0,
            hostID: "z",
            playerColors: ["z": .blue, "a": .red],
            sessionStartTimes: [:]
        )

        // Then wire ordering is stable and independent of insertion order.
        #expect(board.players.map(\.id) == ["a", "z"])
    }

    @Test("Reconstructs simulation state from an authoritative board snapshot")
    func reconstructsGameStateFromBoardSnapshot() {
        let board = MultiplayerBoardState(
            sequence: 5,
            simulationTick: 9,
            hostID: "host",
            players: [MultiplayerPlayerState(
                id: "player", position: CGPoint(x: 4, y: 5), color: .blue,
                health: 80, weapon: .rifle, powerUps: [.damage], rotation: 0.25
            )],
            zombies: [MultiplayerZombieState(id: "zombie", x: 8, y: 9, health: 30, rotation: 0.5)],
            chests: [MultiplayerChestState(id: "chest", x: 10, y: 11, isOpened: true)],
            powerUps: [MultiplayerPowerUpState(id: "powerup", x: 12, y: 13, type: .range)],
            projectiles: [MultiplayerProjectileState(id: "projectile", ownerID: "player", x: 14, y: 15, angle: 0.75, weapon: .pistol, damage: 30, spawnedTick: 8)],
            killCount: 3,
            isGameOver: true,
            acknowledgedInputSequences: ["player": 6]
        )

        let state = GameStateMultiplayerMapper.gameState(from: board, seed: 42)

        #expect(state.seed == 42)
        #expect(state.tick == 9)
        #expect(state.players[0].position == CGPointValue(x: 4, y: 5))
        #expect(state.players[0].health == 80)
        #expect(state.zombies[0].id == "zombie")
        #expect(state.chests[0].isOpened)
        #expect(state.projectiles[0].spawnedTick == 8)
        #expect(state.score == 3)
        #expect(state.isGameOver)
    }
}
