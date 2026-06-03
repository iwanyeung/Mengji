import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    /// MainTabView 注入：收到四格推送后切 Tab。
    var onVisualPush: ((String) async -> Void)?

    private var didRequestAuthorization = false
    private let pendingVisualIdKey = "com.mengji.pendingPushVisualId"
    private let pendingOpenResultKey = "com.mengji.pendingPushOpenResult"

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// 冷启动或未就绪时暂存推送，待 MainTabView 就绪后 drain。
    func enqueueRemoteNotification(_ userInfo: [AnyHashable: Any], openResult: Bool) {
        guard let visualId = visualId(from: userInfo) else { return }
        UserDefaults.standard.set(visualId, forKey: pendingVisualIdKey)
        if openResult {
            UserDefaults.standard.set(true, forKey: pendingOpenResultKey)
        }
    }

    func processPendingPushIfNeeded() async {
        guard let visualId = UserDefaults.standard.string(forKey: pendingVisualIdKey) else { return }
        let openResult = UserDefaults.standard.bool(forKey: pendingOpenResultKey)
        UserDefaults.standard.removeObject(forKey: pendingVisualIdKey)
        UserDefaults.standard.removeObject(forKey: pendingOpenResultKey)
        await handleRemoteNotification(
            userInfo: ["visualId": visualId],
            openResult: openResult
        )
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
        guard let visualId = visualId(from: userInfo) else { return }

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
    }

    private func visualId(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo["visualId"] as? String
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
        let userInfo = notification.request.content.userInfo
        await handleRemoteNotification(userInfo: userInfo, openResult: false)
        return [.banner, .sound]
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
        }
        // iOS 26+：launchOptions[.remoteNotification] 已弃用；点按通知由
        // UNUserNotificationCenterDelegate.didReceive 处理，后台推送见下方 fetchCompletionHandler。
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
            let hasPayload = PushNotificationService.shared.hasVisualPayload(userInfo)
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
