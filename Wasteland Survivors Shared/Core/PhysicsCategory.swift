import Foundation

enum PhysicsCategory {
    static let none: UInt32 = 0
    static let player: UInt32 = 1 << 0
    static let zombie: UInt32 = 1 << 1
    static let projectile: UInt32 = 1 << 2
    static let chest: UInt32 = 1 << 3
    static let meleeHitbox: UInt32 = 1 << 4
    static let powerUp: UInt32 = 1 << 5
}
