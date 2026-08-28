enum PowerUpType: String, CaseIterable {
    case damage = "Damage"
    case range = "Range"
    case fireRate = "Fire Rate"

    var title: String { rawValue.uppercased() }
}
