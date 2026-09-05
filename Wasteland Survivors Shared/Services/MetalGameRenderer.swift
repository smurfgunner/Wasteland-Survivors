import MetalKit
import SpriteKit

struct MetalVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

struct MetalRenderable {
    let position: SIMD2<Float>
    let size: SIMD2<Float>
    let color: SIMD4<Float>
}

@MainActor
final class MetalGameRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var renderables: [MetalRenderable] = []
    private let onFrame: (TimeInterval) -> [MetalRenderable]

    convenience init?(view: MTKView, onFrame: @escaping (TimeInterval) -> [MetalRenderable]) {
        self.init(view: view, onFrame: onFrame, library: view.device?.makeDefaultLibrary())
    }

    init?(view: MTKView, onFrame: @escaping (TimeInterval) -> [MetalRenderable], library: MTLLibrary?) {
        guard let device = view.device,
              let commandQueue = device.makeCommandQueue(),
              let library,
              let vertexFunction = library.makeFunction(name: "metalVertex"),
              let fragmentFunction = library.makeFunction(name: "metalFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.onFrame = onFrame
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        renderables = onFrame(CACurrentMediaTime())
        guard !renderables.isEmpty,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        var vertices: [MetalVertex] = []
        vertices.reserveCapacity(renderables.count * 6)

        for renderable in renderables {
            let minX = renderable.position.x - renderable.size.x / 2
            let maxX = renderable.position.x + renderable.size.x / 2
            let minY = renderable.position.y - renderable.size.y / 2
            let maxY = renderable.position.y + renderable.size.y / 2
            let color = renderable.color

            vertices.append(contentsOf: [
                MetalVertex(position: SIMD2(minX, minY), color: color),
                MetalVertex(position: SIMD2(maxX, minY), color: color),
                MetalVertex(position: SIMD2(minX, maxY), color: color),
                MetalVertex(position: SIMD2(maxX, minY), color: color),
                MetalVertex(position: SIMD2(maxX, maxY), color: color),
                MetalVertex(position: SIMD2(minX, maxY), color: color)
            ])
        }

        encoder.setRenderPipelineState(pipelineState)
        vertices.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            encoder.setVertexBytes(baseAddress, length: bytes.count, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
