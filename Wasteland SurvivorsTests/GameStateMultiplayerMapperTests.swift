import Testing
@testable import Wasteland_Survivors

@Suite("Multiplayer State Transfer")
struct GameStateMultiplayerMapperTests {
    @Test("Initialization transfers the state required to reconstruct the simulation")
    func initializationTransfersRequiredState() {
        let payload = MultiplayerInitializationPayload(
            sessionID: "match",
            sequence: 11,
            simulationTick: 12,
            seed: 7,
            hostID: "host",
            players: [.init(id: "player", spawnPosition: .init(x: 12, y: -8), facing: 0.5)],
            zombies: [.init(id: "zombie-1", position: .init(x: 30, y: 40), health: 18)]
        )

        #expect(payload.sequence == 11)
        #expect(payload.seed == 7)
        #expect(payload.players[0].spawnPosition == .init(x: 12, y: -8))
        #expect(payload.zombies[0].health == 18)
        #expect(payload.isFullCurrentState)
        #expect(payload.requiresEventHistory == false)
    }

    @Test("Recovery transfers current entity sets and score without event history")
    func recoveryTransfersCurrentState() {
        let payload = MultiplayerRecoveryPayload(
            sessionID: "match",
            firstSequence: 4,
            lastSequence: 11,
            simulationTick: 12,
            players: [.init(id: "player", spawnPosition: .zero)],
            zombies: [.init(id: "zombie-1", position: .zero, health: 18)],
            activeChests: ["chest-1"],
            activePowerUps: ["power-up-1"],
            score: 4,
            playerTargets: [:],
            zombieTargets: [:],
            equipment: ["player": .rifle],
            removedEntities: ["zombie-2"],
            playerDeaths: []
        )

        #expect(payload.activePlayers == ["player"])
        #expect(payload.activeZombies == ["zombie-1"])
        #expect(payload.activeChests == ["chest-1"])
        #expect(payload.score == 4)
        #expect(payload.requiresEventHistory == false)
    }

    @Test("State transfer values round trip through the event wire format")
    func stateTransferRoundTrips() throws {
        let message = MultiplayerWireMessage.initialization(.init(
            sessionID: "match",
            sequence: 1,
            simulationTick: 2,
            seed: 3,
            hostID: "host",
            players: [.init(id: "player", spawnPosition: .zero)],
            zombies: []
        ))

        #expect(try MultiplayerWireMessage.decode(message.encoded()) == message)
    }

    @Test("Zombie damage maps the exact entity when identifiers share suffixes")
    func zombieDamageMapsExactIdentifier() {
        // Given two zombies whose identifiers overlap at a delimiter boundary.
        let state = makeState(
            players: [.init(id: "host", position: .zero, rotation: 0, health: 100, weapon: .pistol, powerUps: [])],
            zombies: [
                .init(id: "1", position: .zero, rotation: 0, health: 80),
                .init(id: "zombie-1", position: .zero, rotation: 0, health: 40)
            ]
        )

        // When the simulation event for zombie-1 is mapped to replication.
        let event = MultiplayerSyncEvent(
            gameplayEvent: .zombieDamaged(id: "damage-10-zombie-1", amount: 10),
            sourcePlayerID: "host",
            state: state
        )

        // Then the exact zombie and its authoritative health are preserved.
        #expect(event == .zombieHealthChanged(
            zombieID: "zombie-1",
            damage: 10,
            health: 40,
            sourcePlayerID: "host"
        ))
    }

    @Test("Player damage maps the exact entity when identifiers overlap")
    func playerDamageMapsExactIdentifier() {
        // Given players whose identifiers overlap inside the encoded event ID.
        let state = makeState(players: [
            .init(id: "client", position: .zero, rotation: 0, health: 90, weapon: .pistol, powerUps: []),
            .init(id: "client-2", position: .zero, rotation: 0, health: 55, weapon: .pistol, powerUps: [])
        ])

        // When damage for client-2 is mapped.
        let event = MultiplayerSyncEvent(
            gameplayEvent: .playerDamaged(id: "damage-zombie-1-client-2-10", amount: 12),
            sourcePlayerID: "host",
            state: state
        )

        // Then client-2 receives its own authoritative health.
        #expect(event == .playerDamaged(
            playerID: "client-2",
            damage: 12,
            health: 55,
            sourceID: "zombie-1"
        ))
    }

    @Test("Player damage preserves the attacking zombie identity")
    func playerDamagePreservesZombieSource() {
        // Given authoritative damage produced by a specific zombie.
        let state = makeState(players: [
            .init(id: "client", position: .zero, rotation: 0, health: 88, weapon: .pistol, powerUps: [])
        ])

        // When the event is mapped for replication by the host.
        let event = MultiplayerSyncEvent(
            gameplayEvent: .playerDamaged(id: "damage-zombie-7-client-10", amount: 12),
            sourcePlayerID: "host",
            state: state
        )

        // Then the damage source remains the zombie, not the forwarding host.
        #expect(event == .playerDamaged(
            playerID: "client",
            damage: 12,
            health: 88,
            sourceID: "zombie-7"
        ))
    }

    private func makeState(
        players: [GamePlayerState],
        zombies: [GameZombieState] = []
    ) -> GameState {
        GameState(
            seed: 42,
            tick: 10,
            players: players,
            zombies: zombies,
            chests: [],
            powerUps: [],
            projectiles: [],
            score: 0,
            isGameOver: false
        )
    }
}
