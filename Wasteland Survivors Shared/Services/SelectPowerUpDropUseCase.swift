final class SelectPowerUpDropUseCase {
    private let randomSource: RandomSource

    init(randomSource: RandomSource = SystemRandomSource()) {
        self.randomSource = randomSource
    }

    func execute() -> PowerUpType? {
        guard randomSource.nextInt(upperBound: 10) == 0 else { return nil }
        let powerUps = PowerUpType.allCases
        return powerUps[randomSource.nextInt(upperBound: powerUps.count)]
    }
}
