import SpriteKit

enum WeaponType: String, CaseIterable, Codable, Sendable {
    case pistol = "Pistol"
    case shotgun = "Shotgun"
    case rifle = "Assault Rifle"
    case sword = "Combat Machete"
    case spear = "Wasteland Spear"

    var category: WeaponCategory {
        switch self {
        case .pistol, .shotgun, .rifle:
            return .ranged
        case .sword, .spear:
            return .melee
        }
    }

    var damage: CGFloat {
        switch self {
        case .pistol: return 30
        case .shotgun: return 22
        case .rifle: return 18
        case .sword: return 60
        case .spear: return 48
        }
    }

    var range: CGFloat {
        switch self {
        case .pistol: return 280
        case .shotgun: return 220
        case .rifle: return 340
        case .sword: return 85
        case .spear: return 120
        }
    }

    var fireRate: TimeInterval {
        switch self {
        case .pistol: return 0.35
        case .shotgun: return 0.70
        case .rifle: return 0.16
        case .sword: return 0.45
        case .spear: return 0.38
        }
    }

    var color: SKColor {
        switch self {
        case .pistol: return .systemYellow
        case .shotgun: return .systemOrange
        case .rifle: return .systemRed
        case .sword: return .systemCyan
        case .spear: return .systemTeal
        }
    }
}
