import SwiftUI

// MARK: - 布局常量（与结果页条漫一致）

enum ComicStripLayout {
    static let panelCount = 4
    static let gutter: CGFloat = 2
    /// 单格固定 16:9（高 / 宽）。生成端也按 16:9 出图时，scaledToFill 不会裁切，完整平铺。
    static let panelHeightOverWidth: CGFloat = 9.0 / 16.0
    /// 与结果页条漫区域左右留白一致
    static let horizontalPadding: CGFloat = 24

    /// 四格之间的总间隙高度
    static var totalGutter: CGFloat {
        gutter * CGFloat(max(0, panelCount - 1))
    }

    /// 整条 高/宽（不含间隙的近似比例，供需要估算处使用）
    static var aspectHeightOverWidth: CGFloat {
        panelHeightOverWidth * CGFloat(panelCount)
    }

    /// 尺寸非法（首帧 GeometryReader 为 0 等）时返回 nil，避免负/非有限 frame。
    /// 高度受限时优先保证每格严格 16:9，整条按可用区域取最大宽度并居中。
    static func stripDimensions(maxWidth: CGFloat, maxHeight: CGFloat) -> (width: CGFloat, height: CGFloat)? {
        guard maxWidth.isFinite, maxHeight.isFinite, maxWidth > 0, maxHeight > 0 else {
            return nil
        }
        let panelsHeightPerWidth = panelHeightOverWidth * CGFloat(panelCount)
        let widthLimitedByHeight = (maxHeight - totalGutter) / panelsHeightPerWidth
        let stripW = min(maxWidth, widthLimitedByHeight)
        guard stripW.isFinite, stripW > 0 else { return nil }
        let stripH = stripW * panelsHeightPerWidth + totalGutter
        guard stripH.isFinite, stripH > 0 else { return nil }
        return (stripW, stripH)
    }
}

// MARK: - 条漫内容（结果页与全屏共用）

struct ComicStripContentView: View {
    var artifact: ComicArtifact?
    var imageQuality: ComicImageQuality = .preview
    var fallbackURLs: [URL] = []
    /// 全屏：先 preview 再清晰档模糊→清晰
    var useProgressiveLoading: Bool = false
    /// 全屏关闭颗粒噪点以减轻 Canvas 开销
    var showsFilmGrain: Bool = true

    private var panels: [ComicPanelDisplay] {
        if let artifact {
            let resolved = artifact.panels(for: imageQuality)
            if !resolved.isEmpty { return resolved }
        }
        return fallbackURLs.enumerated().map { index, url in
            ComicPanelDisplay(index: index, remoteURL: url, localRelativePath: nil)
        }
    }

    var body: some View {
        ZStack {
            AppTheme.surface

            GeometryReader { geo in
                let h = geo.size.height
                let gutter = ComicStripLayout.gutter
                let panelCount = ComicStripLayout.panelCount
                let totalGutter = gutter * CGFloat(max(0, panelCount - 1))
                let contentH = max(0, h - totalGutter)
                let panelHeight = contentH / CGFloat(panelCount)
                VStack(spacing: gutter) {
                    ForEach(0..<panelCount, id: \.self) { index in
                        comicStripPanel(index: index + 1)
                            .frame(maxWidth: .infinity)
                            .frame(height: panelHeight)
                            .clipped()
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }

            if showsFilmGrain {
                ComicFilmGrainOverlay()
                    .opacity(0.55)
                    .allowsHitTesting(false)
            }

            Rectangle()
                .strokeBorder(AppTheme.muted.opacity(0.55), lineWidth: 1)
        }
        .clipped()
    }

    private var previewPanelsForProgressive: [ComicPanelDisplay] {
        guard useProgressiveLoading, let artifact else { return [] }
        return artifact.panels(for: .preview)
    }

    private var sharpPanelsForProgressive: [ComicPanelDisplay] {
        guard useProgressiveLoading, let artifact else { return [] }
        return artifact.panels(for: .fullscreen)
    }

    private func comicStripPanel(index: Int) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if useProgressiveLoading,
               previewPanelsForProgressive.indices.contains(index - 1),
               sharpPanelsForProgressive.indices.contains(index - 1) {
                ComicPanelProgressiveImage(
                    previewPanel: previewPanelsForProgressive[index - 1],
                    sharpPanel: sharpPanelsForProgressive[index - 1]
                )
            } else if panels.indices.contains(index - 1) {
                ComicPanelImage(panel: panels[index - 1])
            } else {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if panels.isEmpty {
                Text("\(index)")
                    .font(AppTheme.capsFont(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.text.opacity(0.22))
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
    }
}

// MARK: - 轻噪点（确定性 pattern）

struct ComicFilmGrainOverlay: View {
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

// MARK: - 全屏双指缩放（纯 SwiftUI，与结果页同布局）

private struct ComicStripZoomableStrip: View {
    var artifact: ComicArtifact?
    var imageQuality: ComicImageQuality = .fullscreen
    var useProgressiveLoading: Bool = false
    var fallbackURLs: [URL] = []
    var stripWidth: CGFloat
    var stripHeight: CGFloat

    @State private var zoomScale: CGFloat = 1
    @State private var steadyZoomScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 4

    var body: some View {
        ComicStripContentView(
            artifact: artifact,
            imageQuality: imageQuality,
            fallbackURLs: fallbackURLs,
            useProgressiveLoading: useProgressiveLoading,
            showsFilmGrain: false
        )
            .frame(width: stripWidth, height: stripHeight)
            .scaleEffect(zoomScale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(magnifyGesture)
            .simultaneousGesture(panGesture)
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomScale = min(maxZoom, max(minZoom, steadyZoomScale * value))
            }
            .onEnded { _ in
                steadyZoomScale = zoomScale
                if zoomScale <= minZoom + 0.01 {
                    resetZoom()
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale > minZoom + 0.01 else { return }
                offset = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                steadyOffset = offset
            }
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoomScale = minZoom
            steadyZoomScale = minZoom
            offset = .zero
            steadyOffset = .zero
        }
    }
}

// MARK: - 全屏页

struct ComicStripFullscreenView: View {
    let artifact: ComicArtifact
    var imageQuality: ComicImageQuality = .fullscreen
    var fallbackURLs: [URL] = []
    @Environment(\.dismiss) private var dismiss
    @State private var showZoomHint = true

    private var hasDisplayablePanels: Bool {
        !artifact.panels(for: .preview).isEmpty || !fallbackURLs.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if hasDisplayablePanels {
                    stripContent
                } else {
                    unavailableContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .font(AppTheme.bodyFont(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryColor)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .interactiveDismissDisabled()
    }

    private var stripContent: some View {
        GeometryReader { geo in
            let availableW = max(0, geo.size.width - ComicStripLayout.horizontalPadding * 2)
            let availableH = geo.size.height

            if let stripSize = ComicStripLayout.stripDimensions(
                maxWidth: availableW,
                maxHeight: availableH
            ) {
                ComicStripZoomableStrip(
                    artifact: artifact,
                    imageQuality: imageQuality,
                    useProgressiveLoading: true,
                    fallbackURLs: fallbackURLs,
                    stripWidth: stripSize.width,
                    stripHeight: stripSize.height
                )
            }

            if showZoomHint, geo.size.width > 0, geo.size.height > 0 {
                VStack {
                    Spacer()
                    Text("双指缩放查看细节")
                        .font(AppTheme.capsFont(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.muted)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 20) + 12)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            showZoomHint = false
                        }
                    }
                }
            }
        }
    }

    private var unavailableContent: some View {
        VStack(spacing: 16) {
            Text("四格暂时无法全屏查看")
                .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.text)
            Text("请返回结果页稍后再试。")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
        }
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }
}
