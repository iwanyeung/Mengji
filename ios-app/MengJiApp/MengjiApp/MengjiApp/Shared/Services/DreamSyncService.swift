import Foundation
import Combine

@MainActor
final class DreamSyncService: ObservableObject {
    static let shared = DreamSyncService()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?

    private var syncTask: Task<Void, Never>?

    private init() {}

    /// 从服务端拉取当前账号下的梦境列表并合并到 `DreamStore`。
    func syncFromServer() {
        syncTask?.cancel()
        syncTask = Task { await performSync() }
    }

    func syncFromServerAndWait() async {
        syncTask?.cancel()
        await performSync()
    }

    private func performSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await AuthService.shared.ensureAnonymousSession()
            let graph = try await AuthService.shared.withAuthorizedSession {
                try await DreamService.shared.fetchGraph()
            }
            let dreamIds = graph.nodes.compactMap { UUID(uuidString: $0.id) }
            guard !dreamIds.isEmpty else { return }

            var serverDreams: [Dream] = []
            serverDreams.reserveCapacity(dreamIds.count)

            await withTaskGroup(of: Dream?.self) { group in
                for dreamId in dreamIds {
                    group.addTask {
                        guard !Task.isCancelled else { return nil }
                        do {
                            let detail = try await AuthService.shared.withAuthorizedSession {
                                try await DreamService.shared.fetchDream(dreamId: dreamId)
                            }
                            return await DreamService.shared.dream(from: detail)
                        } catch {
                            return nil
                        }
                    }
                }

                for await dream in group {
                    if let dream {
                        serverDreams.append(dream)
                    }
                }
            }

            guard !Task.isCancelled else { return }
            DreamStore.shared.mergeFromServer(serverDreams)
            lastSyncedAt = Date()
        } catch {
            // 静默失败：离线或尚未登录时仍可使用本地缓存
            print("Dream sync failed:", error.localizedDescription)
        }
    }
}
