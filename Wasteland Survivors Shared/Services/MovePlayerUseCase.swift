import SpriteKit

final class MovePlayerUseCase {
    func execute(player: PlayerNode, direction: CGVector, deltaTime: TimeInterval) {
        player.move(in: direction, dt: deltaTime)
    }
}
