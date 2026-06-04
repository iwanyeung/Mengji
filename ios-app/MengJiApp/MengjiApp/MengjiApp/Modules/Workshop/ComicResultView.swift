import SwiftUI

struct ComicResultView: View {
    var dreamId: UUID? = nil
    var artifactId: UUID? = nil
    var artifact: ComicArtifact?

    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dreamStore: DreamStore

    @State private var fullscreenArtifact: ComicArtifact?
    @State private var fullscreenReady = false
    @State private var isPreparingFullscreen = false
    @State private var isOpeningFullscreen = false

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
                    if let stripSize = ComicStripLayout.stripDimensions(
                        maxWidth: geometry.size.width,
                        maxHeight: geometry.size.height
                    ) {
                        framedStripMockStrip
                            .frame(width: stripSize.width, height: stripSize.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, ComicStripLayout.horizontalPadding)
                .layoutPriority(1)

                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                displayedArtifact?.remoteImageURLs.isEmpty == false
                                    ? "根据你的梦生成的四格分镜，可全屏查看或保存。"
                                    : "当前为占位预览。接入网络后将展示真实生成画面。"
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
        .navigationTitle(displayedArtifact?.remoteImageURLs.isEmpty == false ? "四格已生成" : "四格预览")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $fullscreenArtifact) { artifact in
            ComicStripFullscreenView(artifact: artifact)
        }
        .task(id: prefetchTaskKey) {
            await refreshLocalCacheIfNeeded()
            await warmFullscreenAssets()
        }
    }

    @MainActor
    private func warmFullscreenAssets() async {
        guard let artifact = displayedArtifact,
              !artifact.remoteImageURLs.isEmpty else {
            fullscreenReady = false
            return
        }

        isPreparingFullscreen = true
        defer { isPreparingFullscreen = false }

        var working = artifact
        if let dreamId {
            working = await refreshAndMergeArtifact(working, dreamId: dreamId)
        }

        await ComicArtifactService.prepareForFullscreen(artifact: working)
        fullscreenReady = working.isReadyForFullscreenDisplay()
    }

    @MainActor
    private func refreshAndMergeArtifact(_ artifact: ComicArtifact, dreamId: UUID) async -> ComicArtifact {
        let refreshed = await ComicArtifactService.refreshLocalCache(for: artifact)
        guard var dream = dreamStore.dream(id: dreamId),
              let index = dream.comicArtifacts.firstIndex(where: { $0.id == refreshed.id }) else {
            return refreshed
        }
        dream.comicArtifacts[index] = refreshed
        dreamStore.upsert(dream)
        return refreshed
    }

    @MainActor
    private func refreshLocalCacheIfNeeded() async {
        guard let artifact = displayedArtifact,
              let dreamId,
              artifact.imagePaths.allSatisfy({ $0.isEmpty }),
              !artifact.remoteImageURLs.isEmpty else { return }

        _ = await refreshAndMergeArtifact(artifact, dreamId: dreamId)
    }

    private var prefetchTaskKey: String {
        guard let artifact = displayedArtifact else { return "" }
        let preview = artifact.remoteURLs(for: .preview).map(\.absoluteString).joined(separator: "|")
        let local = artifact.thumbImagePaths.joined(separator: "|")
        let full = artifact.imagePaths.joined(separator: "|")
        return "\(preview)|\(local)|\(full)"
    }

    private var framedStripMockStrip: some View {
        ZStack(alignment: .topTrailing) {
            ComicStripContentView(
                artifact: displayedArtifact,
                imageQuality: .preview
            )

            Button {
                openFullscreenIfReady()
            } label: {
                Text(fullscreenButtonTitle)
                    .font(AppTheme.capsFont(size: 10, weight: .semibold))
                    .foregroundColor(fullscreenReady ? AppTheme.text : AppTheme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.surface.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(AppTheme.muted.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!fullscreenReady || isPreparingFullscreen || isOpeningFullscreen)
            .opacity(fullscreenReady || isPreparingFullscreen || isOpeningFullscreen ? 1 : 0.55)
            .padding(10)
        }
    }

    private var fullscreenButtonTitle: String {
        if isOpeningFullscreen { return "打开中…" }
        if isPreparingFullscreen { return "准备中…" }
        return "全屏"
    }

    private func resolveFullscreenArtifact() -> ComicArtifact? {
        guard let id = displayedArtifact?.id else { return displayedArtifact }
        if let dreamId,
           let dream = dreamStore.dream(id: dreamId),
           let latest = dream.comicArtifacts.first(where: { $0.id == id }) {
            return latest
        }
        return displayedArtifact
    }

    private func openFullscreenIfReady() {
        guard fullscreenReady, !isOpeningFullscreen else { return }
        isOpeningFullscreen = true
        Task { @MainActor in
            defer { isOpeningFullscreen = false }
            guard var resolved = resolveFullscreenArtifact(),
                  !resolved.remoteImageURLs.isEmpty else {
                fullscreenReady = false
                return
            }
            if let dreamId {
                resolved = await refreshAndMergeArtifact(resolved, dreamId: dreamId)
            }
            await ComicArtifactService.prepareForFullscreen(artifact: resolved)
            guard resolved.isReadyForFullscreenDisplay() else {
                fullscreenReady = false
                return
            }
            fullscreenArtifact = resolved
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
        let base: ComicArtifact?
        if let artifact {
            base = artifact
        } else if let dreamId, let dream = dreamStore.dream(id: dreamId) {
            if let artifactId {
                base = dream.comicArtifacts.first(where: { $0.id == artifactId }) ?? dream.comicArtifacts.last
            } else {
                base = dream.comicArtifacts.last
            }
        } else {
            base = nil
        }

        guard let base else { return nil }
        guard let dreamId,
              let dream = dreamStore.dream(id: dreamId),
              let latest = dream.comicArtifacts.first(where: { $0.id == base.id }) else {
            return base
        }
        return latest
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
