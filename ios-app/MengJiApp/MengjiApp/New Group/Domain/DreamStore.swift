import Foundation
import Combine

final class DreamStore: ObservableObject {
    static let shared = DreamStore()

    @Published private(set) var dreams: [Dream] = []

    private enum Keys {
        static let cache = "mengji.dreams.cache"
    }

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        loadFromDisk()
    }

    func upsert(_ dream: Dream) {
        applyOnMain {
            if let index = self.dreams.firstIndex(where: { $0.id == dream.id }) {
                self.dreams[index] = dream
            } else {
                self.dreams.insert(dream, at: 0)
            }
            self.persistToDisk()
        }
    }

    /// 将服务端梦境合并进本地：服务端为准，保留尚未上传的本地-only 梦境。
    func mergeFromServer(_ serverDreams: [Dream]) {
        applyOnMain {
            let serverIds = Set(serverDreams.map(\.id))
            let localOnly = self.dreams.filter { !serverIds.contains($0.id) }
            self.dreams = (serverDreams + localOnly).sorted { $0.createdAt > $1.createdAt }
            self.persistToDisk()
        }
    }

    func delete(id: UUID) {
        applyOnMain {
            self.dreams.removeAll { $0.id == id }
            self.persistToDisk()
        }
    }

    func archive(id: UUID) {
        applyOnMain {
            guard let index = self.dreams.firstIndex(where: { $0.id == id }) else { return }
            var updated = self.dreams[index]
            updated.isArchived = true
            self.dreams[index] = updated
            self.persistToDisk()
        }
    }

    func dream(id: UUID?) -> Dream? {
        guard let id else { return nil }
        return dreams.first(where: { $0.id == id })
    }

    func visibleDreams() -> [Dream] {
        dreams.filter { !$0.isArchived }
    }

    private func loadFromDisk() {
        guard let data = defaults.data(forKey: Keys.cache),
              let decoded = try? decoder.decode([Dream].self, from: data) else { return }
        dreams = decoded
    }

    private func persistToDisk() {
        guard let data = try? encoder.encode(dreams) else { return }
        defaults.set(data, forKey: Keys.cache)
    }

    private func applyOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
