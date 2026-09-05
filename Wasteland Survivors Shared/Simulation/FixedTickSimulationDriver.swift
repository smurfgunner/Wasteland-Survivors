import Foundation

struct FixedTickSimulationDriver {
    private let simulation: GameSimulation
    private let tickDuration: TimeInterval
    private var accumulatedTime: TimeInterval = 0

    private(set) var state: GameState

    init(
        initialState: GameState,
        simulation: GameSimulation = GameSimulation(),
        tickRate: Double = GameSimulation.Configuration.standard.tickRate
    ) {
        precondition(tickRate > 0)
        self.state = initialState
        self.simulation = simulation
        tickDuration = 1 / tickRate
    }

    mutating func advance(
        elapsedTime: TimeInterval,
        inputs: [PlayerInput]
    ) -> [SimulationStep] {
        guard elapsedTime > 0 else { return [] }

        accumulatedTime += elapsedTime
        var steps: [SimulationStep] = []
        var isFirstStep = true

        // The epsilon prevents a mathematically complete tick from being
        // lost because elapsed-time values such as 1/60 cannot be represented
        // exactly in binary floating point.
        let maximumCatchUpSteps = elapsedTime > 5 ? 15 : Int.max
        while accumulatedTime + 1e-9 >= tickDuration && steps.count < maximumCatchUpSteps {
            accumulatedTime -= tickDuration
            let inputsForTick = isFirstStep ? inputs : inputs.map {
                PlayerInput(
                    playerID: $0.playerID,
                    sequence: $0.sequence,
                    movement: $0.movement,
                    aimAngle: $0.aimAngle,
                    wantsToAttack: false,
                    wantsToOpenChestID: nil,
                    wantsToCollectPowerUpID: nil
                )
            }
            let step = simulation.advance(
                state,
                inputs: inputsForTick,
                tick: state.tick + 1
            )
            state = step.state
            steps.append(step)
            isFirstStep = false
        }

        // A long pause should resynchronize on the next frame instead of replaying
        // an unbounded backlog of simulation ticks.
        if steps.count == 15 {
            accumulatedTime = 0
        }
        return steps
    }

    mutating func replaceState(_ state: GameState) {
        self.state = state
    }
}
