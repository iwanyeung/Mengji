import SwiftUI
import UIKit

// MARK: - 布局常量（与结果页条漫一致）

enum ComicStripLayout {
    static let panelFractions: [CGFloat] = [0.22, 0.30, 0.26, 0.22]
    static let gutter: CGFloat = 2
    static let aspectHeightOverWidth: CGFloat = 2.12
}

// MARK: - 条漫内容（结果页与全屏共用）

struct ComicStripContentView: View {
    var body: some View {
        ZStack {
            AppTheme.surface

            GeometryReader { geo in
                let h = geo.size.height
                let fractions = ComicStripLayout.panelFractions
                let gutter = ComicStripLayout.gutter
                let totalGutter = gutter * CGFloat(max(0, fractions.count - 1))
                let contentH = max(0, h - totalGutter)
                VStack(spacing: gutter) {
                    ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
                        comicStripPanel(index: index + 1)
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
    }

    private func comicStripPanel(index: Int) -> some View {
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
                .font(AppTheme.capsFont(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.text.opacity(0.22))
                .padding(8)
        }
    }
}

// MARK: - 轻噪点（确定性 pattern）

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

// MARK: - 双指缩放（UIKit）

struct ComicStripZoomingScrollView: UIViewRepresentable {
    var contentWidth: CGFloat
    var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1.0
        scroll.maximumZoomScale = 4.0
        scroll.bouncesZoom = true
        scroll.alwaysBounceVertical = true
        scroll.alwaysBounceHorizontal = true
        scroll.showsVerticalScrollIndicator = true
        scroll.showsHorizontalScrollIndicator = true
        scroll.backgroundColor = .clear
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = true

        let zoomContainer = UIView()
        zoomContainer.backgroundColor = .clear
        zoomContainer.translatesAutoresizingMaskIntoConstraints = false

        let hosting = UIHostingController(rootView: ComicStripContentView())
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        zoomContainer.addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: zoomContainer.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: zoomContainer.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: zoomContainer.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: zoomContainer.bottomAnchor)
        ])

        scroll.addSubview(zoomContainer)

        let widthConstraint = zoomContainer.widthAnchor.constraint(equalToConstant: contentWidth)
        let heightConstraint = zoomContainer.heightAnchor.constraint(equalToConstant: contentHeight)
        context.coordinator.widthConstraint = widthConstraint
        context.coordinator.heightConstraint = heightConstraint
        context.coordinator.hosting = hosting
        context.coordinator.zoomContainer = zoomContainer
        context.coordinator.scrollView = scroll

        NSLayoutConstraint.activate([
            zoomContainer.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            zoomContainer.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            widthConstraint,
            heightConstraint
        ])

        return scroll
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard contentWidth > 0, contentHeight > 0 else { return }
        context.coordinator.widthConstraint?.constant = contentWidth
        context.coordinator.heightConstraint?.constant = contentHeight
        scrollView.layoutIfNeeded()
        context.coordinator.applyCenteringInsets(to: scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var zoomContainer: UIView?
        var hosting: UIHostingController<ComicStripContentView>?
        var widthConstraint: NSLayoutConstraint?
        var heightConstraint: NSLayoutConstraint?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            zoomContainer
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            applyCenteringInsets(to: scrollView)
        }

        func applyCenteringInsets(to scrollView: UIScrollView) {
            let subW = scrollView.contentSize.width
            let subH = scrollView.contentSize.height
            let boundsW = scrollView.bounds.width
            let boundsH = scrollView.bounds.height
            guard boundsW > 0, boundsH > 0 else { return }

            var inset = UIEdgeInsets.zero
            if subW < boundsW {
                let pad = (boundsW - subW) * 0.5
                inset.left = pad
                inset.right = pad
            }
            if subH < boundsH {
                let pad = (boundsH - subH) * 0.5
                inset.top = pad
                inset.bottom = pad
            }
            scrollView.contentInset = inset
            scrollView.verticalScrollIndicatorInsets = inset
            scrollView.horizontalScrollIndicatorInsets = inset
        }
    }
}

// MARK: - 全屏页

struct ComicStripFullscreenView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                GeometryReader { geo in
                    let horizontalPadding: CGFloat = 16
                    let bottomBreathing: CGFloat = max(geo.safeAreaInsets.bottom, 12) + 8
                    let availableH = max(0, geo.size.height - bottomBreathing)
                    let maxW = geo.size.width - horizontalPadding * 2
                    let stripW = min(maxW, availableH / ComicStripLayout.aspectHeightOverWidth)
                    let stripH = stripW * ComicStripLayout.aspectHeightOverWidth

                    ComicStripZoomingScrollView(contentWidth: stripW, contentHeight: stripH)
                        .frame(width: geo.size.width, height: geo.size.height)
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
}
