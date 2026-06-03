import SwiftUI
import StoreKit

struct CheckoutView: View {
    var dreamId: UUID?
    var styleId: String

    @ObservedObject var appState: AppState
    @ObservedObject private var store = StoreService.shared
    @ObservedObject private var sessionStore = UserSessionStore.shared
    @ObservedObject private var jobStore = ComicGenerationJobStore.shared
    @EnvironmentObject private var dreamStore: DreamStore
    @Environment(\.dismiss) private var dismiss

    @State private var entitlements: Entitlements?
    @State private var navigateToResult = false
    @State private var createdArtifact: ComicArtifact?
    @State private var errorMessage: String?
    @State private var existingVisualUrls: [URL]?
    @State private var existingVisualThumbUrls: [URL]?
    @State private var existingVisualAvailable = false
    @State private var narrativeStaleForComic = false

    var body: some View {
        ZStack {
            AppAuroraBackground(style: .workshop)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    orderSummary
                    if existingVisualAvailable {
                        existingVisualBanner
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundColor(AppTheme.accent)
                    }
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
        .task {
            await store.loadProduct()
            await refreshEntitlements()
            await checkExistingVisual()
        }
    }

    private var dreamTitle: String {
        guard let dreamId, let dream = dreamStore.dream(id: dreamId) else { return "" }
        return dream.title
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("继续后将进入四格故事落成流程。")
                .font(AppTheme.bodyFont(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.text)

            if freeRemaining > 0 {
                Text("体验额度剩余 \(freeRemaining)/\(entitlements?.freeComicsTotal ?? 10) 次 · 本次免费")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundColor(AppTheme.primaryColor)
            } else {
                Text("消耗型内购：每次生成 1 条梦的四格漫画，不支持恢复购买。")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundColor(AppTheme.muted)
            }
        }
    }

    private var existingVisualBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                narrativeStaleForComic
                    ? "梦境整理已更新，建议按新内容重新落成。"
                    : "该梦在此风格下已有落成作品，可直接查看。"
            )
            .font(AppTheme.bodyFont(size: 13))
            .foregroundColor(AppTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(AppTheme.surface, lineWidth: 1)
        )
    }

    private var freeRemaining: Int {
        entitlements?.freeComicsRemaining ?? 0
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
            }

            Text("风格：\(styleName(for: styleId))")
                .font(AppTheme.bodyFont(size: 15))
                .foregroundColor(AppTheme.text)

            if freeRemaining > 0 && !existingVisualAvailable {
                Text("价格：本次免费（体验额度）")
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryColor)
            } else if existingVisualAvailable && !narrativeStaleForComic {
                Text("价格：查看已有作品免费")
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryColor)
            } else {
                Text("价格：\(store.displayPrice)")
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryColor)
            }
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
        VStack(spacing: 10) {
            if existingVisualAvailable && !narrativeStaleForComic {
                Button {
                    Task { await openExistingVisual() }
                } label: {
                    ctaLabel("查看已有四格")
                }
                .disabled(jobStore.isBusy)

                Button {
                    Task { await startCheckout(forceNew: true) }
                } label: {
                    Text("生成新版本（消耗 1 次额度 / 付费）")
                        .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.muted)
                        .frame(maxWidth: .infinity)
                }
                .disabled(jobStore.isBusy)
            } else {
                Button {
                    Task { await startCheckout(forceNew: narrativeStaleForComic || !existingVisualAvailable) }
                } label: {
                    ctaLabel(
                        jobStore.isBusy
                            ? "生成中…"
                            : (narrativeStaleForComic ? "按新内容重新落成四格" : "开始落成四格漫画")
                    )
                }
                .disabled(jobStore.isBusy)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(AppTheme.background.opacity(0.92))
    }

    private func ctaLabel(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
            Image(systemName: "sparkles")
        }
        .font(AppTheme.bodyFont(size: 16, weight: .semibold))
        .foregroundColor(AppTheme.background)
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(AppTheme.primaryColor)
    }

    private func refreshEntitlements() async {
        do {
            try await AuthService.shared.ensureAnonymousSession()
            entitlements = try await EntitlementService.shared.fetch()
        } catch {
            entitlements = nil
        }
    }

    private func checkExistingVisual() async {
        guard let id = dreamId else { return }
        do {
            try await AuthService.shared.ensureAnonymousSession()
            let detail = try await DreamService.shared.fetchDream(dreamId: id)
            narrativeStaleForComic = detail.analysisStale ?? false
            if let visual = detail.visuals?.last(where: { $0.styleKey == styleId && $0.status == "succeeded" }),
               let urls = visual.imageUrls, !urls.isEmpty {
                let resolved = urls.compactMap { URL(string: $0) }
                let thumbResolved = (visual.imageThumbUrls ?? urls).compactMap { URL(string: $0) }
                existingVisualUrls = resolved
                existingVisualThumbUrls = thumbResolved
                existingVisualAvailable = !narrativeStaleForComic
                ComicImageLoader.shared.prefetch(urls: thumbResolved)
            } else {
                existingVisualAvailable = false
                existingVisualThumbUrls = nil
            }
        } catch {
            existingVisualAvailable = false
        }
    }

    private func openExistingVisual() async {
        guard let urls = existingVisualUrls, !urls.isEmpty else { return }
        let thumbStrings = existingVisualThumbUrls?.map(\.absoluteString)
        let artifact = await ComicArtifactService.build(
            styleId: styleId,
            previewDescription: "已有落成作品",
            fullURLStrings: urls.map(\.absoluteString),
            thumbURLStrings: thumbStrings
        )
        ComicArtifactService.scheduleFullDownload(
            artifactId: artifact.id,
            dreamId: dreamId,
            fullURLs: artifact.remoteImageURLs
        )
        createdArtifact = artifact
        navigateToResult = true
    }

    private func startCheckout(forceNew: Bool) async {
        guard jobStore.canStartNewJob() else {
            jobStore.toastMessage = "已有一条四格正在生成，请稍后再试"
            return
        }

        if !sessionStore.session.isLoggedIn && freeRemaining <= 0 && (forceNew || !existingVisualAvailable) {
            errorMessage = "请先使用 Apple 登录后再购买"
            return
        }

        let targetDreamId = dreamId ?? dreamStore.visibleDreams().first?.id
        guard let id = targetDreamId, let dream = dreamStore.dream(id: id) else {
            errorMessage = "找不到梦境记录"
            return
        }

        errorMessage = nil
        jobStore.beginSubmission()

        do {
            try await AuthService.shared.ensureAnonymousSession()
            var transactionJws: String?
            let needsPayment = forceNew || !existingVisualAvailable

            if needsPayment && freeRemaining <= 0 {
                jobStore.updateSubmissionStatus("等待 App Store 确认…")
                transactionJws = try await store.purchase()
            }

            jobStore.updateSubmissionStatus("正在构思分镜…")
            let job = try await VisualService.shared.createFourPanel(
                dreamId: id,
                styleKey: styleId,
                transactionJws: needsPayment && freeRemaining <= 0 ? transactionJws : nil,
                forceNew: forceNew
            )

            if job.reused == true, let urls = job.imageUrls, !urls.isEmpty {
                jobStore.handleImmediateSuccess(
                    urls: urls,
                    thumbUrls: job.imageThumbUrls,
                    dreamId: id,
                    styleId: styleId
                )
                await refreshEntitlements()
                return
            }

            jobStore.startJob(
                visualId: job.visualId,
                dreamId: id,
                styleId: styleId,
                dreamTitle: dream.title
            )
            await refreshEntitlements()
        } catch {
            jobStore.cancelSubmission()
            errorMessage = error.localizedDescription
        }
    }

    private func styleName(for id: String) -> String {
        switch id {
        case "noir-comic": return "高对比黑白 · 颗粒感四格"
        case "neon-surreal": return "霓虹超现实 · 拼贴四格"
        default: return "未知风格"
        }
    }
}
