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
}
