import Combine
import Foundation
import SwiftUI

struct PendingComicJob: Codable, Equatable {
    let visualId: String
    let dreamId: UUID
    let styleId: String
    let dreamTitle: String
    let startedAt: Date
}

private struct UnreadComicCompletion: Codable, Equatable {
    let visualId: String
    let dreamId: UUID
    let styleId: String
    let dreamTitle: String
}

enum ComicJobPhase: String, Codable {
    case idle
    case submitting
    case polling
    case succeeded
    case failed
}

@MainActor
final class ComicGenerationJobStore: ObservableObject {
    static let shared = ComicGenerationJobStore()
    static let comicCompletionToast = "四格已落成，可在梦作间查看"

    /// 四格落成后切到梦作间并预选梦境（由 MainTabView 注入）。
    var onComicGenerationSucceeded: ((UUID) -> Void)?

    @Published private(set) var activeJob: PendingComicJob?
    @Published private(set) var phase: ComicJobPhase = .idle
    @Published var panelProgress = 0
    /// 生成中逐格缩略图 URL（未完成的格为 nil），用于流式展示已画好的格子
    @Published private(set) var partialThumbUrls: [String?] = []
    @Published var statusMessage = ""
    @Published var isShowingFullScreenCover = false
    @Published var completedArtifact: ComicArtifact?
    @Published var completedDreamTitle: String?
    @Published var failurePayload: ComicGenerationFailurePayload?
    @Published var showFailureCover = false
    @Published var toastMessage: String?
    /// 推送点击后自动打开四格结果页
    @Published var shouldAutoOpenComicResult = false

    private var pollTask: Task<Void, Never>?
    private var comfortTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var isAppInForeground = true

    private let storageKey = "com.mengji.pendingComicJob"
    private let unreadCompletionKey = "com.mengji.unreadComicCompletion"

    private let comfortMessages = [
        "正在推敲四格分镜…",
        "为第一格寻找合适的画面…",
        "把梦里的意象慢慢画出来…",
        "四格故事还在成形中…",
    ]
    private var comfortIndex = 0

    private init() {
        if let job = loadPersistedJob() {
            activeJob = job
            phase = .polling
            statusMessage = "正在绘制四格漫画…"
        }
        Task {
            await restoreUnreadCompletionIfNeeded()
        }
    }

    var isBusy: Bool {
        phase == .submitting || phase == .polling
    }

    var hasUnreadCompletion: Bool {
        completedArtifact != nil
    }

    func canStartNewJob() -> Bool {
        !isBusy
    }

    func showToast(_ message: String, duration: TimeInterval = 2.5) {
        toastDismissTask?.cancel()
        toastMessage = message
        let expected = message
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            if toastMessage == expected {
                toastMessage = nil
            }
        }
    }

    func beginSubmission() {
        phase = .submitting
        panelProgress = 0
        partialThumbUrls = []
        statusMessage = "正在准备…"
        failurePayload = nil
        showFailureCover = false
        isShowingFullScreenCover = true
        Task {
            await PushNotificationService.shared.requestAuthorizationIfNeeded()
        }
    }

    func cancelSubmission() {
        phase = .idle
        isShowingFullScreenCover = false
        pollTask?.cancel()
        pollTask = nil
        stopComfortRotation()
    }

    func updateSubmissionStatus(_ message: String) {
        statusMessage = message
    }

    func startJob(visualId: String, dreamId: UUID, styleId: String, dreamTitle: String, showProgress: Bool = true) {
        let job = PendingComicJob(
            visualId: visualId,
            dreamId: dreamId,
            styleId: styleId,
            dreamTitle: dreamTitle,
            startedAt: Date()
        )
        activeJob = job
        persist(job)
        phase = .polling
        panelProgress = 0
        partialThumbUrls = []
        statusMessage = "正在绘制四格漫画…"
        if showProgress {
            isShowingFullScreenCover = true
        }
        startPollLoopIfNeeded()
    }

    func handleImmediateSuccess(
        urls: [String],
        thumbUrls: [String]? = nil,
        dreamId: UUID,
        styleId: String
    ) {
        Task {
            await handleSuccess(
                urls: urls,
                thumbUrls: thumbUrls,
                dreamId: dreamId,
                styleId: styleId,
                visualId: nil,
                forceNew: false
            )
        }
    }

    func minimize() {
        isShowingFullScreenCover = false
    }

    func reopenProgress() {
        guard activeJob != nil, phase == .polling else { return }
        isShowingFullScreenCover = true
    }

    func clearCompletedArtifact() {
        completedArtifact = nil
        completedDreamTitle = nil
        clearUnreadCompletion()
        if phase == .succeeded {
            phase = .idle
        }
        shouldAutoOpenComicResult = false
    }

    func dismissFailure() {
        showFailureCover = false
    }

    func clearFailureState() {
        showFailureCover = false
        failurePayload = nil
        if phase == .failed {
            phase = .idle
        }
    }

    func pausePolling() {
        isAppInForeground = false
        pollTask?.cancel()
        pollTask = nil
        stopComfortRotation()
    }

    func refreshPendingIfNeeded() {
        isAppInForeground = true
        restorePersistedJobIfNeeded()
        startPollLoopIfNeeded()
        Task {
            await syncActiveJobOnce()
            await recoverServerPendingVisualIfNeeded()
            await restoreUnreadCompletionIfNeeded()
        }
    }

    /// 推送点击或前台收到远程通知时，拉取结果并走统一收口。
    func ingestRemoteVisual(visualId: String, openResultAutomatically: Bool = false) async {
        if openResultAutomatically {
            shouldAutoOpenComicResult = true
        }
        do {
            let detail = try await VisualService.shared.fetchAuthorized(visualId: visualId)
            let styleId = detail.styleKey ?? activeJob?.styleId ?? "noir-comic"
            guard let dreamId = UUID(uuidString: detail.dreamId) else { return }

            if detail.status == "succeeded", let urls = detail.imageUrls, !urls.isEmpty {
                await handleSuccess(
                    urls: urls,
                    thumbUrls: detail.imageThumbUrls,
                    dreamId: dreamId,
                    styleId: styleId,
                    visualId: visualId,
                    forceNew: false
                )
            } else if detail.status == "failed" {
                handleFailure(from: detail, dreamId: dreamId, styleId: styleId)
            } else if activeJob == nil {
                let title = DreamStore.shared.dream(id: dreamId)?.title ?? "你的梦"
                startJob(
                    visualId: visualId,
                    dreamId: dreamId,
                    styleId: styleId,
                    dreamTitle: title,
                    showProgress: false
                )
            } else if detail.status == "generating" || detail.status == "queued" {
                applyProgress(from: detail)
                startPollLoopIfNeeded()
            }
        } catch {
            if isRecoverable(error) {
                statusMessage = "连接暂时中断，稍后会继续同步…"
                return
            }
            showToast(error.localizedDescription)
        }
    }

    private func restorePersistedJobIfNeeded() {
        if activeJob == nil, let job = loadPersistedJob() {
            activeJob = job
            phase = .polling
            if statusMessage.isEmpty {
                statusMessage = "正在绘制四格漫画…"
            }
        }
    }

    private func syncActiveJobOnce() async {
        guard let job = activeJob, phase == .polling else { return }
        await ingestRemoteVisual(visualId: job.visualId)
    }

    private func recoverServerPendingVisualIfNeeded() async {
        guard activeJob == nil, phase != .submitting else { return }
        do {
            let items = try await VisualService.shared.fetchPendingVisuals()
            guard let item = items.first,
                  let dreamId = UUID(uuidString: item.dreamId) else { return }
            let title = DreamStore.shared.dream(id: dreamId)?.title ?? "你的梦"
            startJob(
                visualId: item.visualId,
                dreamId: dreamId,
                styleId: item.styleKey,
                dreamTitle: title,
                showProgress: false
            )
        } catch {
            // 静默：离线或无进行中任务
        }
    }

    private func restoreUnreadCompletionIfNeeded() async {
        guard completedArtifact == nil,
              let unread = loadUnreadCompletion() else { return }
        await ingestRemoteVisual(visualId: unread.visualId)
        if completedArtifact == nil {
            completedDreamTitle = unread.dreamTitle
        }
    }

    private func startPollLoopIfNeeded() {
        guard isAppInForeground, phase == .polling, activeJob != nil, pollTask == nil else { return }
        startComfortRotation()
        pollTask = Task {
            guard let job = activeJob else { return }
            do {
                let result = try await VisualService.shared.pollUntilDone(visualId: job.visualId) { [weak self] detail in
                    Task { @MainActor in
                        self?.applyProgress(from: detail)
                    }
                }
                guard !Task.isCancelled else { return }
                handlePollResult(result, job: job)
            } catch {
                guard !Task.isCancelled else { return }
                handlePollError(error)
            }
        }
    }

    private func handlePollError(_ error: Error) {
        pollTask = nil
        stopComfortRotation()

        if isRecoverable(error) {
            statusMessage = "连接暂时中断，回到前台后会继续同步…"
            return
        }

        showToast(error.localizedDescription)
        phase = .failed
        isShowingFullScreenCover = false
        clearPersistedJob()
        activeJob = nil
    }

    private func isRecoverable(_ error: Error) -> Bool {
        if case APIError.unauthorized = error { return true }
        if case APIError.network = error { return true }
        if case APIError.server(let message) = error, message.contains("超时") { return true }
        return false
    }

    private func applyProgress(from detail: VisualDetail) {
        panelProgress = detail.successfulPanelCount ?? panelProgress
        if (detail.successfulPanelCount ?? 0) > 0 {
            statusMessage = "正在绘制第 \(min(detail.successfulPanelCount ?? 0, 4))/4 格…"
        }
        if let partial = detail.imageThumbUrlsPartial {
            partialThumbUrls = partial
        } else if let thumbs = detail.imageThumbUrls, !thumbs.isEmpty {
            partialThumbUrls = thumbs.map { Optional($0) }
        }
        ComicImageLoader.shared.prefetch(urls: detail.prefetchableThumbImageURLs)
        if detail.status == "succeeded" {
            ComicImageLoader.shared.prefetch(urls: detail.prefetchableImageURLs)
        }
    }

    private func handlePollResult(_ result: VisualDetail, job: PendingComicJob) {
        pollTask = nil
        stopComfortRotation()

        if result.status == "succeeded", let urls = result.imageUrls, !urls.isEmpty {
            Task {
                await handleSuccess(
                    urls: urls,
                    thumbUrls: result.imageThumbUrls,
                    dreamId: job.dreamId,
                    styleId: job.styleId,
                    visualId: job.visualId,
                    forceNew: true
                )
            }
            Analytics.track("workshop_comic_success", properties: [
                "dreamId": job.dreamId.uuidString,
                "styleId": job.styleId,
                "panelCount": urls.count,
                "forceNew": true,
            ])
            return
        }

        handleFailure(from: result, dreamId: job.dreamId, styleId: job.styleId)
    }

    private func handleSuccess(
        urls: [String],
        thumbUrls: [String]?,
        dreamId: UUID,
        styleId: String,
        visualId: String?,
        forceNew: Bool
    ) async {
        pollTask?.cancel()
        pollTask = nil
        stopComfortRotation()

        let artifactId: UUID = {
            if let visualId, let serverId = UUID(uuidString: visualId) {
                return serverId
            }
            return UUID()
        }()

        // 仅落盘缩略图并预热预览，立即可显示；全分辨率与全屏资源放到后台下载，不阻塞结果展示。
        let artifact = await ComicArtifactService.buildFast(
            styleId: styleId,
            previewDescription: "基于梦境生成的四格漫画",
            fullURLStrings: urls,
            thumbURLStrings: thumbUrls,
            artifactId: artifactId
        )

        if var dream = DreamStore.shared.dream(id: dreamId) {
            if forceNew || !dream.comicArtifacts.contains(where: { $0.id == artifact.id }) {
                dream.comicArtifacts.append(artifact)
                DreamStore.shared.upsert(dream)
            }
        }

        ComicArtifactService.scheduleFullDownload(
            artifactId: artifact.id,
            dreamId: dreamId,
            fullURLs: artifact.remoteImageURLs
        )

        completedArtifact = artifact
        completedDreamTitle = activeJob?.dreamTitle ?? DreamStore.shared.dream(id: dreamId)?.title ?? ""
        phase = .succeeded
        activeJob = nil
        clearPersistedJob()
        isShowingFullScreenCover = false
        panelProgress = 4
        partialThumbUrls = []
        statusMessage = "四格已落成"
        shouldAutoOpenComicResult = true
        onComicGenerationSucceeded?(dreamId)
        showToast(Self.comicCompletionToast)

        if let visualId {
            WatchNotificationBridge.shared.notifyComicReady(visualId: visualId, dreamId: dreamId)
            persistUnreadCompletion(
                UnreadComicCompletion(
                    visualId: visualId,
                    dreamId: dreamId,
                    styleId: styleId,
                    dreamTitle: completedDreamTitle ?? "你的梦"
                )
            )
        }
    }

    private func handleFailure(from result: VisualDetail, dreamId: UUID, styleId: String) {
        pollTask?.cancel()
        pollTask = nil
        stopComfortRotation()

        let panelCount = result.successfulPanelCount ?? 0
        let code = result.failureCode ?? (panelCount == 0 ? "generation_failed" : "partial_success")
        let message = result.userMessage ?? fallbackUserMessage(for: code, panelCount: panelCount)
        let refunded = result.quotaRefunded ?? (panelCount == 0)

        failurePayload = ComicGenerationFailurePayload(
            failureCode: code,
            userMessage: message,
            quotaRefunded: refunded,
            successfulPanelCount: panelCount,
            dreamId: dreamId,
            styleId: styleId
        )

        phase = .failed
        activeJob = nil
        clearPersistedJob()
        isShowingFullScreenCover = false
        showFailureCover = true
        shouldAutoOpenComicResult = false
        partialThumbUrls = []

        Analytics.track("workshop_comic_failure", properties: [
            "dreamId": dreamId.uuidString,
            "styleId": styleId,
            "failureCode": code,
            "panelCount": panelCount,
            "quotaRefunded": refunded,
        ])
    }

    private func fallbackUserMessage(for code: String, panelCount: Int) -> String {
        switch code {
        case "moderation_blocked":
            return "你的梦已经安全保存在梦悸里。在把梦境转成画面时，生成服务对部分内容有安全规范，这次没能通过。这不代表你的梦「有问题」——很多梦境里的意象，适合记录与陪伴式解读，但不适合直接画出来。"
        case "service_unavailable":
            return "生成服务暂时繁忙或连接不稳定，请稍后再试。你的梦境内容不会因此丢失。"
        case "partial_success":
            return "四格还未完整落成（已完成 \(panelCount)/4 格）。剩余分镜未能继续生成，本次额度已使用。"
        default:
            return "这次还未能把梦落成四格。你可以稍后再试，或换一种画面风格。"
        }
    }

    private func startComfortRotation() {
        comfortTask?.cancel()
        comfortIndex = 0
        comfortTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, phase == .polling else { return }
                comfortIndex = (comfortIndex + 1) % comfortMessages.count
                if panelProgress == 0 {
                    statusMessage = comfortMessages[comfortIndex]
                }
            }
        }
    }

    private func stopComfortRotation() {
        comfortTask?.cancel()
        comfortTask = nil
    }

    private func persist(_ job: PendingComicJob) {
        if let data = try? JSONEncoder().encode(job) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadPersistedJob() -> PendingComicJob? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(PendingComicJob.self, from: data)
    }

    private func clearPersistedJob() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func persistUnreadCompletion(_ completion: UnreadComicCompletion) {
        if let data = try? JSONEncoder().encode(completion) {
            UserDefaults.standard.set(data, forKey: unreadCompletionKey)
        }
    }

    private func loadUnreadCompletion() -> UnreadComicCompletion? {
        guard let data = UserDefaults.standard.data(forKey: unreadCompletionKey) else { return nil }
        return try? JSONDecoder().decode(UnreadComicCompletion.self, from: data)
    }

    private func clearUnreadCompletion() {
        UserDefaults.standard.removeObject(forKey: unreadCompletionKey)
    }
}
