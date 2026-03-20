import SwiftUI

struct ComicResultView: View {
    var artifact: ComicArtifact?

    @Environment(\.dismiss) private var dismiss

    /// 竖向条漫占位：高/宽比（中间区域在该比例内 `aspectFit` 居中铺满可用空间）
    private let stripAspectHeightOverWidth: CGFloat = 2.12

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("今晚的梦，在这儿了")
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .foregroundColor(AppTheme.text)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                GeometryReader { geometry in
                    let maxW = geometry.size.width
                    let maxH = geometry.size.height
                    let stripW = min(maxW, maxH / stripAspectHeightOverWidth)
                    let stripH = stripW * stripAspectHeightOverWidth

                    framedStripMockStrip
                        .frame(width: stripW, height: stripH)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .layoutPriority(1)

                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "当前为占位预览。接入真实生成能力后，这里会展示根据你的梦生成的竖向分镜画面；布局可能因内容略有不同。"
                            )
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundColor(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                            if let artifact {
                                Text(artifact.previewDescription)
                                    .font(.system(size: 13, weight: .regular, design: .default))
                                    .foregroundColor(AppTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("关于这张作品")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundColor(AppTheme.text)
                    }
                    .tint(AppTheme.primaryColor)

                    actions
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("四格已生成（Mock）")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var framedStripMockStrip: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                AppTheme.surface

                GeometryReader { geo in
                    let h = geo.size.height
                    let fractions: [CGFloat] = [0.22, 0.30, 0.26, 0.22]
                    let gutter: CGFloat = 2
                    let totalGutter = gutter * CGFloat(max(0, fractions.count - 1))
                    let contentH = max(0, h - totalGutter)
                    VStack(spacing: gutter) {
                        ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
                            stripPanel(index: index + 1)
                                .frame(height: contentH * fraction)
                        }
                    }
                }

                ComicFilmGrainOverlay()
                    .opacity(0.55)
                    .allowsHitTesting(false)

                Rectangle()
                    .strokeBorder(AppTheme.muted.opacity(0.55), lineWidth: 1)
            }
            .clipped()

            Text("预览")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.background)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.muted.opacity(0.92))
                .padding(10)
        }
    }

    private func stripPanel(index: Int) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.background,
                            index % 2 == 1
                                ? AppTheme.primaryColor.opacity(0.16)
                                : AppTheme.accent.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("\(index)")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.text.opacity(0.22))
                .padding(8)
        }
    }

    private var actions: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Text("稍后在潜意识星图里再看")
                Spacer()
                Image(systemName: "point.topleft.down.curvedto.point.filled.bottomright.up")
            }
            .font(.system(size: 14, weight: .semibold, design: .default))
            .foregroundColor(AppTheme.background)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(AppTheme.primaryColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 轻噪点（确定性 pattern，避免 random 导致重绘闪烁）

private struct ComicFilmGrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 5
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    let phase = sin(x * 0.08 + y * 0.11) * 0.5 + 0.5
                    let opacity = 0.018 + phase * 0.035
                    let dot = CGRect(x: x, y: y, width: 1.15, height: 1.15)
                    context.fill(
                        Path(ellipseIn: dot),
                        with: .color(Color.white.opacity(opacity))
                    )
                    y += step
                }
                x += step
            }
        }
        .blendMode(.overlay)
    }
}
