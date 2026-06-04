import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    /// 收到四格推送后切 Tab / 刷新梦作间
    var onVisualPush: ((String) async -> Void)?
    /// 收到梦析完成推送后打开梦析
    var onDreamAnalyzedPush: ((UUID) async -> Void)?

    private var didRequestAuthorization = false
    private let pendingVisualIdKey = "com.mengji.pendingPushVisualId"
    private let pendingDreamIdKey = "com.mengji.pendingPushDreamId"
    private let pendingOpenResultKey = "com.mengji.pendingPushOpenResult"

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func enqueueRemoteNotification(_ userInfo: [AnyHashable: Any], openResult: Bool) {
        if let visualId = visualId(from: userInfo) {
            UserDefaults.standard.set(visualId, forKey: pendingVisualIdKey)
        } else if let dreamId = dreamId(from: userInfo) {
            UserDefaults.standard.set(dreamId.uuidString, forKey: pendingDreamIdKey)
        } else {
            return
        }
        if openResult {
            UserDefaults.standard.set(true, forKey: pendingOpenResultKey)
        }
    }

    func processPendingPushIfNeeded() async {
        let openResult = UserDefaults.standard.bool(forKey: pendingOpenResultKey)
        if let visualId = UserDefaults.standard.string(forKey: pendingVisualIdKey) {
            UserDefaults.standard.removeObject(forKey: pendingVisualIdKey)
            UserDefaults.standard.removeObject(forKey: pendingOpenResultKey)
            await handleRemoteNotification(userInfo: ["type": "visual_done", "visualId": visualId], openResult: openResult)
            return
        }
        if let dreamRaw = UserDefaults.standard.string(forKey: pendingDreamIdKey),
           let dreamId = UUID(uuidString: dreamRaw) {
            UserDefaults.standard.removeObject(forKey: pendingDreamIdKey)
            UserDefaults.standard.removeObject(forKey: pendingOpenResultKey)
            await handleRemoteNotification(
                userInfo: ["type": "dream_analyzed", "dreamId": dreamId.uuidString.lowercased()],
                openResult: openResult
            )
        }
    }

    func requestAuthorizationIfNeeded() async {
        guard !didRequestAuthorization else {
            await registerForRemoteNotificationsIfAuthorized()
            return
        }
        didRequestAuthorization = true

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await registerForRemoteNotificationsIfAuthorized()
            }
        } catch {
            print("[push] authorization failed:", error)
        }
    }

    private func registerForRemoteNotificationsIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            await uploadToken(token)
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        print("[push] register failed:", error)
    }

    private func uploadToken(_ token: String) async {
        do {
            try await AuthService.shared.ensureAnonymousSession()
            struct Body: Encodable {
                let token: String
                let environment: String
            }
            struct Resp: Decodable { let ok: Bool }
            #if DEBUG
            let environment = "sandbox"
            #else
            let environment = "production"
            #endif
            let _: Resp = try await APIClient.shared.request(
                "PUT",
                path: "api/me/push-token",
                body: Body(token: token, environment: environment)
            )
        } catch {
            print("[push] upload token failed:", error)
        }
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any], openResult: Bool = false) async {
        let pushType = (userInfo["type"] as? String) ?? (visualId(from: userInfo) != nil ? "visual_done" : nil)

        switch pushType {
        case "dream_analyzed":
            guard let dreamId = dreamId(from: userInfo) else { return }
            WatchNotificationBridge.shared.notifyDreamAnalyzed(dreamId: dreamId)
            if openResult, let onDreamAnalyzedPush {
                await onDreamAnalyzedPush(dreamId)
            } else if onDreamAnalyzedPush == nil {
                enqueueRemoteNotification(userInfo, openResult: openResult)
            }
        case "visual_done", "visual_failed":
            guard let visualId = visualId(from: userInfo) else { return }
            let dreamId = dreamId(from: userInfo)
            if let dreamId {
                WatchNotificationBridge.shared.notifyComicReady(visualId: visualId, dreamId: dreamId)
            }
            if let onVisualPush {
                await onVisualPush(visualId)
            } else {
                enqueueRemoteNotification(userInfo, openResult: openResult)
                return
            }
            await ComicGenerationJobStore.shared.ingestRemoteVisual(
                visualId: visualId,
                openResultAutomatically: openResult
            )
        default:
            if let visualId = visualId(from: userInfo) {
                await handleRemoteNotification(
                    userInfo: ["type": "visual_done", "visualId": visualId],
                    openResult: openResult
                )
            }
        }
    }

    private func visualId(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo["visualId"] as? String
    }

    private func dreamId(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let raw = userInfo["dreamId"] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    func hasActionablePayload(_ userInfo: [AnyHashable: Any]) -> Bool {
        if let type = userInfo["type"] as? String, type == "dream_analyzed" {
            return dreamId(from: userInfo) != nil
        }
        return visualId(from: userInfo) != nil
    }

    func hasVisualPayload(_ userInfo: [AnyHashable: Any]) -> Bool {
        visualId(from: userInfo) != nil
    }
}

extension PushNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        let userInfo = content.userInfo
        await handleRemoteNotification(userInfo: userInfo, openResult: false)

        await MainActor.run {
            MengjiPushBannerPresenter.show(
                title: content.title.isEmpty ? "梦悸" : content.title,
                body: content.body
            )
        }
        return [.sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        await handleRemoteNotification(userInfo: userInfo, openResult: true)
    }
}

final class MengjiAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MainActor.assumeIsolated {
            PushNotificationService.shared.configure()
            WatchCompanionDiagnostics.logInstalledBundleState()
            WatchDreamIngestService.shared.activate()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            await PushNotificationService.shared.handleRemoteNotification(
                userInfo: userInfo,
                openResult: false
            )
            let hasPayload = PushNotificationService.shared.hasActionablePayload(userInfo)
            completionHandler(hasPayload ? .newData : .noData)
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleRegistrationFailure(error)
        }
    }
}
