import WatchKit

enum WatchHapticFeedback {
    static func playSuccess() {
        WKInterfaceDevice.current().play(.success)
    }
}
