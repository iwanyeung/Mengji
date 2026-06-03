import Foundation

struct AuthService {
    static let shared = AuthService()

    func ensureAnonymousSession() async throws {
        if APIClient.authToken != nil { return }
        try await createAnonymousSession()
    }

    /// 401 时清 token 并重登后重试一次，避免短暂鉴权失败清掉进行中的漫画任务。
    func withAuthorizedSession<T>(_ operation: () async throws -> T) async throws -> T {
        try await ensureAnonymousSession()
        do {
            return try await operation()
        } catch APIError.unauthorized {
            APIClient.clearAuthToken()
            try await createAnonymousSession()
            return try await operation()
        }
    }

    private func createAnonymousSession() async throws {
        let deviceId = UserSessionStore.shared.session.anonymousId.uuidString
        struct Resp: Decodable {
            let token: String
        }
        let resp: Resp = try await APIClient.shared.request("POST", path: "api/auth/anonymous", body: ["deviceId": deviceId])
        APIClient.authToken = resp.token
    }

    func syncAppleLogin(appleUserId: String) async {
        do {
            try await ensureAnonymousSession()
            let deviceId = UserSessionStore.shared.session.anonymousId.uuidString
            struct Resp: Decodable { let token: String }
            let resp: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/auth/apple",
                body: ["appleUserId": appleUserId, "deviceId": deviceId]
            )
            APIClient.authToken = resp.token
            await DreamSyncService.shared.syncFromServerAndWait()
        } catch {
            print("Apple auth sync failed:", error)
        }
    }
}
