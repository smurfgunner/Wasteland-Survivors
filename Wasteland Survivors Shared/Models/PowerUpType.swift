enum PowerUpType: String, CaseIterable {
    case damage = "Damage"
    case range = "Range"

    var title: String { rawValue.uppercased() }
}
