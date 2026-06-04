import Foundation
import UserNotifications

@MainActor
final class WatchNotificationHandler: NSObject {
    static let shared = WatchNotificationHandler()

    private var didRequestAuthorization = false

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        WatchConnectivitySender.shared.onNotifyEvent = { [weak self] event, payload in
            self?.handleConnectivityEvent(event, payload: payload)
        }
    }

    func requestAuthorizationIfNeeded() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func handleConnectivityEvent(_ event: String, payload: [String: Any]) {
        switch event {
        case "dream_analyzed":
            present(title: "梦析已完成", body: "请在 iPhone 上查看详情")
        case "comic_ready":
            present(title: "四格已落成", body: "请在 iPhone 梦作间查看")
        default:
            break
        }
    }

    private func present(title: String, body: String) {
        WatchHapticFeedback.playSuccess()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension WatchNotificationHandler: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            WatchHapticFeedback.playSuccess()
        }
        return [.banner, .sound]
    }
}
