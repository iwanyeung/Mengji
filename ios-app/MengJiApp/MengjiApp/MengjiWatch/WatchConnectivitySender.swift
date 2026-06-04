import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivitySender: NSObject, ObservableObject {
    static let shared = WatchConnectivitySender()

    @Published private(set) var isReachable = false
    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    private(set) var lastApplicationContext: [String: Any] = [:]

    var onApplicationContextUpdated: (([String: Any]) -> Void)?
    var onNotifyEvent: ((String, [String: Any]) -> Void)?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendDreamAudio(
        fileURL: URL,
        dreamId: UUID,
        occurredAt: Date,
        duration: TimeInterval,
        segmentIndex: Int,
        segmentId: UUID
    ) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let metadata: [String: Any] = [
            WatchConnectivityMetadata.dreamId: dreamId.uuidString.lowercased(),
            WatchConnectivityMetadata.occurredAt: ISO8601DateFormatter().string(from: occurredAt),
            WatchConnectivityMetadata.source: "watch",
            WatchConnectivityMetadata.durationSeconds: duration,
            WatchConnectivityMetadata.segmentIndex: segmentIndex,
            WatchConnectivityMetadata.segmentId: segmentId.uuidString.lowercased(),
        ]

        _ = session.transferFile(fileURL, metadata: metadata)
    }
}

extension WatchConnectivitySender: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.activationState = activationState
            self.isReachable = session.isReachable
            self.lastApplicationContext = session.receivedApplicationContext
            self.onApplicationContextUpdated?(session.receivedApplicationContext)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.lastApplicationContext = applicationContext
            self.onApplicationContextUpdated?(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.handleNotifyPayload(userInfo)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleNotifyPayload(message)
        }
    }

    private func handleNotifyPayload(_ payload: [String: Any]) {
        guard let event = payload[WatchConnectivityMetadata.notifyEvent] as? String else { return }
        onNotifyEvent?(event, payload)
    }
}
