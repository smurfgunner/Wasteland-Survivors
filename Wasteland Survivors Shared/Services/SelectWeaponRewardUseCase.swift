import SpriteKit

final class SelectWeaponRewardUseCase {
    private let randomSource: RandomSource

    init(randomSource: RandomSource = SystemRandomSource()) {
        self.randomSource = randomSource
    }

    func execute(excluding currentWeapon: WeaponType) -> WeaponType {
        let availableWeapons = WeaponType.allCases.filter { $0 != currentWeapon }
        guard !availableWeapons.isEmpty else { return .shotgun }
        return availableWeapons[randomSource.nextInt(upperBound: availableWeapons.count)]
    }
}
