import Foundation
import Combine
import AVFoundation
import AVFAudio
import Speech

final class RecordingViewModel: ObservableObject {
    struct Segment: Identifiable {
        let id: UUID
        let occurredAt: Date
        let meta: String
        let durationText: String
        var transcript: String
        var audioFileURL: URL?
        var source: DreamRecordingDraftSource
        var isSelected: Bool
    }

    /// 录梦完成并整理时回调，传入新梦的 ID（用于跳转梦析）
    var onFinishRecording: ((UUID) -> Void)?

    @Published var segments: [Segment] = []
    @Published var isRecording: Bool = false
    @Published var isLocked: Bool = false
    @Published var currentDuration: TimeInterval = 0
    @Published var liveTranscript: String = ""
    @Published var speechAuthDenied: Bool = false
    @Published var isProcessingDream: Bool = false
    @Published var processingError: String?

    // MARK: - 整理等待（P0–P2）
    @Published private(set) var organizingPhase: DreamOrganizingPhase = .preparing
    @Published private(set) var organizingStatusMessage: String = DreamOrganizingPhase.preparing.defaultStatusMessage
    @Published private(set) var organizingUploadedCount: Int = 0
    @Published private(set) var organizingSegmentTotal: Int = 0
    @Published private(set) var organizingShowsSuccess: Bool = false
    /// 整理全屏期间压低录梦页极光动效（全屏自有背景，默认不再压低）
    @Published private(set) var organizingAuroraCalm: Bool = false

    private var organizingComfortTask: Task<Void, Never>?

    /// 语音识别管线曾失败（无权限/识别失败时极光保持静态，避免「像在监听」）
    @Published private(set) var recognitionPipelineFailed: Bool = false

    /// 麦克风被拒或语音识别器不可用 → 极光无动效
    @Published private(set) var auroraMotionAllowed: Bool = true

    /// 平滑后的输入电平 0…1，用于极光与脉冲判定
    @Published private(set) var smoothedInputLevel: CGFloat = 0

    /// 每次 +1 触发一次极光「波」脉冲（与录音电平从低到高跳变 + 已识别到中文 同时满足时）
    @Published private(set) var auroraPulseToken: UInt = 0

    private var currentStartDate: Date?
    private var timer: Timer?

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var segmentAudioURL: URL?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    // lazy：延迟到首次录音时初始化，避免 App 启动时在主线程加载语音识别框架
    private lazy var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    private let levelSmoothingAlpha: CGFloat = 0.22
    private var smoothedLevelInternal: CGFloat = 0

    private var levelInQuietBand: Bool = true
    private let quietLevelThreshold: CGFloat = 0.055
    private let speechLevelThreshold: CGFloat = 0.17
    private var pulseCooldownUntil: Date = .distantPast
    private let pulseCooldown: TimeInterval = 0.85

    private let levelProcessQueue = DispatchQueue(label: "mengji.recording.level")
    private var sessionCancellable: AnyCancellable?

    var hasSelectedSegments: Bool {
        segments.contains(where: \.isSelected)
    }

    var draftBannerText: String? {
        guard !segments.isEmpty else { return nil }
        return "共 \(segments.count) 段草稿，勾选参与整理后点「完成并整理」"
    }

    var formattedCurrentDuration: String {
        let total = Int(currentDuration.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var buttonHint: String {
        if isLocked {
            return "已锁定 \(formattedCurrentDuration) · 轻点结束"
        } else if isRecording {
            return "录制中 \(formattedCurrentDuration)"
        } else {
            return "按住录音"
        }
    }

    init() {
        refreshAuroraPolicy()
        sessionCancellable = DreamRecordingSession.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadSegmentsFromSession()
            }
        reloadSegmentsFromSession()
    }

    func reloadSegmentsFromSession() {
        Task { @MainActor in
            let drafts = DreamRecordingSession.shared.drafts
            segments = drafts.map { draft in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "MMM dd • HH:mm"
                return Segment(
                    id: draft.id,
                    occurredAt: draft.occurredAt,
                    meta: formatter.string(from: draft.occurredAt),
                    durationText: draft.durationText,
                    transcript: draft.transcript,
                    audioFileURL: draft.audioFileURL,
                    source: draft.source,
                    isSelected: draft.isSelected
                )
            }
        }
    }

    func beginNewDreamSession() {
        Task { @MainActor in
            DreamRecordingSession.shared.beginNewDream()
        }
    }

    func setSegmentSelected(id: UUID, selected: Bool) {
        Task { @MainActor in
            DreamRecordingSession.shared.setSelected(id: id, selected: selected)
        }
    }

    func refreshAuroraPolicy() {
        let mic = AVAudioApplication.shared.recordPermission
        let micDenied = (mic == .denied)
        let speechAvailable = speechRecognizer?.isAvailable ?? false

        let allowed = !micDenied && speechAvailable && !speechAuthDenied && !recognitionPipelineFailed
        if auroraMotionAllowed != allowed {
            auroraMotionAllowed = allowed
        }
    }

    func beginRecording() {
        guard !isRecording else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .authorized:
                    self.speechAuthDenied = false
                    self.refreshAuroraPolicy()
                    self.startRecordingSession()
                default:
                    self.speechAuthDenied = true
                    self.refreshAuroraPolicy()
                }
            }
        }
    }

    private func startRecordingSession() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            speechAuthDenied = true
            refreshAuroraPolicy()
            return
        }

        isRecording = true
        isLocked = false
        currentStartDate = Date()
        currentDuration = 0
        liveTranscript = ""
        recognitionPipelineFailed = false
        resetLevelStateForNewTake()
        refreshAuroraPolicy()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentDuration += 0.1
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            speechAuthDenied = true
            isRecording = false
            refreshAuroraPolicy()
            return
        }

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)

        segmentAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).caf")
        if let url = segmentAudioURL {
            audioFile = try? AVAudioFile(forWriting: url, settings: format.settings)
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            try? self?.audioFile?.write(from: buffer)
            self?.processAudioLevel(buffer: buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            isRecording = false
            recognitionPipelineFailed = true
            refreshAuroraPolicy()
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.liveTranscript = text
                    self.evaluateAuroraPulse()
                }
            } else if let error {
                DispatchQueue.main.async {
                    // 用户松手结束录音时会 cancel task，系统仍回调 error，不能当作「识别管线失败」
                    if Self.isBenignEndOfSpeechTaskError(error) {
                        return
                    }
                    guard self.isRecording else { return }
                    self.teardownRecordingSession()
                    self.recognitionPipelineFailed = true
                    self.refreshAuroraPolicy()
                }
            }
        }
    }

    private func resetLevelStateForNewTake() {
        smoothedLevelInternal = 0
        smoothedInputLevel = 0
        levelInQuietBand = true
    }

    private func processAudioLevel(buffer: AVAudioPCMBuffer) {
        let raw = Self.rmsNormalized(from: buffer)
        levelProcessQueue.async { [weak self] in
            guard let self else { return }
            let next = CGFloat(raw)
            let s = self.smoothedLevelInternal * (1 - self.levelSmoothingAlpha) + next * self.levelSmoothingAlpha
            self.smoothedLevelInternal = s
            DispatchQueue.main.async {
                self.smoothedInputLevel = s
                self.evaluateAuroraPulse()
            }
        }
    }

    private func evaluateAuroraPulse() {
        guard isRecording else { return }
        guard Self.containsChinese(liveTranscript) else { return }
        guard Date() > pulseCooldownUntil else { return }

        let l = smoothedInputLevel
        if l < quietLevelThreshold {
            levelInQuietBand = true
            return
        }
        if levelInQuietBand && l > speechLevelThreshold {
            levelInQuietBand = false
            auroraPulseToken &+= 1
            pulseCooldownUntil = Date().addingTimeInterval(pulseCooldown)
        }
    }

    /// 结束录音时 cancel recognition task 产生的错误，不应关闭极光
    private static func isBenignEndOfSpeechTaskError(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
            return true
        }
        return false
    }

    /// CJK 统一汉字 + 扩展 A 区，用于区分「有中文转写」与咳嗽等无文本输入
    private static func containsChinese(_ s: String) -> Bool {
        s.unicodeScalars.contains { u in
            let v = u.value
            return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
        }
    }

    private static func rmsNormalized(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return 0 }

        var sum: Float = 0
        for ch in 0..<channelCount {
            let ptr = channelData[ch]
            for i in 0..<frames {
                let s = ptr[i]
                sum += s * s
            }
        }
        let count = Float(frames * channelCount)
        let rms = sqrt(sum / max(count, 1))
        // 柔和映射到 0…1，避免环境底噪长期顶满
        let gain: Float = 28
        return min(1, rms * gain)
    }

    private func teardownRecordingSession() {
        isRecording = false
        isLocked = false

        timer?.invalidate()
        timer = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        audioFile = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        smoothedLevelInternal = 0
        smoothedInputLevel = 0
        levelInQuietBand = true
    }

    func endRecording() {
        guard isRecording else { return }
        teardownRecordingSession()
        recognitionPipelineFailed = false
        refreshAuroraPolicy()

        let now = Date()
        let start = currentStartDate ?? now
        let duration = max(1, Int(now.timeIntervalSince(start)))

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd • HH:mm"

        let meta = formatter.string(from: now)
        let durationText = String(format: "%02d:%02d", duration / 60, duration % 60)
        let transcriptText = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let segmentId = UUID()
        let transcript = transcriptText.isEmpty ? "（未识别到语音）" : transcriptText
        Task { @MainActor in
            DreamRecordingSession.shared.appendPhoneSegment(
                id: segmentId,
                occurredAt: now,
                meta: meta,
                durationText: durationText,
                transcript: transcript,
                audioFileURL: segmentAudioURL
            )
        }
        segmentAudioURL = nil

        Analytics.track("recording_segment_finished", properties: [
            "duration": duration,
            "hasTranscript": !transcriptText.isEmpty
        ])

        currentStartDate = nil
        currentDuration = 0
        liveTranscript = ""
    }

    func lockRecording() {
        guard isRecording else { return }
        isLocked = true
    }

    func dismissOrganizing() {
        stopOrganizingComfortRotation()
        isProcessingDream = false
        processingError = nil
        organizingShowsSuccess = false
        organizingAuroraCalm = false
        resetOrganizingPresentation()
    }

    private func resetOrganizingPresentation() {
        stopOrganizingComfortRotation()
        organizingPhase = .preparing
        organizingStatusMessage = DreamOrganizingPhase.preparing.defaultStatusMessage
        organizingUploadedCount = 0
        organizingSegmentTotal = 0
    }

    private func setOrganizingPhase(_ phase: DreamOrganizingPhase, message: String? = nil) {
        organizingPhase = phase
        if let message {
            stopOrganizingComfortRotation()
            organizingStatusMessage = message
        } else if phase == .complete {
            stopOrganizingComfortRotation()
            organizingStatusMessage = phase.defaultStatusMessage
        } else {
            startOrganizingComfortRotation(for: phase)
        }
    }

    private func startOrganizingComfortRotation(for phase: DreamOrganizingPhase) {
        stopOrganizingComfortRotation()
        let messages = phase.comfortMessages
        guard !messages.isEmpty else { return }
        organizingStatusMessage = messages[0]
        guard messages.count > 1 else { return }

        var index = 0
        organizingComfortTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                guard !Task.isCancelled else { break }
                index = (index + 1) % messages.count
                organizingStatusMessage = messages[index]
            }
        }
    }

    private func stopOrganizingComfortRotation() {
        organizingComfortTask?.cancel()
        organizingComfortTask = nil
    }

    func finishAllSegments() {
        guard hasSelectedSegments else { return }
        if isProcessingDream, processingError == nil, !organizingShowsSuccess { return }

        let now = Date()
        let sorted = segments
            .filter(\.isSelected)
            .sorted { $0.occurredAt < $1.occurredAt }
        let segmentCount = sorted.count

        isProcessingDream = true
        processingError = nil
        organizingShowsSuccess = false
        organizingSegmentTotal = segmentCount
        organizingUploadedCount = 0
        setOrganizingPhase(.preparing)

        Task { @MainActor in
            let dreamId = DreamRecordingSession.shared.dreamId ?? DreamRecordingSession.shared.startIfNeeded()
            do {
                try await AuthService.shared.ensureAnonymousSession()
                try await DreamService.shared.createDream(id: dreamId, occurredAt: now)

                setOrganizingPhase(.uploading)
                let uploadSegments = sorted.enumerated().map { idx, seg in
                    let transcript = seg.source == .watch && seg.transcript.isEmpty ? "" : seg.transcript
                    return (index: idx, transcript: transcript, audioURL: seg.audioFileURL)
                }
                try await DreamService.shared.uploadSegments(
                    dreamId: dreamId,
                    segments: uploadSegments
                ) { [weak self] uploaded, total in
                    Task { @MainActor in
                        self?.organizingUploadedCount = uploaded
                        self?.organizingSegmentTotal = total
                    }
                }

                setOrganizingPhase(.transcribing)
                try await DreamService.shared.finalizeRecording(dreamId: dreamId)

                setOrganizingPhase(.analyzing)
                let detail = try await DreamService.shared.pollUntilAnalyzed(dreamId: dreamId)

                guard var dream = DreamService.shared.dream(from: detail) else {
                    throw APIError.server("无法解析梦析结果")
                }
                DreamService.shared.applyServerDetail(detail, to: &dream)
                DreamStore.shared.upsert(dream)
                DreamRecordingSession.shared.clear()
                segments.removeAll()

                Analytics.track("dream_recording_finished", properties: [
                    "dreamId": dream.id.uuidString,
                    "segmentCount": segmentCount,
                    "source": "server_ai"
                ])

                WatchNotificationBridge.shared.notifyDreamAnalyzed(dreamId: dream.id)

                organizingShowsSuccess = true
                setOrganizingPhase(.complete)
                try await Task.sleep(nanoseconds: DreamOrganizingTiming.successDisplayNanoseconds)
                isProcessingDream = false
                resetOrganizingPresentation()
                try await Task.sleep(nanoseconds: DreamOrganizingTiming.postDismissNavigateNanoseconds)
                onFinishRecording?(dream.id)
            } catch {
                processingError = error.localizedDescription
                #if DEBUG
                let raw = sorted.map(\.transcript).joined(separator: "。")
                let organized = MockAIService.organizeAndInterpret(rawTranscript: raw, createdAt: now)
                let dream = Dream(
                    id: dreamId,
                    createdAt: now,
                    rawTranscript: raw,
                    organizedText: organized.organizedText,
                    interpretation: organized.interpretation,
                    tags: organized.tags,
                    title: organized.title,
                    note: nil,
                    isArchived: false,
                    comicArtifacts: []
                )
                DreamStore.shared.upsert(dream)
                DreamRecordingSession.shared.clear()
                segments.removeAll()
                WatchNotificationBridge.shared.notifyDreamAnalyzed(dreamId: dream.id)
                organizingShowsSuccess = true
                setOrganizingPhase(.complete)
                try? await Task.sleep(nanoseconds: DreamOrganizingTiming.successDisplayNanoseconds)
                isProcessingDream = false
                resetOrganizingPresentation()
                try? await Task.sleep(nanoseconds: DreamOrganizingTiming.postDismissNavigateNanoseconds)
                onFinishRecording?(dream.id)
                #endif
            }
        }
    }

    func deleteSegment(id: UUID) {
        Task { @MainActor in
            DreamRecordingSession.shared.removeDraft(id: id)
        }
    }
}
