import SwiftUI

struct MockPaymentView: View {
    var dreamId: UUID?
    var styleId: String

    @EnvironmentObject private var dreamStore: DreamStore
    @Environment(\.dismiss) private var dismiss
    @State private var navigateToResult = false
    @State private var createdArtifact: ComicArtifact?

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                header
                orderSummary

                Spacer()

                Button {
                    performMockPayment()
                } label: {
                    HStack(spacing: 10) {
                        Text("确认支付（Mock）并开始显化")
                        Spacer()
                        Image(systemName: "sparkles")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(AppTheme.background)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(AppTheme.primaryColor)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)

            NavigationLink(
                destination: ComicResultView(artifact: createdArtifact),
                isActive: $navigateToResult
            ) {
                EmptyView()
            }
            .hidden()
        }
        .navigationTitle("确认订单")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前阶段仅为体验版流程，支付为伪流程，方便你先感受整个路径。")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(AppTheme.muted)
        }
    }

    private var orderSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本次显化")
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.text)

            if let dreamId, let dream = dreamStore.dream(id: dreamId) {
                Text("梦境：《\(dream.title)》")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(AppTheme.text)
            } else {
                Text("梦境：来自最近的一条记录")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(AppTheme.text)
            }

            Text("风格：\(styleName(for: styleId))")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundColor(AppTheme.text)

            Text("价格（示意）：¥ 18")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundColor(AppTheme.muted)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(AppTheme.surface, lineWidth: 1)
                .background(AppTheme.background.opacity(0.7))
        )
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
        navigateToResult = true
    }
}

