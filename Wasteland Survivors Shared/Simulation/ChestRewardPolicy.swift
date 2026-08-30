import Foundation

enum ChestRewardPolicy {
    static func select(
        seed: UInt64,
        chestID: String,
        excluding currentWeapon: WeaponType
    ) -> WeaponType {
        let availableWeapons = WeaponType.allCases
            .filter { $0 != currentWeapon }
            .sorted { $0.rawValue < $1.rawValue }
        guard !availableWeapons.isEmpty else { return currentWeapon }

        var hash = seed
        for byte in chestID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return availableWeapons[Int(hash % UInt64(availableWeapons.count))]
    }
}
