import Combine
import Foundation
import WatchConnectivity

enum DreamRecordingDraftSource: String, Codable, Equatable {
    case watch
    case phone
}

struct DreamRecordingDraft: Identifiable, Codable, Equatable {
    let id: UUID
    let occurredAt: Date
    let durationText: String
    var transcript: String
    var audioFilePath: String?
    let source: DreamRecordingDraftSource
    var isSelected: Bool
    let segmentIndex: Int?

    var audioFileURL: URL? {
        guard let audioFilePath else { return nil }
        return URL(fileURLWithPath: audioFilePath)
    }
}

/// 跨设备录梦草稿池：手表段与手机段合并，仅在手机「完成并整理」时上传。
@MainActor
final class DreamRecordingSession: ObservableObject {
    static let shared = DreamRecordingSession()

    @Published private(set) var dreamId: UUID?
    @Published private(set) var drafts: [DreamRecordingDraft] = []
    @Published private(set) var startedAt: Date?

    private let storageFileName = "ActiveRecordingSession.json"
    private let iso8601 = ISO8601DateFormatter()

    private init() {
        loadFromDisk()
    }

    var hasDrafts: Bool { !drafts.isEmpty }

    var selectedDrafts: [DreamRecordingDraft] {
        drafts.filter(\.isSelected)
    }

    // MARK: - Session lifecycle

    @discardableResult
    func startIfNeeded() -> UUID {
        if let dreamId { return dreamId }
        let id = UUID()
        dreamId = id
        startedAt = Date()
        persist()
        publishContextToWatch()
        return id
    }

    func start(with id: UUID) {
        dreamId = id
        if startedAt == nil { startedAt = Date() }
        persist()
        publishContextToWatch()
    }

    func clear() {
        dreamId = nil
        drafts = []
        startedAt = nil
        persist()
        clearWatchContext()
    }

    func beginNewDream() {
        clear()
        _ = startIfNeeded()
    }

    // MARK: - Drafts

    @discardableResult
    func appendWatchSegment(
        audioURL: URL,
        occurredAt: Date,
        duration: TimeInterval,
        segmentIndex: Int,
        segmentId: UUID,
        dreamIdFromWatch: UUID?
    ) -> DreamRecordingDraft {
        if let dreamIdFromWatch {
            if dreamId == nil {
                start(with: dreamIdFromWatch)
            } else if dreamId != dreamIdFromWatch {
                start(with: dreamIdFromWatch)
                drafts = []
            }
        } else {
            startIfNeeded()
        }

        let stableURL = persistDraftAudio(from: audioURL, segmentId: segmentId)
        let draft = DreamRecordingDraft(
            id: segmentId,
            occurredAt: occurredAt,
            durationText: formatDuration(duration),
            transcript: "",
            audioFilePath: stableURL?.path,
            source: .watch,
            isSelected: true,
            segmentIndex: segmentIndex
        )
        drafts.insert(draft, at: 0)
        persist()
        publishContextToWatch()
        return draft
    }

    func appendPhoneSegment(
        id: UUID,
        occurredAt: Date,
        meta: String,
        durationText: String,
        transcript: String,
        audioFileURL: URL?
    ) {
        startIfNeeded()
        let stablePath: String?
        if let audioFileURL {
            stablePath = persistDraftAudio(from: audioFileURL, segmentId: id)?.path
        } else {
            stablePath = nil
        }
        let draft = DreamRecordingDraft(
            id: id,
            occurredAt: occurredAt,
            durationText: durationText,
            transcript: transcript,
            audioFilePath: stablePath,
            source: .phone,
            isSelected: true,
            segmentIndex: nil
        )
        drafts.insert(draft, at: 0)
        persist()
        publishContextToWatch()
    }

    func removeDraft(id: UUID) {
        if let draft = drafts.first(where: { $0.id == id }),
           let path = draft.audioFilePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        drafts.removeAll { $0.id == id }
        if drafts.isEmpty {
            dreamId = nil
            startedAt = nil
            clearWatchContext()
        }
        persist()
    }

    func setSelected(id: UUID, selected: Bool) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].isSelected = selected
        persist()
    }

    // MARK: - Watch context

    func publishContextToWatch() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var context: [String: Any] = [:]
        if let dreamId {
            context[WatchConnectivityMetadata.activeDreamId] = dreamId.uuidString.lowercased()
            context[WatchConnectivityMetadata.draftCount] = drafts.count
        }
        try? session.updateApplicationContext(context)
    }

    func clearWatchContext() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext([:])
    }

    // MARK: - Persistence

    private struct PersistedState: Codable {
        var dreamId: UUID?
        var startedAt: Date?
        var drafts: [DreamRecordingDraft]
    }

    private var draftsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("RecordingDrafts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(storageFileName)
    }

    private func persistDraftAudio(from source: URL, segmentId: UUID) -> URL? {
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        let dest = draftsDirectory.appendingPathComponent("\(segmentId.uuidString).\(ext)")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    private func persist() {
        let state = PersistedState(dreamId: dreamId, startedAt: startedAt, drafts: drafts)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        dreamId = state.dreamId
        startedAt = state.startedAt
        drafts = state.drafts
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(1, Int(duration.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
