import MetalKit
import SwiftUI
import UIKit

private struct SpotAuroraUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var amplitude: Float
    var blend: Float
    var speed: Float
    var colorStop0: SIMD4<Float>
    var colorStop1: SIMD4<Float>
    var colorStop2: SIMD4<Float>
    var backgroundRGB: SIMD4<Float>
}

private final class SpotAuroraMTKView: MTKView {
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = contentScaleFactor
        let newSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        guard newSize != drawableSize else { return }
        drawableSize = newSize
    }
}

/// ReactBits 风格「光斑极光」：横向色带 + simplex 噪声塑形。
struct SpotAuroraMetalBackgroundView: UIViewRepresentable {
    struct Config {
        var amplitude: Float = 1.0
        var blend: Float = 0.5
        var speed: Float = 1.0
        var colorStop0: SIMD4<Float> = SIMD4<Float>(0x8F / 255, 0xA0 / 255, 0x2E / 255, 0)
        var colorStop1: SIMD4<Float> = SIMD4<Float>(0xD4 / 255, 0xFF / 255, 0x33 / 255, 0)
        var colorStop2: SIMD4<Float> = SIMD4<Float>(0x8F / 255, 0xA0 / 255, 0x2E / 255, 0)
    }

    var isPaused: Bool
    var motionAllowed: Bool
    var config: Config = Config()

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        guard motionAllowed, let device = MTLCreateSystemDefaultDevice() else {
            let v = UIView()
            v.backgroundColor = UIColor(AppTheme.background)
            v.isUserInteractionEnabled = false
            return v
        }

        let view = SpotAuroraMTKView(frame: .zero, device: device)
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0x0D / 255, green: 0x0C / 255, blue: 0x0F / 255, alpha: 1)
        view.isOpaque = true
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = isPaused ? 1 : 60
        view.isPaused = false
        view.delegate = context.coordinator
        context.coordinator.freezeTime = isPaused
        context.coordinator.config = config
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        view.layer.zPosition = -1
        context.coordinator.setup(device: device, mtkView: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.freezeTime = isPaused
        context.coordinator.config = config
        if let mtk = uiView as? SpotAuroraMTKView {
            mtk.preferredFramesPerSecond = isPaused ? 1 : 60
        }
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var startTime: CFTimeInterval = CACurrentMediaTime()
        var freezeTime: Bool = false
        var config: Config = Config()

        func setup(device: MTLDevice, mtkView: MTKView) {
            commandQueue = device.makeCommandQueue()
            startTime = CACurrentMediaTime()

            guard let library = try? device.makeDefaultLibrary(bundle: Bundle.main) else { return }
            guard let vfn = library.makeFunction(name: "spotAuroraVertex"),
                  let ffn = library.makeFunction(name: "spotAuroraFragment") else { return }

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

            device.makeRenderPipelineState(descriptor: desc) { [weak self] state, _ in
                DispatchQueue.main.async { self?.pipeline = state }
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipeline,
                  let commandQueue,
                  let drawable = view.currentDrawable,
                  let rpd = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }

            let w = max(Float(view.drawableSize.width), 1)
            let h = max(Float(view.drawableSize.height), 1)
            let t = freezeTime ? 0 : Float(CACurrentMediaTime() - startTime)

            var u = SpotAuroraUniforms(
                resolution: SIMD2<Float>(w, h),
                time: t,
                amplitude: config.amplitude,
                blend: config.blend,
                speed: config.speed,
                colorStop0: config.colorStop0,
                colorStop1: config.colorStop1,
                colorStop2: config.colorStop2,
                backgroundRGB: SIMD4<Float>(0x0D / 255, 0x0C / 255, 0x0F / 255, 0)
            )

            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&u, length: MemoryLayout<SpotAuroraUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
