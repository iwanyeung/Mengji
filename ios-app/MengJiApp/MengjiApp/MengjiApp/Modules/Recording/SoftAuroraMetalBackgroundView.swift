//
//  SoftAuroraMetalBackgroundView.swift
//  录梦页：Metal 全屏极光（AuroraShader.metal），与 WebGL Soft Aurora 数学对齐。
//

import MetalKit
import SwiftUI
import UIKit

private struct AuroraUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var speed: Float
    var scale: Float
    var brightness: Float
    var color1: SIMD4<Float>
    var color2: SIMD4<Float>
    var noiseFreq: Float
    var noiseAmp: Float
    var bandHeight: Float
    var bandSpread: Float
    var octaveDecay: Float
    var layerOffset: Float
    var colorSpeed: Float
    var pulseBoost: Float
    var backgroundRGB: SIMD4<Float>
}

private final class AuroraMTKView: MTKView {
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = contentScaleFactor
        let newSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        guard newSize != drawableSize else { return }
        drawableSize = newSize
    }
}

/// 全屏极光 Shader；`motionAllowed == false` 时不创建 Metal，仅深色底。
struct SoftAuroraMetalBackgroundView: UIViewRepresentable {
    struct Config {
        var speed: Float = 0.6
        var scale: Float = 1.5
        var brightness: Float = 0.92
        var noiseFreq: Float = 2.5
        var noiseAmp: Float = 1.0
        var bandHeight: Float = 0.5
        var bandSpread: Float = 1.0
        var octaveDecay: Float = 0.1
        var layerOffset: Float = 0
        var colorSpeed: Float = 1.0
    }

    var pulseBoost: CGFloat
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

        let view = AuroraMTKView(frame: .zero, device: device)
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
        context.coordinator.pulseBoost = Float(max(0, pulseBoost))
        context.coordinator.freezeTime = isPaused
        context.coordinator.config = config
        if let mtk = uiView as? AuroraMTKView {
            mtk.preferredFramesPerSecond = isPaused ? 1 : 60
        }
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var startTime: CFTimeInterval = CACurrentMediaTime()
        var pulseBoost: Float = 0
        var config: Config = Config()
        /// 与 `accessibilityReduceMotion` 对应：时间冻结在 0，避免 MTKView pause 导致黑屏
        var freezeTime: Bool = false

        func setup(device: MTLDevice, mtkView: MTKView) {
            commandQueue = device.makeCommandQueue()
            startTime = CACurrentMediaTime()

            guard let library = try? device.makeDefaultLibrary(bundle: Bundle.main) else { return }
            guard let vfn = library.makeFunction(name: "auroraVertex"),
                  let ffn = library.makeFunction(name: "auroraFragment") else { return }

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

            // 异步编译：不阻塞主线程，pipeline 就绪前 draw() 里的 guard 会直接跳过（显示纯色底）
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

            var u = AuroraUniforms(
                resolution: SIMD2<Float>(w, h),
                time: t,
                speed: config.speed,
                scale: config.scale,
                brightness: config.brightness,
                color1: Self.themePrimary,
                color2: Self.themeSecondary,
                noiseFreq: config.noiseFreq,
                noiseAmp: config.noiseAmp,
                bandHeight: config.bandHeight,
                bandSpread: config.bandSpread,
                octaveDecay: config.octaveDecay,
                layerOffset: config.layerOffset,
                colorSpeed: config.colorSpeed,
                pulseBoost: pulseBoost,
                backgroundRGB: Self.themeBackground
            )

            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&u, length: MemoryLayout<AuroraUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        private static let themePrimary = SIMD4<Float>(0xD4 / 255, 0xFF / 255, 0x33 / 255, 0)
        /// 第二层：更暗的酸黄（与主色同系、压低明度），避免强调色洋红跳脱
        private static let themeSecondary = SIMD4<Float>(0x8F / 255, 0xA0 / 255, 0x2E / 255, 0)
        private static let themeBackground = SIMD4<Float>(0x0D / 255, 0x0C / 255, 0x0F / 255, 0)
    }
}
