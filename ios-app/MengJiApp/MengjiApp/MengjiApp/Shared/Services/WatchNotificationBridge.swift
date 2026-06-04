import Foundation
import WatchConnectivity

/// iPhone → Apple Watch：整理完成、漫画落成等事件（WCSession 为主通道）。
@MainActor
final class WatchNotificationBridge {
    static let shared = WatchNotificationBridge()

    enum Event: String {
        case dreamAnalyzed = "dream_analyzed"
        case comicReady = "comic_ready"
    }

    private init() {}

    func notifyDreamAnalyzed(dreamId: UUID) {
        send(event: .dreamAnalyzed, dreamId: dreamId, visualId: nil)
    }

    func notifyComicReady(visualId: String, dreamId: UUID) {
        send(event: .comicReady, dreamId: dreamId, visualId: visualId)
    }

    private func send(event: Event, dreamId: UUID, visualId: String?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        var payload: [String: Any] = [
            WatchConnectivityMetadata.notifyEvent: event.rawValue,
            WatchConnectivityMetadata.dreamId: dreamId.uuidString.lowercased(),
            "sentAt": ISO8601DateFormatter().string(from: Date()),
        ]
        if let visualId {
            payload[WatchConnectivityMetadata.notifyVisualId] = visualId
        }

        session.transferUserInfo(payload)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                #if DEBUG
                print("[WatchNotify] sendMessage failed:", error.localizedDescription)
                #endif
            }
        }
    }
}
