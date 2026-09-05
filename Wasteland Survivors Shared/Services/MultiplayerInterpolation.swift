import CoreGraphics
import Foundation

enum MultiplayerInterpolation {
    static func angle(
        current: CGFloat,
        target: CGFloat,
        deltaTime: TimeInterval,
        responsiveness: CGFloat
    ) -> CGFloat {
        guard deltaTime > 0, responsiveness > 0 else { return current }
        let twoPi = CGFloat.pi * 2
        var delta = (target - current).truncatingRemainder(dividingBy: twoPi)
        if delta > CGFloat.pi {
            delta -= twoPi
        } else if delta < -CGFloat.pi {
            delta += twoPi
        }
        let factor = min(1, CGFloat(deltaTime) * responsiveness)
        return current + delta * factor
    }

    static func position(
        current: CGPoint,
        target: CGPoint,
        deltaTime: TimeInterval,
        responsiveness: CGFloat
    ) -> CGPoint {
        guard deltaTime > 0, responsiveness > 0 else { return current }
        let correctionDistance = hypot(target.x - current.x, target.y - current.y)
        if correctionDistance > 200 {
            return target
        }
        let factor = min(1, CGFloat(deltaTime) * responsiveness)
        return CGPoint(
            x: current.x + (target.x - current.x) * factor,
            y: current.y + (target.y - current.y) * factor
        )
    }
}
