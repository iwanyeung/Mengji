import Foundation
import Combine
import CryptoKit

struct UserSession: Equatable {
    var anonymousId: UUID
    var isLoggedIn: Bool
    /// Apple 返回的稳定用户标识（本地持久化，供日后对接云端）
    var appleUserIdentifier: String?
    /// 展示用姓名（首次授权时可能提供）
    var appleDisplayName: String?
    /// 用户可读的业务数字 ID（MVP 本机生成，后续可替换为服务端下发）
    var businessNumericId: String?
    var profile: UserProfile
}

final class UserSessionStore: ObservableObject {
    static let shared = UserSessionStore()

    @Published private(set) var session: UserSession

    private enum Keys {
        static let anonymousId = "user.anonymousId"
        static let isLoggedIn = "user.isLoggedIn"
        static let appleUserId = "user.appleUserId"
        static let appleDisplayName = "user.appleDisplayName"
        static let businessNumericId = "user.businessNumericId"
        static let profileJSON = "user.profileJSON"
    }

    private let defaults = UserDefaults.standard

    private init() {
        let stored = defaults.string(forKey: Keys.anonymousId)
        let id = UUID(uuidString: stored ?? "") ?? UUID()
        if stored == nil {
            defaults.set(id.uuidString, forKey: Keys.anonymousId)
        }

        let isLoggedIn = defaults.bool(forKey: Keys.isLoggedIn)
        let appleId = defaults.string(forKey: Keys.appleUserId)
        let displayName = defaults.string(forKey: Keys.appleDisplayName)
        let bizId = defaults.string(forKey: Keys.businessNumericId)
        let profile: UserProfile
        if let data = defaults.data(forKey: Keys.profileJSON),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = decoded
        } else {
            profile = .empty
        }

        self.session = UserSession(
            anonymousId: id,
            isLoggedIn: isLoggedIn,
            appleUserIdentifier: appleId,
            appleDisplayName: displayName,
            businessNumericId: bizId,
            profile: profile
        )
    }

    private func persist() {
        defaults.set(session.isLoggedIn, forKey: Keys.isLoggedIn)
        defaults.set(session.appleUserIdentifier, forKey: Keys.appleUserId)
        defaults.set(session.appleDisplayName, forKey: Keys.appleDisplayName)
        defaults.set(session.businessNumericId, forKey: Keys.businessNumericId)
        if let data = try? JSONEncoder().encode(session.profile) {
            defaults.set(data, forKey: Keys.profileJSON)
        }
    }

    private func stableNumericId(from appleUserId: String) -> String {
        let input = Data(appleUserId.utf8)
        let digest = SHA256.hash(data: input)
        let value = digest.withUnsafeBytes { UInt64(truncatingIfNeeded: $0.load(as: UInt64.self)) }
        let ten = String(format: "%010d", value % 10_000_000_000)
        return ten
    }

    /// 完成 Apple 登录（由 `ASAuthorization` 成功回调中调用，可在任意线程）
    func applyAppleAuthorization(
        appleUserId: String,
        fullName: PersonNameComponents?,
        email _: String?
    ) {
        runOnMain { [weak self] in
            guard let self else { return }
            var display = self.session.appleDisplayName
            if let full = fullName {
                let formatter = PersonNameComponentsFormatter()
                let name = formatter.string(from: full).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    display = name
                }
            }
            let biz: String
            if let existing = self.session.businessNumericId, self.session.appleUserIdentifier == appleUserId {
                biz = existing
            } else {
                biz = self.stableNumericId(from: appleUserId)
            }

            self.session = UserSession(
                anonymousId: self.session.anonymousId,
                isLoggedIn: true,
                appleUserIdentifier: appleUserId,
                appleDisplayName: display,
                businessNumericId: biz,
                profile: self.session.profile
            )
            self.persist()
        }
    }

    /// 调试：模拟 Apple 登录成功（无需系统弹窗）
    func simulateAppleSignInForDevelopment() {
        let mockId = "mock.apple.\(session.anonymousId.uuidString.prefix(8))"
        applyAppleAuthorization(
            appleUserId: mockId,
            fullName: PersonNameComponents(givenName: "演示", familyName: "用户"),
            email: nil
        )
    }

    func signOut() {
        runOnMain { [weak self] in
            guard let self else { return }
            self.session = UserSession(
                anonymousId: self.session.anonymousId,
                isLoggedIn: false,
                appleUserIdentifier: nil,
                appleDisplayName: nil,
                businessNumericId: nil,
                profile: .empty
            )
            self.persist()
        }
    }

    func updateProfile(_ profile: UserProfile) {
        runOnMain { [weak self] in
            guard let self else { return }
            guard self.session.isLoggedIn else { return }
            self.session = UserSession(
                anonymousId: self.session.anonymousId,
                isLoggedIn: self.session.isLoggedIn,
                appleUserIdentifier: self.session.appleUserIdentifier,
                appleDisplayName: self.session.appleDisplayName,
                businessNumericId: self.session.businessNumericId,
                profile: profile
            )
            self.persist()
        }
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
