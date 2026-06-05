import SwiftUI

struct StyleSelectionView: View {
    var dreamId: UUID?

    @ObservedObject var appState: AppState
    @State private var selectedStyleId: String?
    @State private var navigateToStoryboard = false

    private let styles: [WorkshopStyle] = [
        WorkshopStyle(
            id: "noir-comic",
            title: "高对比黑白 · 颗粒感四格",
            description: "像旧时代报纸上的连载漫画，用粗线条和颗粒噪点讲完一段梦。",
            previewImageName: "StylePreviewNoir"
        ),
        WorkshopStyle(
            id: "neon-surreal",
            title: "霓虹超现实 · 拼贴四格",
            description: "颜色偏离现实，人物与场景像被剪贴在同一张夜空里。",
            previewImageName: "StylePreviewNeon"
        )
    ]

    var body: some View {
        ZStack {
            AppAuroraBackground(style: .workshop)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    ForEach(styles) { style in
                        StyleCard(
                            style: style,
                            isSelected: style.id == selectedStyleId
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: WorkshopMotion.selectDuration)) {
                                selectedStyleId = style.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
        }
        .navigationDestination(isPresented: $navigateToStoryboard) {
            StoryboardPreviewView(
                dreamId: dreamId,
                styleId: selectedStyleId ?? styles.first?.id ?? "",
                appState: appState
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomCTA
        }
        .navigationTitle("选择风格")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .onAppear {
            if selectedStyleId == nil {
                selectedStyleId = styles.first?.id
            }
            if let dreamId {
                Task {
                    try? await AuthService.shared.ensureAnonymousSession()
                    try? await DreamService.shared.prefetchStoryboard(dreamId: dreamId)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("为这条梦选择一种落成风格。")
                .font(AppTheme.bodyFont(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("给这条梦选一个最合适的画面语言。")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomCTA: some View {
        Button {
            if selectedStyleId == nil {
                selectedStyleId = styles.first?.id
            }
            if selectedStyleId != nil {
                withAnimation(WorkshopMotion.navigationSpring) {
                    navigateToStoryboard = true
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text("继续 · 预览分镜")
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(AppTheme.bodyFont(size: 16, weight: .semibold))
            .foregroundColor(AppTheme.background)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(AppTheme.primaryColor)
        }
        .buttonStyle(WorkshopPrimaryCTAButtonStyle())
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(AppTheme.background.opacity(0.92))
    }
}

private struct WorkshopStyle: Identifiable {
    let id: String
    let title: String
    let description: String
    let previewImageName: String
}

private struct StyleCard: View {
    let style: WorkshopStyle
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Image(style.previewImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()

                if style.id == "noir-comic" {
                    ComicFilmGrainOverlay()
                        .opacity(0.45)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                Text(style.title)
                    .font(AppTheme.titleFont(size: 15))
                    .foregroundColor(AppTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(style.description)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundColor(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .overlay {
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(
                    isSelected ? AppTheme.primaryColor : AppTheme.surface,
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .scaleEffect(isSelected ? 1.0 : 0.995)
        .shadow(
            color: isSelected ? AppTheme.primaryColor.opacity(0.18) : .clear,
            radius: isSelected ? 8 : 0,
            x: 0,
            y: 2
        )
        .animation(.easeInOut(duration: WorkshopMotion.selectDuration), value: isSelected)
    }
}

