import Foundation
import Combine

struct UserSession {
    var anonymousId: UUID
    var isLoggedIn: Bool
}

final class UserSessionStore: ObservableObject {
    static let shared = UserSessionStore()

    @Published private(set) var session: UserSession

    private init() {
        let stored = UserDefaults.standard.string(forKey: "user.anonymousId")
        let id = UUID(uuidString: stored ?? "") ?? UUID()
        if stored == nil {
            UserDefaults.standard.set(id.uuidString, forKey: "user.anonymousId")
        }
        self.session = UserSession(anonymousId: id, isLoggedIn: false)
    }
}

