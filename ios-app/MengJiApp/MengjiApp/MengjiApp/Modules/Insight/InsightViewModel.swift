import Foundation
import Combine

@MainActor
final class InsightViewModel: ObservableObject {
    enum DreamFeedback {
        case veryClose
        case aBitOff
        case uncomfortable

        var serverType: DreamFeedbackType {
            switch self {
            case .veryClose: return .veryClose
            case .aBitOff: return .aBitOff
            case .uncomfortable: return .uncomfortable
            }
        }

        init?(server: DreamFeedbackType) {
            switch server {
            case .veryClose: self = .veryClose
            case .aBitOff: self = .aBitOff
            case .uncomfortable: self = .uncomfortable
            }
        }
    }

    struct DreamAnalysis {
        let id: UUID
        let dateString: String
        let timeString: String
        var title: String
        var organizedText: String
        var tags: [String]
        var interpretation: String
        var note: String?
    }

    @Published var current: DreamAnalysis
    @Published var feedback: DreamFeedback?
    @Published var analysisStale = false
    @Published var interpretationCollapsed = false
    @Published var aBitOffSheetSeen = false
    @Published var toastMessage: String?
    @Published var toastStyle: AppToastStyle = .info
    @Published var isSyncing = false
    @Published var isReinterpreting = false
    @Published var pendingSubstantialSave = false

    private let targetDreamId: UUID?
    private var lastSavedOrganizedText: String

    init(dreamId: UUID? = nil) {
        self.targetDreamId = dreamId

        if let dream = DreamStore.shared.dream(id: dreamId) {
            self.current = Self.makeAnalysis(from: dream)
            self.feedback = dream.feedback.type.flatMap { DreamFeedback(server: $0) }
            self.analysisStale = dream.analysisStale
            self.interpretationCollapsed = dream.interpretationCollapsed
            self.aBitOffSheetSeen = dream.feedback.aBitOffSheetSeen
            self.lastSavedOrganizedText = dream.organizedText
        } else if let dreamId {
            self.current = Self.loadingPlaceholder(dreamId: dreamId)
            self.lastSavedOrganizedText = ""
        } else {
            let placeholder = Self.placeholderAnalysis()
            self.current = placeholder
            self.lastSavedOrganizedText = placeholder.organizedText
        }
    }

    func refreshFromServer() async {
        guard let dreamId = targetDreamId else { return }

        isSyncing = true
        defer { isSyncing = false }

        if let cached = DreamStore.shared.dream(id: dreamId) {
            applyDreamState(cached)
        }

        do {
            try await AuthService.shared.ensureAnonymousSession()
            let detail = try await DreamService.shared.fetchDream(dreamId: dreamId)

            var dream = DreamStore.shared.dream(id: dreamId)
            if dream == nil {
                dream = Dream(
                    id: dreamId,
                    createdAt: Date(),
                    rawTranscript: detail.rawTranscript ?? "",
                    organizedText: detail.refinedNarrative ?? "",
                    interpretation: detail.analysisText ?? "",
                    tags: detail.tags?.map(\.name) ?? [],
                    title: String((detail.refinedNarrative ?? "未命名梦境").prefix(24)),
                    note: nil,
                    isArchived: false,
                    comicArtifacts: []
                )
            }

            var updated = dream!
            DreamService.shared.applyServerDetail(detail, to: &updated)
            DreamStore.shared.upsert(updated)
            applyDreamState(updated)
        } catch {
            if DreamStore.shared.dream(id: dreamId) == nil {
                presentToast(error.localizedDescription, style: .error)
            }
        }
    }

    func toggleFeedback(_ value: DreamFeedback) async -> FeedbackAction {
        if feedback == value {
            feedback = nil
            await syncFeedback(nil)
            return .cleared
        }
        feedback = value
        await syncFeedback(value.serverType)

        switch value {
        case .veryClose:
            presentToast("收到了，谢谢你愿意告诉梦悸。", style: .success)
            return .veryCloseConfirmed
        case .aBitOff:
            if !aBitOffSheetSeen {
                return .showABitOffSheetFirstTime
            }
            return .aBitOffInlineOnly
        case .uncomfortable:
            return .showUncomfortableSheet
        }
    }

    func markABitOffSheetSeen() async {
        aBitOffSheetSeen = true
        do {
            try await AuthService.shared.ensureAnonymousSession()
            _ = try await DreamService.shared.putFeedback(
                dreamId: current.id,
                feedback: .aBitOff,
                markABitOffSheetSeen: true
            )
            persistFeedbackFlags()
        } catch {
            presentToast(error.localizedDescription, style: .error)
        }
    }

    func reinterpret(mode: String, trigger: String, note: String? = nil, updateTags: Bool = false) async -> Bool {
        isReinterpreting = true
        defer { isReinterpreting = false }
        do {
            try await AuthService.shared.ensureAnonymousSession()
            let resp = try await DreamService.shared.reinterpret(
                dreamId: current.id,
                mode: mode,
                trigger: trigger,
                feedbackNote: note,
                updateTags: updateTags
            )
            current.interpretation = resp.analysisText
            analysisStale = false
            pendingSubstantialSave = false
            interpretationCollapsed = false
            persistCurrentDream()
            presentToast(
                mode == "gentler" ? "已为你换了一种更轻柔的说法。" : "梦析解读已根据当前整理更新。",
                style: .success
            )
            return true
        } catch {
            presentToast(error.localizedDescription, style: .error)
            return false
        }
    }

    @discardableResult
    func saveOrganizedText(_ text: String, andReinterpret: Bool) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await AuthService.shared.ensureAnonymousSession()
            let resp = try await DreamService.shared.patchNarrative(dreamId: current.id, refinedNarrative: trimmed)
            current.organizedText = trimmed
            analysisStale = resp.analysisStale
            lastSavedOrganizedText = trimmed
            pendingSubstantialSave = resp.analysisStale && !andReinterpret
            persistCurrentDream()

            if andReinterpret {
                return await reinterpret(mode: "default", trigger: "edit")
            }

            if resp.analysisStale {
                presentToast("梦境整理已保存。", style: .success)
            } else {
                presentToast("已保存。", style: .success)
            }
            return true
        } catch {
            presentToast(error.localizedDescription, style: .error)
            return false
        }
    }

    func applyOrganizedTextEditLocally(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        current.organizedText = trimmed
        let substantiallyChanged = substantiallyChanged(from: lastSavedOrganizedText, to: trimmed)
        if substantiallyChanged && trimmed != lastSavedOrganizedText {
            pendingSubstantialSave = true
        }
        return true
    }

    func applyEdits(
        title: String,
        note: String?,
        tagsText: String,
        organizedText: String? = nil
    ) {
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

        if let organizedText {
            let trimmedOrganized = organizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedOrganized.isEmpty {
                current.organizedText = trimmedOrganized
            }
        }

        persistCurrentDream()
    }

    func archiveCurrent() {
        DreamStore.shared.archive(id: current.id)
    }

    func deleteCurrent() {
        DreamStore.shared.delete(id: current.id)
    }

    func setInterpretationCollapsed(_ collapsed: Bool) {
        interpretationCollapsed = collapsed
        persistCurrentDream()
    }

    enum FeedbackAction {
        case cleared
        case veryCloseConfirmed
        case showABitOffSheetFirstTime
        case aBitOffInlineOnly
        case showUncomfortableSheet
    }

    private func syncFeedback(_ type: DreamFeedbackType?) async {
        do {
            try await AuthService.shared.ensureAnonymousSession()
            _ = try await DreamService.shared.putFeedback(dreamId: current.id, feedback: type)
            persistFeedbackFlags()
        } catch {
            presentToast(error.localizedDescription, style: .error)
        }
    }

    func presentToast(_ message: String, style: AppToastStyle = .info) {
        toastStyle = style
        toastMessage = message
    }

    private func persistFeedbackFlags() {
        if var dream = DreamStore.shared.dream(id: current.id) {
            dream.feedback.type = feedback?.serverType
            dream.feedback.aBitOffSheetSeen = aBitOffSheetSeen
            dream.analysisStale = analysisStale
            dream.interpretationCollapsed = interpretationCollapsed
            DreamStore.shared.upsert(dream)
        }
    }

    private func applyDreamState(_ dream: Dream) {
        current = Self.makeAnalysis(from: dream)
        feedback = dream.feedback.type.flatMap { DreamFeedback(server: $0) }
        analysisStale = dream.analysisStale
        interpretationCollapsed = dream.interpretationCollapsed
        aBitOffSheetSeen = dream.feedback.aBitOffSheetSeen
        lastSavedOrganizedText = dream.organizedText
    }

    private func persistCurrentDream() {
        if var dream = DreamStore.shared.dream(id: current.id) {
            dream.title = current.title
            dream.note = current.note
            dream.tags = current.tags
            dream.organizedText = current.organizedText
            dream.interpretation = current.interpretation
            dream.analysisStale = analysisStale
            dream.interpretationCollapsed = interpretationCollapsed
            dream.feedback.type = feedback?.serverType
            dream.feedback.aBitOffSheetSeen = aBitOffSheetSeen
            DreamStore.shared.upsert(dream)
        }
    }

    private func substantiallyChanged(from before: String, to after: String) -> Bool {
        let a = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = after.trimmingCharacters(in: .whitespacesAndNewlines)
        if a == b { return false }
        if a.isEmpty || b.isEmpty { return true }
        let maxLen = max(a.count, b.count)
        if maxLen < 40 { return a != b }
        let distance = zip(a, b).filter { $0 != $1 }.count + abs(a.count - b.count)
        return Double(distance) / Double(maxLen) > 0.05 || distance > 30
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

    /// 有导航 ID 但本地尚未写入 Store 时（录梦刚完成跳转）
    private static func loadingPlaceholder(dreamId: UUID) -> DreamAnalysis {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "yyyy.MM.dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        return DreamAnalysis(
            id: dreamId,
            dateString: dateFormatter.string(from: now),
            timeString: timeFormatter.string(from: now),
            title: "正在载入这条梦…",
            organizedText: "梦悸正在呈现你刚才整理的内容。",
            tags: [],
            interpretation: "稍候片刻，温柔解读马上呈现。",
            note: nil
        )
    }

    /// 无 dreamId 的预览 / 占位
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
