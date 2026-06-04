import Combine
import Foundation
import WatchConnectivity

extension Notification.Name {
    /// 手表录音段已写入手机草稿池；`userInfo`: dreamId, segmentIndex
    static let watchDreamSegmentReceived = Notification.Name("mengji.watchDreamSegmentReceived")
    /// 手表录音整理失败；`userInfo["message"]` 为 `String`
    static let watchDreamIngestFailed = Notification.Name("mengji.watchDreamIngestFailed")
}

@MainActor
final class WatchDreamIngestService: NSObject, ObservableObject {
    static let shared = WatchDreamIngestService()

    private var isActivated = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        guard !isActivated else { return }
        isActivated = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
        DreamRecordingSession.shared.publishContextToWatch()
    }
}

extension WatchDreamIngestService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        #if DEBUG
        if let error {
            print("[WatchIngest] activation error: \(error)")
        }
        Task { @MainActor in
            print(
                "[WatchIngest] activation=\(activationState.rawValue) " +
                "isPaired=\(session.isPaired) isWatchAppInstalled=\(session.isWatchAppInstalled)"
            )
        }
        #endif
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let segmentId = (metadata[WatchIncomingFileStaging.segmentIdMetadataKey] as? String)
            .flatMap { UUID(uuidString: $0) } ?? UUID()
        let stagedURL = WatchIncomingFileStaging.copy(from: file.fileURL, segmentId: segmentId)

        #if DEBUG
        if stagedURL == nil {
            let exists = FileManager.default.fileExists(atPath: file.fileURL.path)
            print("[WatchIngest] stage failed segmentId=\(segmentId) sourceExists=\(exists)")
        }
        #endif

        Task { @MainActor in
            if let stagedURL {
                self.processStagedAudio(at: stagedURL, metadata: metadata)
            } else {
                self.notifyFailure("无法保存手表录音文件")
            }
        }
    }
}

// MARK: - Draft ingest

extension WatchDreamIngestService {
    private func processStagedAudio(at audioURL: URL, metadata: [String: Any]) {
        let dreamIdFromWatch = (metadata[WatchConnectivityMetadata.dreamId] as? String)
            .flatMap { UUID(uuidString: $0) }
        let segmentId = (metadata[WatchConnectivityMetadata.segmentId] as? String)
            .flatMap { UUID(uuidString: $0) } ?? UUID()
        let segmentIndex = metadata[WatchConnectivityMetadata.segmentIndex] as? Int ?? 0
        let occurredAt = parseOccurredAt(metadata[WatchConnectivityMetadata.occurredAt] as? String) ?? Date()
        let duration = metadata[WatchConnectivityMetadata.durationSeconds] as? TimeInterval ?? 0

        let draft = DreamRecordingSession.shared.appendWatchSegment(
            audioURL: audioURL,
            occurredAt: occurredAt,
            duration: duration,
            segmentIndex: segmentIndex,
            segmentId: segmentId,
            dreamIdFromWatch: dreamIdFromWatch
        )

        let dreamId = DreamRecordingSession.shared.dreamId ?? draft.id
        NotificationCenter.default.post(
            name: .watchDreamSegmentReceived,
            object: nil,
            userInfo: [
                "dreamId": dreamId,
                "segmentIndex": segmentIndex,
            ]
        )
    }

    private func parseOccurredAt(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func notifyFailure(_ message: String) {
        NotificationCenter.default.post(
            name: .watchDreamIngestFailed,
            object: nil,
            userInfo: ["message": message]
        )
    }
}
