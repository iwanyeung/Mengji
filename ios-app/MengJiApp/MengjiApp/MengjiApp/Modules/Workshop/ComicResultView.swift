import SwiftUI

struct ComicResultView: View {
    var dreamId: UUID? = nil
    var artifactId: UUID? = nil
    var artifact: ComicArtifact?
    var visualId: String? = nil

    @ObservedObject var appState: AppState
    @ObservedObject private var jobStore = ComicGenerationJobStore.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dreamStore: DreamStore

    @State private var fullscreenArtifact: ComicArtifact?
    @State private var fullscreenReady = false
    @State private var isPreparingFullscreen = false
    @State private var isOpeningFullscreen = false
    @State private var storyboardCaptions: [VisualDetail.VisualStoryboardCaption] = []
    @State private var selectedFidelityFeedback: ComicFidelityFeedback?
    @State private var compensationEligible = false
    @State private var compensationHint: String?
    @State private var isSubmittingFeedback = false
    @State private var feedbackMessage: String?
    @State private var isStartingCompensationRetry = false

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

                    storyboardCaptionsSection
                    fidelityFeedbackSection
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
            await loadVisualMetadata()
        }
    }

    private var resolvedVisualId: String? {
        if let visualId, !visualId.isEmpty { return visualId }
        return displayedArtifact?.id.uuidString.lowercased()
    }

    @ViewBuilder
    private var storyboardCaptionsSection: some View {
        if !storyboardCaptions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("四格故事线")
                    .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.text)

                ForEach(storyboardCaptions, id: \.panelIndex) { panel in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(panel.panelIndex)")
                            .font(AppTheme.capsFont(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.muted)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(panel.caption)
                                .font(AppTheme.bodyFont(size: 12))
                                .foregroundColor(AppTheme.text.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)

                            Text(sourceLabel(panel.source))
                                .font(AppTheme.capsFont(size: 9, weight: .semibold))
                                .foregroundColor(AppTheme.muted)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(AppTheme.surface, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var fidelityFeedbackSection: some View {
        if displayedArtifact?.remoteImageURLs.isEmpty == false,
           resolvedVisualId != nil {
        VStack(alignment: .leading, spacing: 12) {
            Text("和梦对得上吗？")
                .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.text)

            Text("你的反馈会帮助我们改进落成体验，不会影响梦境记录。")
                .font(AppTheme.bodyFont(size: 12))
                .foregroundColor(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if selectedFidelityFeedback == nil {
                VStack(spacing: 8) {
                    ForEach(ComicFidelityFeedback.allCases, id: \.self) { option in
                        Button {
                            Task { await submitFidelityFeedback(option) }
                        } label: {
                            Text(option.label)
                                .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(AppTheme.surface.opacity(0.85))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 0)
                                        .strokeBorder(AppTheme.muted.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmittingFeedback)
                    }
                }
            } else if let selectedFidelityFeedback {
                Text("已记录：\(selectedFidelityFeedback.label)")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundColor(AppTheme.muted)
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundColor(AppTheme.primaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if compensationEligible, let hint = compensationHint {
                VStack(alignment: .leading, spacing: 8) {
                    Text(hint)
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundColor(AppTheme.text.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await startCompensationRetry() }
                    } label: {
                        Text(isStartingCompensationRetry ? "正在启动意象重试…" : "免费意象四格重试")
                            .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.primaryColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStartingCompensationRetry || jobStore.isBusy)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(AppTheme.surface, lineWidth: 1)
        )
        }
    }

    private func sourceLabel(_ raw: String) -> String {
        ComicPanelSource(rawValue: raw)?.label ?? "意象延伸"
    }

    private func loadVisualMetadata() async {
        guard let visualId = resolvedVisualId else { return }
        do {
            try await AuthService.shared.ensureAnonymousSession()
            let detail = try await VisualService.shared.fetchAuthorized(visualId: visualId)
            storyboardCaptions = detail.storyboardCaptions ?? []
            if let raw = detail.fidelityFeedback,
               let feedback = ComicFidelityFeedback(rawValue: raw) {
                selectedFidelityFeedback = feedback
            }
            if detail.compensationRedeemed == true {
                compensationEligible = false
            }
        } catch {
            storyboardCaptions = []
        }
    }

    private func submitFidelityFeedback(_ feedback: ComicFidelityFeedback) async {
        guard let visualId = resolvedVisualId else { return }
        isSubmittingFeedback = true
        feedbackMessage = nil
        defer { isSubmittingFeedback = false }

        do {
            try await AuthService.shared.ensureAnonymousSession()
            let response = try await VisualService.shared.submitFidelityFeedback(
                visualId: visualId,
                feedback: feedback
            )
            selectedFidelityFeedback = feedback
            compensationEligible = response.compensationEligible
            compensationHint = response.compensationHint
            feedbackMessage = response.compensationEligible
                ? "感谢反馈，你可以免费再试一次意象四格。"
                : "感谢你的反馈。"
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    private func startCompensationRetry() async {
        guard let dreamId,
              let visualId = resolvedVisualId,
              let artifact = displayedArtifact,
              jobStore.canStartNewJob() else { return }

        isStartingCompensationRetry = true
        defer { isStartingCompensationRetry = false }

        do {
            try await AuthService.shared.ensureAnonymousSession()
            jobStore.beginSubmission()
            jobStore.updateSubmissionStatus("正在以意象模式重试…")
            let job = try await VisualService.shared.createFourPanel(
                dreamId: dreamId,
                styleKey: artifact.styleId,
                transactionJws: nil,
                forceNew: true,
                compensationForVisualId: visualId,
                forceImageryMode: true
            )
            let dreamTitle = dreamStore.dream(id: dreamId)?.title ?? "你的梦"
            jobStore.startJob(
                visualId: job.visualId,
                dreamId: dreamId,
                styleId: artifact.styleId,
                dreamTitle: dreamTitle
            )
            compensationEligible = false
            feedbackMessage = "已开始免费意象重试，可在梦作间查看进度。"
            dismiss()
            appState.openWorkshop(from: dreamId)
        } catch {
            jobStore.cancelSubmission()
            feedbackMessage = error.localizedDescription
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
