import Foundation
import WatchConnectivity

/// 真机排查：iPhone 安装包是否含嵌套手表 App、系统是否认为手表已安装。
enum WatchCompanionDiagnostics {
    private static var embeddedWatchPath: String {
        Bundle.main.bundlePath + "/Watch/MengjiWatch.app"
    }

    static func logInstalledBundleState() {
        #if DEBUG
        let embeddedExists = FileManager.default.fileExists(atPath: embeddedWatchPath)
        let session = WCSession.isSupported() ? WCSession.default : nil
        print("[WatchDiag] iPhoneBundleHasEmbeddedWatch=\(embeddedExists)")
        if embeddedExists, let info = Bundle(path: embeddedWatchPath)?.infoDictionary {
            let bid = info["CFBundleIdentifier"] as? String ?? "?"
            let companion = info["WKCompanionAppBundleIdentifier"] as? String ?? "?"
            print("[WatchDiag] embeddedBundleId=\(bid) WKCompanion=\(companion)")
        } else {
            print("[WatchDiag] missing path=\(embeddedWatchPath)")
            print("[WatchDiag] fix: Clean → ⌘R to iPhone; confirm Embed Watch Content + CodeSignOnCopy")
        }
        if let session {
            print(
                "[WatchDiag] isPaired=\(session.isPaired) " +
                "isWatchAppInstalled=\(session.isWatchAppInstalled) " +
                "isReachable=\(session.isReachable)"
            )
            if embeddedExists, !session.isWatchAppInstalled {
                print(
                    "[WatchDiag] embedded OK but watch not installed → " +
                    "iPhone「Watch」打开「在 Apple Watch 上显示 App」; " +
                    "或在 Mac Console 选 **iPhone** 搜 installd / watchkitapp（不是搜 installed）"
                )
            }
        }
        #endif
    }
}
