import Foundation

enum Analytics {
    static func track(_ event: String, properties: [String: Any] = [:]) {
        #if DEBUG
        print("Analytics:", event, properties)
        #endif
    }
}

