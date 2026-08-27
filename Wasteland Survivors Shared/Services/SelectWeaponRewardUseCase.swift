import SpriteKit

final class SelectWeaponRewardUseCase {
    func execute(excluding currentWeapon: WeaponType) -> WeaponType {
        let availableWeapons = WeaponType.allCases.filter { $0 != currentWeapon }
        return availableWeapons.randomElement() ?? .shotgun
    }
}
