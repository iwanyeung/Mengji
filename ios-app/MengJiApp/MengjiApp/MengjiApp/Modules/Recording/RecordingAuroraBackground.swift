import SwiftUI

/// 录梦页 Soft Aurora：Metal Shader 与 WebGL 参考一致（`AuroraShader.metal`）。
struct RecordingAuroraBackground: View {
    @ObservedObject var viewModel: RecordingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulseScale: CGFloat = 1

    private var auroraActive: Bool {
        viewModel.auroraMotionAllowed && !viewModel.organizingAuroraCalm
    }

    var body: some View {
        ZStack {
            AppTheme.background

            if auroraActive {
                SoftAuroraMetalBackgroundView(
                    pulseBoost: max(0, pulseScale - 1),
                    isPaused: reduceMotion,
                    motionAllowed: true
                )
            }

            if viewModel.organizingAuroraCalm {
                AppTheme.background.opacity(0.72)
            }
        }
        .onChange(of: viewModel.auroraPulseToken) { _, _ in
            guard auroraActive, !reduceMotion else { return }
            let t = Transaction(animation: nil)
            withTransaction(t) {
                pulseScale = 1.14
            }
            withAnimation(.easeOut(duration: 0.45)) {
                pulseScale = 1
            }
        }
    }
}
