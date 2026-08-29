import CoreGraphics
import Foundation

enum MultiplayerInterpolation {
    static func position(
        current: CGPoint,
        target: CGPoint,
        deltaTime: TimeInterval,
        responsiveness: CGFloat
    ) -> CGPoint {
        guard deltaTime > 0, responsiveness > 0 else { return current }
        let factor = min(1, CGFloat(deltaTime) * responsiveness)
        return CGPoint(
            x: current.x + (target.x - current.x) * factor,
            y: current.y + (target.y - current.y) * factor
        )
    }
}
