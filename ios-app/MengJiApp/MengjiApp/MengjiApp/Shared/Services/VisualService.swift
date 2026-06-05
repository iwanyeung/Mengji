import Foundation

struct Entitlements: Decodable {
    let freeComicsRemaining: Int
    let freeComicsTotal: Int
    let hasRedeemedInvite: Bool
    let inviteChannelLabel: String?
}

struct EntitlementService {
    static let shared = EntitlementService()

    func fetch() async throws -> Entitlements {
        try await APIClient.shared.request("GET", path: "api/me/entitlements")
    }

    func redeem(code: String) async throws -> String {
        struct Body: Encodable { let code: String }
        struct Resp: Decodable { let message: String }
        let resp: Resp = try await APIClient.shared.request("POST", path: "api/invite/redeem", body: Body(code: code))
        return resp.message
    }
}

struct VisualJob: Decodable {
    let visualId: String
    let status: String
    let reused: Bool?
    let imageUrls: [String]?
    let imageThumbUrls: [String]?
}

struct VisualDetail: Decodable {
    let id: String
    let dreamId: String
    let status: String
    let styleKey: String?
    let imageUrls: [String]?
    let imageThumbUrls: [String]?
    /// 生成中逐格写入，未完成的格为 null
    let imageUrlsPartial: [String?]?
    let imageThumbUrlsPartial: [String?]?
    let failureReason: String?
    let failureCode: String?
    let userMessage: String?
    let quotaRefunded: Bool?
    let successfulPanelCount: Int?
    let readinessLevelAtGen: String?
    let storyboardMode: String?
    let fidelityFeedback: String?
    let compensationRedeemed: Bool?
    let compensationForVisualId: String?
    let storyboardCaptions: [VisualStoryboardCaption]?

    struct VisualStoryboardCaption: Decodable {
        let panelIndex: Int
        let caption: String
        let source: String
    }
}

struct VisualService {
    static let shared = VisualService()

    func createFourPanel(
        dreamId: UUID,
        styleKey: String,
        transactionJws: String?,
        forceNew: Bool = false,
        compensationForVisualId: String? = nil,
        forceImageryMode: Bool = false
    ) async throws -> VisualJob {
        struct Body: Encodable {
            let dreamId: String
            let styleKey: String
            let transactionJws: String?
            let forceNew: Bool
            let compensationForVisualId: String?
            let forceImageryMode: Bool
        }
        return try await APIClient.shared.request(
            "POST",
            path: "api/visuals/four-panel",
            body: Body(
                dreamId: dreamId.uuidString.lowercased(),
                styleKey: styleKey,
                transactionJws: transactionJws,
                forceNew: forceNew,
                compensationForVisualId: compensationForVisualId,
                forceImageryMode: forceImageryMode
            )
        )
    }

    func submitFidelityFeedback(
        visualId: String,
        feedback: ComicFidelityFeedback,
        optionalNote: String? = nil
    ) async throws -> ComicFidelityFeedbackResponse {
        struct Body: Encodable {
            let feedback: String
            let optionalNote: String?
        }
        return try await APIClient.shared.request(
            "POST",
            path: "api/visuals/\(visualId)/fidelity-feedback",
            body: Body(feedback: feedback.rawValue, optionalNote: optionalNote)
        )
    }

    func fetch(visualId: String) async throws -> VisualDetail {
        try await APIClient.shared.request("GET", path: "api/visuals/\(visualId)")
    }

    func fetchAuthorized(visualId: String) async throws -> VisualDetail {
        try await AuthService.shared.withAuthorizedSession {
            try await fetch(visualId: visualId)
        }
    }

    struct PendingVisualItem: Decodable {
        let visualId: String
        let dreamId: String
        let styleKey: String
        let status: String
        let successfulPanelCount: Int?
    }

    func fetchPendingVisuals() async throws -> [PendingVisualItem] {
        struct Resp: Decodable { let items: [PendingVisualItem] }
        let resp: Resp = try await AuthService.shared.withAuthorizedSession {
            try await APIClient.shared.request("GET", path: "api/me/pending-visuals")
        }
        return resp.items
    }

    func pollUntilDone(visualId: String, maxAttempts: Int = 120, onProgress: ((VisualDetail) -> Void)? = nil) async throws -> VisualDetail {
        for attempt in 0..<maxAttempts {
            let detail = try await fetchAuthorized(visualId: visualId)
            onProgress?(detail)
            if detail.status == "succeeded" || detail.status == "failed" {
                return detail
            }
            let intervalNs: UInt64 = attempt < 20 ? 1_000_000_000 : 2_000_000_000
            try await Task.sleep(nanoseconds: intervalNs)
        }
        throw APIError.server("漫画生成超时")
    }
}
