import Foundation
import Combine
import AVFoundation
import Speech

final class RecordingViewModel: ObservableObject {
    struct Segment: Identifiable {
        let id: UUID
        let occurredAt: Date
        let meta: String
        let durationText: String
        var transcript: String
    }

    /// 录梦完成并整理时回调，传入新梦的 ID（用于跳转梦析）
    var onFinishRecording: ((UUID) -> Void)?

    @Published var segments: [Segment] = []
    @Published var isRecording: Bool = false
    @Published var isLocked: Bool = false
    @Published var currentDuration: TimeInterval = 0
    @Published var liveTranscript: String = ""
    @Published var speechAuthDenied: Bool = false

    private var currentStartDate: Date?
    private var timer: Timer?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

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

    func beginRecording() {
        guard !isRecording else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .authorized:
                    self.startRecordingSession()
                default:
                    self.speechAuthDenied = true
                }
            }
        }
    }

    private func startRecordingSession() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            speechAuthDenied = true
            return
        }

        isRecording = true
        isLocked = false
        currentStartDate = Date()
        currentDuration = 0
        liveTranscript = ""

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
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            isRecording = false
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.liveTranscript = text
                }
            } else if error != nil {
                DispatchQueue.main.async {
                    self.isRecording = false
                }
            }
        }
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        isLocked = false

        timer?.invalidate()
        timer = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        let now = Date()
        let start = currentStartDate ?? now
        let duration = max(1, Int(now.timeIntervalSince(start)))

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd • HH:mm"

        let meta = formatter.string(from: now)
        let durationText = String(format: "%02d:%02d", duration / 60, duration % 60)
        let transcriptText = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let segment = Segment(
            id: UUID(),
            occurredAt: now,
            meta: meta,
            durationText: durationText,
            transcript: transcriptText.isEmpty ? "（未识别到语音）" : transcriptText
        )
        segments.insert(segment, at: 0)

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

    func finishAllSegments() {
        guard !segments.isEmpty else { return }

        let now = Date()
        let raw = segments
            .sorted { $0.occurredAt < $1.occurredAt }
            .map { $0.transcript }
            .joined(separator: "。")

        let organized = MockAIService.organizeAndInterpret(rawTranscript: raw, createdAt: now)

        let dream = Dream(
            id: UUID(),
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
        segments.removeAll()

        Analytics.track("dream_recording_finished", properties: [
            "dreamId": dream.id.uuidString,
            "segmentCount": segments.count
        ])

        onFinishRecording?(dream.id)
    }

    func deleteSegment(id: UUID) {
        segments.removeAll { $0.id == id }
    }
}

