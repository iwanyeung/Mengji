import SwiftUI

struct ComicResultView: View {
    var dreamId: UUID? = nil
    var artifactId: UUID? = nil
    var artifact: ComicArtifact?

    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dreamStore: DreamStore

    @State private var isFullscreenStripPresented = false

    var body: some View {
        ZStack {
            AppAuroraBackground(style: .workshop)

            VStack(alignment: .leading, spacing: 0) {
                Text("那晚的梦，在这儿了")
                    .font(AppTheme.titleFont(size: 17))
                    .foregroundColor(AppTheme.text)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                if let meta = displayMeta {
                    HStack(spacing: 8) {
                        Text("第\(meta.versionNumber)版")
                            .font(AppTheme.capsFont(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.muted)

                        Text("落成于：\(comicDateTimeString(from: meta.createdAt))")
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundColor(AppTheme.muted.opacity(0.95))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                }

                GeometryReader { geometry in
                    let maxW = geometry.size.width
                    let maxH = geometry.size.height
                    let stripW = min(maxW, maxH / ComicStripLayout.aspectHeightOverWidth)
                    let stripH = stripW * ComicStripLayout.aspectHeightOverWidth

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
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundColor(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                            if let displayedArtifact {
                                Text(displayedArtifact.previewDescription)
                                    .font(AppTheme.bodyFont(size: 13))
                                    .foregroundColor(AppTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("风格：\(styleName(for: displayedArtifact.styleId))")
                                        .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                                        .foregroundColor(AppTheme.text.opacity(0.92))

                                    Text("批次号：\(batchCode(for: displayedArtifact.id))")
                                        .font(AppTheme.bodyFont(size: 12))
                                        .foregroundColor(AppTheme.muted)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("关于这张作品")
                            .font(AppTheme.bodyFont(size: 13, weight: .semibold))
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
        .fullScreenCover(isPresented: $isFullscreenStripPresented) {
            ComicStripFullscreenView()
        }
    }

    private var framedStripMockStrip: some View {
        ZStack(alignment: .topTrailing) {
            ComicStripContentView()

            Button {
                isFullscreenStripPresented = true
            } label: {
                Text("全屏")
                    .font(AppTheme.capsFont(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.muted.opacity(0.92))
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    private var actions: some View {
        Button {
            appState.openStarMap()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Text("稍后在潜意识星图里再看")
                Spacer()
                Image(systemName: "point.topleft.down.curvedto.point.filled.bottomright.up")
            }
            .font(AppTheme.bodyFont(size: 14, weight: .semibold))
            .foregroundColor(AppTheme.background)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(AppTheme.primaryColor)
        }
        .buttonStyle(.plain)
    }

    private var displayedArtifact: ComicArtifact? {
        if let artifact {
            return artifact
        }

        guard let dreamId, let dream = dreamStore.dream(id: dreamId) else {
            return nil
        }

        if let artifactId {
            return dream.comicArtifacts.first(where: { $0.id == artifactId }) ?? dream.comicArtifacts.last
        }

        return dream.comicArtifacts.last
    }

    private var displayMeta: (versionNumber: Int, createdAt: Date)? {
        guard let displayedArtifact else { return nil }
        guard let dreamId, let dream = dreamStore.dream(id: dreamId) else {
            return (1, displayedArtifact.createdAt)
        }

        let sorted = dream.comicArtifacts.sorted { $0.createdAt > $1.createdAt }
        if let index = sorted.firstIndex(where: { $0.id == displayedArtifact.id }) {
            let versionNumber = sorted.count - index
            return (versionNumber, displayedArtifact.createdAt)
        }

        return (sorted.count + 1, displayedArtifact.createdAt)
    }

    private func comicDateTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: date)
    }

    private func styleName(for id: String) -> String {
        switch id {
        case "noir-comic":
            return "高对比黑白 · 颗粒感四格"
        case "neon-surreal":
            return "霓虹超现实 · 拼贴四格"
        default:
            return "自定义风格"
        }
    }

    private func batchCode(for id: UUID) -> String {
        let clean = id.uuidString.replacingOccurrences(of: "-", with: "")
        let suffix = String(clean.suffix(8)).uppercased()
        return "MJ-\(suffix)"
    }
}
