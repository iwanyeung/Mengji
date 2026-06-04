import SwiftUI

@main
struct MengjiWatchApp: App {
    init() {
        WatchConnectivitySender.shared.activate()
        WatchNotificationHandler.shared.configure()
        Task {
            await WatchNotificationHandler.shared.requestAuthorizationIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchRecordingView()
        }
    }
}
