import CoreGraphics
import Foundation
import SpriteKit

final class FixedRandomSource: RandomSource {
    func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        (range.lowerBound + range.upperBound) / 2
    }

    func nextInt(upperBound: Int) -> Int {
        0
    }
}

final class NoDropRandomSource: RandomSource {
    func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        range.upperBound
    }

    func nextInt(upperBound: Int) -> Int {
        upperBound - 1
    }
}

final class TestClock {
    var now: TimeInterval = 0
}

struct RenderedPixelSnapshot: Equatable {
    let width: Int
    let height: Int
    let pixelHash: UInt64

    init(texture: SKTexture) throws {
        let image = texture.cgImage()
        guard let providerData = image.dataProvider?.data else {
            throw RenderedPixelSnapshotError.missingImageData
        }

        width = image.width
        height = image.height
        let data = providerData as Data
        pixelHash = data.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

enum RenderedPixelSnapshotError: Error {
    case missingImageData
}
