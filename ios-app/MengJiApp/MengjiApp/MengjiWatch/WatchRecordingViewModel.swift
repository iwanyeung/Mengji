import Foundation

enum WatchRecordingPhase: Equatable {
    case idle
    case recording
    case segmentSent
    case permissionDenied
    case error(String)
}

@MainActor
final class WatchRecordingViewModel: ObservableObject {
    @Published private(set) var phase: WatchRecordingPhase = .idle
    @Published private(set) var durationText = "0:00"
    @Published private(set) var segmentCount = 0

    private let audioRecorder = WatchAudioRecorder()
    private let connectivity = WatchConnectivitySender.shared
    private var resetTask: Task<Void, Never>?

    private static let activeDreamIdKey = "com.mengji.watch.activeDreamId"
    private static let nextSegmentIndexKey = "com.mengji.watch.nextSegmentIndex"

    private var sessionDreamId: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.activeDreamIdKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString.lowercased(), forKey: Self.activeDreamIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activeDreamIdKey)
            }
        }
    }

    private var nextSegmentIndex: Int {
        get { UserDefaults.standard.integer(forKey: Self.nextSegmentIndexKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.nextSegmentIndexKey) }
    }

    init() {
        connectivity.activate()
        connectivity.onApplicationContextUpdated = { [weak self] context in
            self?.applyApplicationContext(context)
        }
        applyApplicationContext(connectivity.lastApplicationContext)
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    func handlePrimaryTap() async {
        resetTask?.cancel()
        switch phase {
        case .idle, .segmentSent, .error, .permissionDenied:
            await startRecording()
        case .recording:
            await stopAndSend()
        }
    }

    private func startRecording() async {
        let granted = await audioRecorder.requestPermissionIfNeeded()
        guard granted else {
            phase = .permissionDenied
            scheduleReset(after: 3)
            return
        }
        do {
            try audioRecorder.start()
            phase = .recording
        } catch {
            phase = .error(error.localizedDescription)
            scheduleReset(after: 2.5)
        }
    }

    private func stopAndSend() async {
        do {
            let duration = audioRecorder.duration
            let fileURL = try audioRecorder.stop()
            let dreamId = ensureSessionDreamId()
            let segmentIndex = nextSegmentIndex
            let segmentId = UUID()
            let occurredAt = Date()

            connectivity.sendDreamAudio(
                fileURL: fileURL,
                dreamId: dreamId,
                occurredAt: occurredAt,
                duration: duration,
                segmentIndex: segmentIndex,
                segmentId: segmentId
            )

            nextSegmentIndex = segmentIndex + 1
            segmentCount = nextSegmentIndex
            phase = .segmentSent
        } catch {
            phase = .error(error.localizedDescription)
            scheduleReset(after: 2.5)
        }
    }

    private func ensureSessionDreamId() -> UUID {
        if let sessionDreamId { return sessionDreamId }
        let id = UUID()
        sessionDreamId = id
        nextSegmentIndex = 0
        segmentCount = 0
        return id
    }

    private func applyApplicationContext(_ context: [String: Any]) {
        if let raw = context[WatchConnectivityMetadata.activeDreamId] as? String,
           let id = UUID(uuidString: raw) {
            sessionDreamId = id
            if let count = context[WatchConnectivityMetadata.draftCount] as? Int {
                nextSegmentIndex = count
                segmentCount = count
            }
        } else if context.isEmpty {
            sessionDreamId = nil
            nextSegmentIndex = 0
            segmentCount = 0
            if phase == .segmentSent {
                phase = .idle
            }
        }
    }

    private func scheduleReset(after seconds: TimeInterval) {
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if case .permissionDenied = phase {
                phase = .idle
            } else if case .error = phase {
                phase = .idle
            }
            durationText = "0:00"
        }
    }

    func updateDurationDisplay() {
        guard case .recording = phase else { return }
        let total = Int(audioRecorder.duration)
        let minutes = total / 60
        let seconds = total % 60
        durationText = String(format: "%d:%02d", minutes, seconds)
    }
}
