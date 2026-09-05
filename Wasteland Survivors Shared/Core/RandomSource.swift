import CoreGraphics

protocol RandomSource: AnyObject {
    func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat
    func nextInt(upperBound: Int) -> Int
}

final class SystemRandomSource: RandomSource {
    func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range)
    }

    func nextInt(upperBound: Int) -> Int {
        Int.random(in: 0..<upperBound)
    }
}

final class SeededRandomSource: RandomSource {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        let fraction = CGFloat(nextUnitInterval())
        return range.lowerBound + (range.upperBound - range.lowerBound) * fraction
    }

    func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(nextValue() % UInt64(upperBound))
    }

    private func nextUnitInterval() -> Double {
        Double(nextValue() >> 11) / Double(1 << 53)
    }

    private func nextValue() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
