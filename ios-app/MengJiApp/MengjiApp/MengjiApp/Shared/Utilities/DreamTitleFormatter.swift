import Foundation

enum DreamTitleFormatter {
    /// 服务端返回的完整标题，或基于正文/标签的本地兜底
    static func resolve(serverTitle: String?, narrative: String, tags: [String] = []) -> String {
        if let serverTitle = serverTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !serverTitle.isEmpty {
            return serverTitle
        }
        return fallback(from: narrative, tags: tags)
    }

    /// 判断是否为旧版「正文前 24 字」标题，便于刷新时覆盖
    static func isLegacyAutoTitle(_ title: String, narrative: String) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !narrative.isEmpty else { return trimmedTitle.isEmpty }

        if trimmedTitle.hasPrefix("关于「"), trimmedTitle.hasSuffix("」的夜里") {
            return false
        }

        let legacy = String(narrative.prefix(24))
        return trimmedTitle == legacy
    }

    private static func fallback(from narrative: String, tags: [String]) -> String {
        let generic: Set<String> = ["梦境", "自我观察", "梦", "夜", "未命名梦"]
        if let tag = tags.first(where: { tag in
            let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.count >= 2 && t.count <= 12 && !generic.contains(t)
        }) {
            return format(phrase: tag)
        }

        let trimmed = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return format(phrase: "未命名梦境")
        }

        var source = trimmed
        if let range = source.range(of: #"^我(昨天|今天|刚才)?(做)?(了)?(一个)?梦(，|。|梦见|里)?"#, options: .regularExpression) {
            source = String(source[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if source.isEmpty { source = trimmed }

        let phrase: String
        if source.count <= 10 {
            phrase = source
        } else {
            let end = source.index(source.startIndex, offsetBy: min(10, source.count))
            phrase = String(source[..<end])
                .trimmingCharacters(in: CharacterSet(charactersIn: "，,。！？!?、 "))
        }

        return format(phrase: phrase.isEmpty ? "一段梦" : phrase)
    }

    static func format(phrase: String) -> String {
        let cleaned = phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "「", with: "")
            .replacingOccurrences(of: "」", with: "")
        let body = cleaned.isEmpty ? "未命名梦境" : String(cleaned.prefix(24))
        return "关于「\(body)」的夜里"
    }
}
