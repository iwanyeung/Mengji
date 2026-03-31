import SwiftUI

struct MockPaymentView: View {
    var dreamId: UUID?
    var styleId: String

    @ObservedObject var appState: AppState
    @EnvironmentObject private var dreamStore: DreamStore
    @State private var navigateToResult = false
    @State private var createdArtifact: ComicArtifact?

    var body: some View {
        ZStack {
            AppAuroraBackground(style: .workshop)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    orderSummary
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
        }
        .navigationDestination(isPresented: $navigateToResult) {
            ComicResultView(artifact: createdArtifact, appState: appState)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomCTA
        }
        .navigationTitle("准备落成")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("继续后将进入四格故事落成流程。")
                .font(AppTheme.bodyFont(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.text)

            Text("当前阶段仅为体验版流程，支付为伪流程，方便你先感受整个路径。")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
        }
    }

    private var orderSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本次落成信息")
                .font(AppTheme.titleFont(size: 16))
                .foregroundColor(AppTheme.text)

            if let dreamId, let dream = dreamStore.dream(id: dreamId) {
                Text("梦境：《\(dream.title)》")
                    .font(AppTheme.bodyFont(size: 15))
                    .foregroundColor(AppTheme.text)
            } else {
                Text("梦境：来自最近的一条记录")
                    .font(AppTheme.bodyFont(size: 15))
                    .foregroundColor(AppTheme.text)
            }

            Text("风格：\(styleName(for: styleId))")
                .font(AppTheme.bodyFont(size: 15))
                .foregroundColor(AppTheme.text)

            Text("价格（示意）：¥ 18")
                .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.primaryColor)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(AppTheme.surface, lineWidth: 1)
                .background(AppTheme.background.opacity(0.7))
        )
    }

    private var bottomCTA: some View {
        Button {
            performMockPayment()
        } label: {
            HStack(spacing: 10) {
                Text("继续（体验版）并开始落成")
                Spacer()
                Image(systemName: "sparkles")
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

    private func styleName(for id: String) -> String {
        switch id {
        case "noir-comic":
            return "高对比黑白 · 颗粒感四格"
        case "neon-surreal":
            return "霓虹超现实 · 拼贴四格"
        default:
            return "未知风格"
        }
    }

    private func performMockPayment() {
        let targetDreamId: UUID?
        if let id = dreamId {
            targetDreamId = id
        } else {
            targetDreamId = dreamStore.visibleDreams().first?.id
        }

        guard let id = targetDreamId, var dream = dreamStore.dream(id: id) else {
            return
        }

        let artifact = ComicArtifact(
            id: UUID(),
            createdAt: Date(),
            styleId: styleId,
            previewDescription: "基于《\(dream.title)》生成的四格漫画，占位预览。",
            imagePaths: []
        )

        dream.comicArtifacts.append(artifact)
        DreamStore.shared.upsert(dream)

        Analytics.track("workshop_mock_payment_success", properties: [
            "dreamId": dream.id.uuidString,
            "styleId": styleId
        ])

        createdArtifact = artifact
        withAnimation(WorkshopMotion.navigationSpring) {
            navigateToResult = true
        }
    }
}

