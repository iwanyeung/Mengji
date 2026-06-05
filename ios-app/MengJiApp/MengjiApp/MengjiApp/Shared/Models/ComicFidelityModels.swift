import Foundation

enum ComicReadinessLevel: String, Decodable {
    case sparse
    case moderate
    case rich
}

enum ComicStoryboardMode: String, Decodable {
    case imagery
    case narrative
}

enum ComicPanelSource: String, Decodable, CaseIterable {
    case verbatim
    case atmosphere
    case inferred

    var label: String {
        switch self {
        case .verbatim: return "来自你的梦"
        case .atmosphere: return "意象延伸"
        case .inferred: return "AI 补充"
        }
    }
}

enum ComicFidelityFeedback: String, CaseIterable {
    case veryClose = "very_close"
    case tooInvented = "too_invented"
    case notMine = "not_mine"

    var label: String {
        switch self {
        case .veryClose: return "很像我梦里的"
        case .tooInvented: return "多了很多我没梦到的"
        case .notMine: return "完全不像"
        }
    }
}

struct ComicReadiness: Decodable {
    let level: ComicReadinessLevel
    let score: Int
    let segmentCount: Int
    let narrativeCharCount: Int
    let concreteImageryCount: Int
    let suggestedMode: ComicStoryboardMode
    let userHint: String
    let ctaHint: String

    var isSparse: Bool { level == .sparse }
    var isRich: Bool { level == .rich }
}

struct ComicStoryboardPanel: Identifiable, Decodable, Equatable {
    let panelIndex: Int
    let caption: String
    let source: ComicPanelSource

    var id: Int { panelIndex }
}

struct ComicStoryboardPreview: Decodable {
    let styleKey: String
    let storyboardMode: ComicStoryboardMode
    let readiness: ComicReadiness?
    let panels: [ComicStoryboardPanel]
    let inferredPanelCount: Int
}

struct ComicFidelityFeedbackResponse: Decodable {
    let fidelityFeedback: String
    let compensationEligible: Bool
    let compensationHint: String?
}

struct ComicStoryboardCaptionUpdate: Encodable {
    let panelIndex: Int
    let caption: String
}
