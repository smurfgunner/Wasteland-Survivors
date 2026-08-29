import CoreGraphics
import Foundation
import Testing
@testable import Wasteland_Survivors

@Suite("Multiplayer Mode Fixtures")
struct MultiplayerModeFixtureTests {
    @Test("Offline, local, and server-stub fixtures share one deterministic simulation contract")
    func allSupportedModesUseTheSameSimulationContract() throws {
        let initial = GameState.initial(seed: 12_345, playerID: "player")
        let inputs = (1...120).map { tick in
            PlayerInput(
                playerID: "player",
                sequence: UInt64(tick),
                movement: CGPointValue(x: tick.isMultiple(of: 2) ? 1 : -1, y: 0.25),
                aimAngle: Double(tick) / 10,
                wantsToAttack: tick.isMultiple(of: 30)
            )
        }

        let offline = run(initial: initial, inputs: inputs)
        let localHost = run(initial: initial, inputs: try inputs.map(roundTripLocally))
        let serverStub = run(initial: initial, inputs: try ServerTransportStub().relay(inputs))

        #expect(offline == localHost)
        #expect(localHost == serverStub)
    }

    @Test("Packet hold, duplicate, drop, and release preserve the ordered server contract")
    func packetManipulationPreservesOrderedServerContract() throws {
        let inputs = (1...12).map {
            PlayerInput(
                playerID: "player",
                sequence: UInt64($0),
                movement: CGPointValue(x: Double($0.isMultiple(of: 2) ? 1 : -1), y: 0),
                aimAngle: Double($0),
                wantsToAttack: $0.isMultiple(of: 3)
            )
        }
        let delivered = try ServerTransportStub().relay(inputs, manipulate: true)

        #expect(delivered == inputs)
        #expect(run(initial: .initial(seed: 9, playerID: "player"), inputs: delivered)
            == run(initial: .initial(seed: 9, playerID: "player"), inputs: inputs))
    }

    private func run(initial: GameState, inputs: [PlayerInput]) -> GameState {
        var driver = FixedTickSimulationDriver(initialState: initial)
        for input in inputs {
            _ = driver.advance(elapsedTime: 1.0 / 60.0, inputs: [input])
        }
        return driver.state
    }

    private func roundTripLocally(_ input: PlayerInput) throws -> PlayerInput {
        let wire = try MultiplayerWireMessage.playerInput(MultiplayerPlayerInput(
            playerID: input.playerID,
            sequence: input.sequence,
            movement: CGVector(dx: input.movement.x, dy: input.movement.y),
            aimAngle: input.aimAngle,
            wantsToAttack: input.wantsToAttack,
            wantsToOpenChestID: input.wantsToOpenChestID,
            wantsToCollectPowerUpID: input.wantsToCollectPowerUpID
        )).encoded()
        guard case let .playerInput(decoded) = try MultiplayerWireMessage.decode(wire) else {
            throw FixtureError.invalidWireMessage
        }
        return PlayerInput(
            playerID: decoded.playerID,
            sequence: decoded.sequence,
            movement: CGPointValue(x: Double(decoded.movement.dx), y: Double(decoded.movement.dy)),
            aimAngle: decoded.aimAngle,
            wantsToAttack: decoded.wantsToAttack,
            wantsToOpenChestID: decoded.wantsToOpenChestID,
            wantsToCollectPowerUpID: decoded.wantsToCollectPowerUpID
        )
    }
}

private struct ServerTransportStub {
    func relay(_ inputs: [PlayerInput], manipulate: Bool = false) throws -> [PlayerInput] {
        var packets = try inputs.map { input in
            let data = try JSONEncoder().encode(input)
            return try JSONDecoder().decode(PlayerInput.self, from: data)
        }
        guard manipulate else { return packets }

        let held = packets.filter { (4...6).contains($0.sequence) }.reversed()
        packets.removeAll { (4...6).contains($0.sequence) }
        packets.append(contentsOf: held)
        packets.insert(packets[3], at: 0)
        let retransmitted = packets.remove(at: 1)
        packets.append(retransmitted)

        var uniqueBySequence: [UInt64: PlayerInput] = [:]
        for packet in packets {
            uniqueBySequence[packet.sequence] = packet
        }
        return uniqueBySequence.values.sorted { $0.sequence < $1.sequence }
    }
}

private enum FixtureError: Error {
    case invalidWireMessage
}
