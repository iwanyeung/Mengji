import AVFoundation
import Foundation

enum WatchAudioRecorderError: LocalizedError {
    case permissionDenied
    case failedToStart
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "请在手表「设置 › 隐私 › 麦克风」中允许梦悸使用麦克风。"
        case .failedToStart:
            return "录音启动失败，请稍后再试。"
        case .noActiveRecording:
            return "当前没有进行中的录音。"
        }
    }
}

@MainActor
final class WatchAudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var duration: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var timer: Timer?

    func requestPermissionIfNeeded() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func start() throws {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-dream-\(UUID().uuidString).m4a")
        outputURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record() else {
            throw WatchAudioRecorderError.failedToStart
        }
        self.recorder = recorder
        isRecording = true
        duration = 0

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.duration = recorder.currentTime
            }
        }
    }

    func stop() throws -> URL {
        guard isRecording, let recorder, let url = outputURL else {
            throw WatchAudioRecorderError.noActiveRecording
        }
        timer?.invalidate()
        timer = nil
        recorder.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        self.recorder = nil
        outputURL = nil
        return url
    }
}

extension WatchAudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            if self.isRecording {
                self.timer?.invalidate()
                self.timer = nil
                self.isRecording = false
                self.recorder = nil
            }
        }
    }
}
