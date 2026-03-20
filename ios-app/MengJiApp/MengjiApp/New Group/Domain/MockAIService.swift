import Foundation

enum MockAIService {
    struct OrganizedResult {
        let title: String
        let organizedText: String
        let interpretation: String
        let tags: [String]
    }

    static func organizeAndInterpret(rawTranscript: String, createdAt: Date) -> OrganizedResult {
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "这一段梦还很模糊，但你已经为记住它迈出了一小步。"
        let base = trimmed.isEmpty ? fallback : trimmed

        let previewLimit = 18
        let titleBody: String
        if base.count <= previewLimit {
            titleBody = base
        } else {
            let idx = base.index(base.startIndex, offsetBy: previewLimit)
            titleBody = String(base[..<idx]) + "…"
        }

        let title = "关于「\(titleBody)」的夜里"

        let organizedText = base + "\n\n（梦悸正在用更连贯的方式帮你记住这些画面与情绪。）"

        let interpretation = """
这个梦更像是一段被匆匆按下暂停的日记。你在半睡半醒之间抓住了一些碎片：场景、人物、甚至只是一种身体的感觉。

梦悸暂时还不知道这些细节在你的人生里对应着什么，但它们之所以出现，多半与最近在意的关系、压力或期待有关。你已经做了一件很重要的事：把它们留了下来，而不是任由它们消散。

当你哪天有空重新回看这段梦时，不妨问问自己：这一晚的画面，最打动你的一瞬间是什么？那一瞬间，可能就是你最近最在意、但来不及说出口的东西。
"""

        let roughTags = extractTags(from: base)

        return OrganizedResult(
            title: title,
            organizedText: organizedText,
            interpretation: interpretation,
            tags: roughTags
        )
    }

    private static func extractTags(from text: String) -> [String] {
        if text.isEmpty {
            return ["未命名梦", "片段", "需要更多记录"]
        }

        let separators = CharacterSet(charactersIn: " ，,、。！？!?\n")
        let words = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if words.isEmpty {
            return ["夜晚", "片段感", "模糊的情绪"]
        }

        let unique = Array(NSOrderedSet(array: words)).compactMap { $0 as? String }
        let picked = Array(unique.prefix(4))
        return picked + ["夜里发生的事"]
    }
}

