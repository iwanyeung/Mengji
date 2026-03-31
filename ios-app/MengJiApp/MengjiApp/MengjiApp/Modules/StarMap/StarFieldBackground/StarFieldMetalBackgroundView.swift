//
//  StarFieldMetalBackgroundView.swift
//  潜意识星图：全屏 Metal 飞行星野（StarFieldShader.metal）。
//

import MetalKit
import QuartzCore
import SwiftUI
import UIKit

private struct StarFieldUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var flightSpeed: Float
    var primary: SIMD4<Float>
    var background: SIMD4<Float>
    var accent: SIMD4<Float>
    var maxSteps: Int32
    var drawDistance: Float
    var starThreshold: Float
    var nebulaLastIndex: Int32
}

private final class StarFieldMTKView: MTKView {
    var drawableScale: CGFloat = 0.5

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = contentScaleFactor * drawableScale
        let newSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        // 尺寸未变时跳过，避免重复分配 IOSurface 触发 IOSurfaceClientSetSurfaceNotify failed
        guard newSize != drawableSize else { return }
        drawableSize = newSize
    }
}

struct StarFieldMetalBackgroundView: UIViewRepresentable {
    var config: StarfieldMetalConfig
    var isPaused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(config: config)
    }

    func makeUIView(context: Context) -> UIView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            let v = UIView()
            v.backgroundColor = UIColor(red: 0x0D / 255, green: 0x0C / 255, blue: 0x0F / 255, alpha: 1)
            return v
        }

        let view = StarFieldMTKView(frame: .zero, device: device)
        view.framebufferOnly = false
        view.clearColor = MTLClearColor(red: 0.05, green: 0.047, blue: 0.059, alpha: 1)
        view.isOpaque = true
        view.enableSetNeedsDisplay = false
        view.drawableScale = 0.5
        view.preferredFramesPerSecond = config.preferredFPS
        view.isPaused = isPaused
        view.delegate = context.coordinator
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.setup(device: device, mtkView: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let mtk = uiView as? StarFieldMTKView else { return }
        mtk.preferredFramesPerSecond = config.preferredFPS
        mtk.isPaused = isPaused
        context.coordinator.config = config
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var startTime: CFTimeInterval = CACurrentMediaTime()
        var config: StarfieldMetalConfig

        init(config: StarfieldMetalConfig) {
            self.config = config
        }

        func setup(device: MTLDevice, mtkView: MTKView) {
            commandQueue = device.makeCommandQueue()
            startTime = CACurrentMediaTime()

            guard let library = try? device.makeDefaultLibrary(bundle: Bundle.main) else { return }
            let vfn = library.makeFunction(name: "starFieldVertex")
            let ffn = library.makeFunction(name: "starFieldFragment")
            guard let vfn, let ffn else { return }

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
            let t = Float(CACurrentMediaTime() - startTime)

            var u = StarFieldUniforms(
                resolution: SIMD2<Float>(w, h),
                time: t,
                flightSpeed: config.flightSpeed,
                primary: Self.themePrimary,
                background: Self.themeBackground,
                accent: Self.themeAccent,
                maxSteps: config.maxSteps,
                drawDistance: config.drawDistance,
                starThreshold: config.starThreshold,
                nebulaLastIndex: config.nebulaLastIndex
            )

            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&u, length: MemoryLayout<StarFieldUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        private static let themePrimary = SIMD4<Float>(0xD4 / 255, 0xFF / 255, 0x33 / 255, 0)
        private static let themeBackground = SIMD4<Float>(0x0D / 255, 0x0C / 255, 0x0F / 255, 0)
        private static let themeAccent = SIMD4<Float>(0xFF / 255, 0x33 / 255, 0x66 / 255, 0)
    }
}
