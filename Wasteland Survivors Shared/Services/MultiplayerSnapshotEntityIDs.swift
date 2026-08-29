enum MultiplayerSnapshotEntityIDs {
    static func zombie(_ node: ZombieNode) -> String { node.multiplayerID }
    static func chest(_ node: ChestNode) -> String { node.multiplayerID }
    static func powerUp(_ node: PowerUpNode) -> String { node.multiplayerID }
    static func projectile(_ node: ProjectileNode) -> String { node.multiplayerID }
}
