import Foundation
import Combine

final class DreamStore: ObservableObject {
    static let shared = DreamStore()

    @Published private(set) var dreams: [Dream] = []

    private let queue = DispatchQueue(label: "dream.store.queue")

    private init() {}

    func upsert(_ dream: Dream) {
        queue.async {
            DispatchQueue.main.async {
                if let index = self.dreams.firstIndex(where: { $0.id == dream.id }) {
                    self.dreams[index] = dream
                } else {
                    self.dreams.insert(dream, at: 0)
                }
            }
        }
    }

    func delete(id: UUID) {
        queue.async {
            DispatchQueue.main.async {
                self.dreams.removeAll { $0.id == id }
            }
        }
    }

    func archive(id: UUID) {
        queue.async {
            DispatchQueue.main.async {
                guard let index = self.dreams.firstIndex(where: { $0.id == id }) else { return }
                var updated = self.dreams[index]
                updated.isArchived = true
                self.dreams[index] = updated
            }
        }
    }

    func dream(id: UUID?) -> Dream? {
        guard let id else { return nil }
        return dreams.first(where: { $0.id == id })
    }

    func visibleDreams() -> [Dream] {
        dreams.filter { !$0.isArchived }
    }
}

