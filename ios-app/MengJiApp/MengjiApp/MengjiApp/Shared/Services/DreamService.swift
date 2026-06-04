import Foundation

struct ServerDreamGraph: Decodable {
    let nodes: [ServerGraphNode]
    let edges: [ServerGraphEdge]

    struct ServerGraphNode: Decodable {
        let id: String
        let dateLabel: String?
        let tags: [String]?
        let snippet: String?
        let hasVisual: Bool?
    }

    struct ServerGraphEdge: Decodable {
        let id: String
        let from: String
        let to: String
        let score: Double?
        let sharedTags: [String]?
    }
}

struct ServerDreamDetail: Decodable {
    let id: String
    let occurredAt: String?
    let status: String
    let refinedNarrative: String?
    let analysisText: String?
    let title: String?
    let rawTranscript: String?
    let narrativeHash: String?
    let analysisNarrativeHash: String?
    let analysisRevision: Int?
    let analysisStale: Bool?
    let userTagsLocked: Bool?
    let tags: [ServerTag]?
    let feedback: ServerFeedback?
    let visuals: [ServerVisual]?

    struct ServerTag: Decodable {
        let name: String
    }

    struct ServerFeedback: Decodable {
        let type: String?
        let optionalNote: String?
        let aBitOffSheetSeen: Bool?
        let interpretationRevision: Int?
    }

    struct ServerVisual: Decodable {
        let id: String?
        let styleKey: String?
        let status: String?
        let imageUrls: [String]?
        let imageThumbUrls: [String]?
    }
}

struct PatchNarrativeResponse: Decodable {
    let narrativeHash: String
    let analysisStale: Bool
}

struct ReinterpretResponse: Decodable {
    let analysisText: String
    let analysisRevision: Int
    let narrativeHash: String
    let analysisStale: Bool?
}

struct DreamFeedbackResponse: Decodable {
    let feedback: String?
    let optionalNote: String?
    let aBitOffSheetSeen: Bool?
}

struct DreamService {
    static let shared = DreamService()

    private static let iso8601WithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func createDream(id: UUID, occurredAt: Date = Date(), source: String = "iphone") async throws {
        try await AuthService.shared.ensureAnonymousSession()
        struct Body: Encodable {
            let id: String
            let occurredAt: String
            let source: String
        }
        let iso = ISO8601DateFormatter().string(from: occurredAt)
        struct Resp: Decodable { let id: String; let status: String }
        let _: Resp = try await APIClient.shared.request(
            "POST",
            path: "api/dreams",
            body: Body(id: id.uuidString.lowercased(), occurredAt: iso, source: source)
        )
    }

    func uploadSegments(
        dreamId: UUID,
        segments: [(index: Int, transcript: String, audioURL: URL?)],
        onSegmentUploaded: ((Int, Int) -> Void)? = nil
    ) async throws {
        let total = segments.count
        for (offset, seg) in segments.enumerated() {
            try await APIClient.shared.uploadSegment(
                dreamId: dreamId,
                index: seg.index,
                deviceTranscript: seg.transcript,
                audioFileURL: seg.audioURL
            )
            onSegmentUploaded?(offset + 1, total)
        }
    }

    func finalizeRecording(dreamId: UUID) async throws {
        struct Resp: Decodable { let status: String }
        let _: Resp = try await APIClient.shared.request(
            "POST",
            path: "api/dreams/\(dreamId.uuidString.lowercased())/finalize-recording"
        )
    }

    func fetchDream(dreamId: UUID) async throws -> ServerDreamDetail {
        try await APIClient.shared.request(
            "GET",
            path: "api/dreams/\(dreamId.uuidString.lowercased())"
        )
    }

    func fetchGraph() async throws -> ServerDreamGraph {
        try await APIClient.shared.request("GET", path: "api/dreams/graph")
    }

    func dream(from detail: ServerDreamDetail) -> Dream? {
        guard let id = UUID(uuidString: detail.id) else { return nil }
        let createdAt = parseServerDate(detail.occurredAt) ?? Date()
        let narrative = detail.refinedNarrative ?? ""
        let tags = detail.tags?.map(\.name) ?? []
        var dream = Dream(
            id: id,
            createdAt: createdAt,
            rawTranscript: detail.rawTranscript ?? "",
            organizedText: narrative,
            interpretation: detail.analysisText ?? "",
            tags: tags,
            title: DreamTitleFormatter.resolve(
                serverTitle: detail.title,
                narrative: narrative,
                tags: tags
            ),
            note: nil,
            isArchived: false,
            comicArtifacts: []
        )
        applyServerDetail(detail, to: &dream)
        return dream
    }

    private func parseServerDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = Self.iso8601WithFraction.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    func pollUntilAnalyzed(
        dreamId: UUID,
        maxAttempts: Int = 60,
        onPoll: ((Int, ServerDreamDetail) -> Void)? = nil
    ) async throws -> ServerDreamDetail {
        for attempt in 0..<maxAttempts {
            let detail = try await fetchDream(dreamId: dreamId)
            if detail.status == "analyzed" || detail.status == "visualized" {
                return detail
            }
            onPoll?(attempt, detail)
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw APIError.server("梦析超时，请稍后在梦析页刷新")
    }

    func patchNarrative(dreamId: UUID, refinedNarrative: String) async throws -> PatchNarrativeResponse {
        struct Body: Encodable { let refinedNarrative: String }
        return try await APIClient.shared.request(
            "PATCH",
            path: "api/dreams/\(dreamId.uuidString.lowercased())",
            body: Body(refinedNarrative: refinedNarrative)
        )
    }

    func patchTags(dreamId: UUID, tags: [String]) async throws {
        struct Body: Encodable { let tags: [String] }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await APIClient.shared.request(
            "PATCH",
            path: "api/dreams/\(dreamId.uuidString.lowercased())",
            body: Body(tags: tags)
        )
    }

    func reinterpret(
        dreamId: UUID,
        mode: String = "default",
        trigger: String,
        feedbackNote: String? = nil,
        updateTags: Bool = false
    ) async throws -> ReinterpretResponse {
        struct Body: Encodable {
            let mode: String
            let trigger: String
            let feedbackNote: String?
            let updateTags: Bool
        }
        return try await APIClient.shared.request(
            "POST",
            path: "api/dreams/\(dreamId.uuidString.lowercased())/reinterpret",
            body: Body(mode: mode, trigger: trigger, feedbackNote: feedbackNote, updateTags: updateTags)
        )
    }

    func putFeedback(
        dreamId: UUID,
        feedback: DreamFeedbackType?,
        optionalNote: String? = nil,
        markABitOffSheetSeen: Bool = false
    ) async throws -> DreamFeedbackResponse {
        struct Body: Encodable {
            let feedback: String?
            let optionalNote: String?
            let markABitOffSheetSeen: Bool
        }
        return try await APIClient.shared.request(
            "PUT",
            path: "api/dreams/\(dreamId.uuidString.lowercased())/feedback",
            body: Body(
                feedback: feedback?.rawValue,
                optionalNote: optionalNote,
                markABitOffSheetSeen: markABitOffSheetSeen
            )
        )
    }

    func prefetchStoryboard(dreamId: UUID, styleKey: String? = nil) async throws {
        struct Body: Encodable { let styleKey: String? }
        struct Resp: Decodable { let accepted: Bool }
        let _: Resp = try await APIClient.shared.request(
            "POST",
            path: "api/dreams/\(dreamId.uuidString.lowercased())/comic-storyboard/prefetch",
            body: Body(styleKey: styleKey)
        )
    }

    func applyServerDetail(_ detail: ServerDreamDetail, to dream: inout Dream) {
        if let refined = detail.refinedNarrative, !refined.isEmpty {
            dream.organizedText = refined
        }
        if let analysis = detail.analysisText, !analysis.isEmpty {
            dream.interpretation = analysis
        }
        if let serverTags = detail.tags?.map(\.name), !serverTags.isEmpty {
            dream.tags = serverTags
        }
        if let serverTitle = detail.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !serverTitle.isEmpty {
            if dream.title.isEmpty
                || DreamTitleFormatter.isLegacyAutoTitle(dream.title, narrative: dream.organizedText) {
                dream.title = serverTitle
            }
        }
        dream.analysisStale = detail.analysisStale ?? false

        if let fb = detail.feedback, let raw = fb.type {
            dream.feedback.type = DreamFeedbackType(rawValue: raw)
            dream.feedback.optionalNote = fb.optionalNote
            dream.feedback.aBitOffSheetSeen = fb.aBitOffSheetSeen ?? false
        }

        applyComicArtifacts(from: detail, to: &dream)
    }

    private func applyComicArtifacts(from detail: ServerDreamDetail, to dream: inout Dream) {
        guard let visuals = detail.visuals else { return }
        let artifacts: [ComicArtifact] = visuals.compactMap { visual in
            guard visual.status == "succeeded",
                  let urls = visual.imageUrls,
                  !urls.isEmpty else { return nil }
            let artifactId = visual.id.flatMap { UUID(uuidString: $0) } ?? UUID()
            let styleId = visual.styleKey ?? "unknown"
            let thumbStrings = visual.imageThumbUrls?.isEmpty == false
                ? visual.imageThumbUrls!
                : urls
            return ComicArtifact(
                id: artifactId,
                createdAt: dream.createdAt,
                styleId: styleId,
                previewDescription: "四格漫画",
                remoteImageURLs: urls.compactMap { URL(string: $0) },
                remoteThumbImageURLs: thumbStrings.compactMap { URL(string: $0) }
            )
        }
        guard !artifacts.isEmpty else { return }
        dream.comicArtifacts = artifacts

        let dreamId = dream.id
        Task { @MainActor in
            await Self.refreshComicLocalCache(dreamId: dreamId, artifacts: artifacts)
        }
    }

    @MainActor
    private static func refreshComicLocalCache(dreamId: UUID, artifacts: [ComicArtifact]) async {
        guard var dream = DreamStore.shared.dream(id: dreamId) else { return }
        var updated = false
        for artifact in artifacts {
            guard artifact.imagePaths.isEmpty,
                  !artifact.remoteImageURLs.isEmpty,
                  let index = dream.comicArtifacts.firstIndex(where: { $0.id == artifact.id }) else {
                continue
            }
            let refreshed = await ComicArtifactService.refreshLocalCache(for: artifact)
            dream.comicArtifacts[index] = refreshed
            updated = true
        }
        if updated {
            DreamStore.shared.upsert(dream)
        }
    }
}
