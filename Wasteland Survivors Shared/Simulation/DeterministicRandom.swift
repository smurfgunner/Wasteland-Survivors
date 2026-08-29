import Foundation

struct DeterministicRandom: Sendable {
    static func value(
        seed: UInt64,
        entityID: String,
        tick: UInt64,
        purpose: String
    ) -> Double {
        var hash = seed ^ 14_695_981_039_346_656_037
        for byte in entityID.utf8 {
            hash ^= UInt64(byte)
            hash &*= 10_951_162_821_1
        }
        for byte in purpose.utf8 {
            hash ^= UInt64(byte)
            hash &*= 10_951_162_821_1
        }
        for byte in withUnsafeBytes(of: tick.bigEndian, Array.init) {
            hash ^= UInt64(byte)
            hash &*= 10_951_162_821_1
        }

        return Double(hash >> 11) / Double(1 << 53)
    }

    static func integer(
        seed: UInt64,
        entityID: String,
        tick: UInt64,
        purpose: String,
        upperBound: Int
    ) -> Int {
        precondition(upperBound > 0)
        return Int(value(seed: seed, entityID: entityID, tick: tick, purpose: purpose) * Double(upperBound))
    }
}
