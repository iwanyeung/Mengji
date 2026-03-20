import Foundation
import Combine

final class InsightViewModel: ObservableObject {
    enum DreamFeedback {
        case veryClose      // 很贴近我
        case aBitOff        // 有点偏差
        case uncomfortable  // 让我有点不舒服
    }

    struct DreamAnalysis {
        let id: UUID
        let dateString: String
        let timeString: String
        var title: String
        let organizedText: String
        var tags: [String]
        let interpretation: String
        var note: String?
    }

    @Published var current: DreamAnalysis
    @Published var feedback: DreamFeedback?

    init(dreamId: UUID? = nil) {
        if let dream = DreamStore.shared.dream(id: dreamId) {
            self.current = Self.makeAnalysis(from: dream)
        } else {
            self.current = Self.placeholderAnalysis()
        }
    }

    func toggleFeedback(_ value: DreamFeedback) {
        if feedback == value {
            feedback = nil
        } else {
            feedback = value
        }
        Analytics.track("dream_feedback_updated", properties: [
            "dreamId": current.id.uuidString,
            "feedback": String(describing: value)
        ])
    }

    func applyEdits(title: String, note: String?, tagsText: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)

        let separators = CharacterSet(charactersIn: "，,、 ")
        let rawTags = tagsText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        current.title = trimmedTitle.isEmpty ? current.title : trimmedTitle
        current.note = trimmedNote
        if !rawTags.isEmpty {
            current.tags = rawTags
        }

        if var dream = DreamStore.shared.dream(id: current.id) {
            dream.title = current.title
            dream.note = current.note
            dream.tags = current.tags
            DreamStore.shared.upsert(dream)
        }
    }

    func archiveCurrent() {
        DreamStore.shared.archive(id: current.id)
    }

    func deleteCurrent() {
        DreamStore.shared.delete(id: current.id)
    }

    private static func makeAnalysis(from dream: Dream) -> DreamAnalysis {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "yyyy.MM.dd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        return DreamAnalysis(
            id: dream.id,
            dateString: dateFormatter.string(from: dream.createdAt),
            timeString: timeFormatter.string(from: dream.createdAt),
            title: dream.title,
            organizedText: dream.organizedText,
            tags: dream.tags,
            interpretation: dream.interpretation,
            note: dream.note
        )
    }

    private static func placeholderAnalysis() -> DreamAnalysis {
        DreamAnalysis(
            id: UUID(),
            dateString: "2026.03.17",
            timeString: "03:14",
            title: "从钟楼坠落前的一秒",
            organizedText: "这里会展示你刚刚记录并整理好的梦境内容。",
            tags: ["占位梦", "示例标签"],
            interpretation: "当真实的梦记录生成后，这里会以温柔的方式陪你一起回看那一晚发生了什么。",
            note: nil
        )
    }
}

