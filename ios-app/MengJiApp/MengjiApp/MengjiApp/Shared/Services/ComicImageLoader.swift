import Combine
import SwiftUI
import UIKit

/// 四格漫画图片加载：本地磁盘 → 内存 → URLCache，支持缩略图/原图分级预取。
@MainActor
final class ComicImageLoader: ObservableObject {
    static let shared = ComicImageLoader()

    @Published private(set) var cacheRevision = 0

    private static let urlCache: URLCache = {
        URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "com.mengji.comic-images"
        )
    }()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = Self.urlCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()

    private let memoryCache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        memoryCache.countLimit = 64
        memoryCache.totalCostLimit = 96 * 1024 * 1024
    }

    func cacheKey(for panel: ComicPanelDisplay) -> String {
        if let path = panel.localRelativePath, !path.isEmpty {
            return "file://\(path)"
        }
        return panel.remoteURL.absoluteString
    }

    func image(for panel: ComicPanelDisplay) -> UIImage? {
        if let path = panel.localRelativePath, !path.isEmpty {
            let fileURL = ComicPanelDiskCache.fileURL(relativePath: path)
            if let cached = memoryCache.object(forKey: cacheKey(for: panel) as NSString) {
                return cached
            }
            if let image = loadImageFromDisk(fileURL) {
                memoryCache.setObject(image, forKey: cacheKey(for: panel) as NSString, cost: 1)
                return image
            }
        }
        return image(for: panel.remoteURL)
    }

    func image(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        let request = URLRequest(url: url)
        if let response = Self.urlCache.cachedResponse(for: request),
           let image = UIImage(data: response.data) {
            memoryCache.setObject(image, forKey: key, cost: response.data.count)
            return image
        }
        return nil
    }

    func prefetch(panels: [ComicPanelDisplay]) {
        for panel in panels {
            prefetch(panel: panel)
        }
    }

    func prefetch(panel: ComicPanelDisplay) {
        let key = cacheKey(for: panel)
        guard image(for: panel) == nil else { return }
        guard inFlight[key] == nil else { return }
        inFlight[key] = Task {
            defer { inFlight[key] = nil }
            return await load(panel: panel)
        }
    }

    func prefetch(urls: [URL]) {
        for url in urls {
            prefetch(url: url)
        }
    }

    func prefetch(url: URL) {
        guard image(for: url) == nil else { return }
        let key = url.absoluteString
        guard inFlight[key] == nil else { return }
        inFlight[key] = Task {
            defer { inFlight[key] = nil }
            return await load(url: url)
        }
    }

    func prefetchAll(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    await self.ensureLoaded(url: url)
                }
            }
        }
    }

    func prefetchAll(panels: [ComicPanelDisplay]) async {
        await withTaskGroup(of: Void.self) { group in
            for panel in panels {
                group.addTask {
                    await self.ensureLoaded(panel: panel)
                }
            }
        }
    }

    func ensureLoaded(panel: ComicPanelDisplay) async {
        if image(for: panel) != nil { return }
        let key = cacheKey(for: panel)
        if let task = inFlight[key] {
            _ = await task.value
            return
        }
        _ = await load(panel: panel)
    }

    func ensureLoaded(url: URL) async {
        if image(for: url) != nil { return }
        let key = url.absoluteString
        if let task = inFlight[key] {
            _ = await task.value
            return
        }
        _ = await load(url: url)
    }

    @discardableResult
    func load(panel: ComicPanelDisplay) async -> UIImage? {
        if let existing = image(for: panel) {
            return existing
        }
        let key = cacheKey(for: panel)
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task<UIImage?, Never> {
            if let path = panel.localRelativePath, !path.isEmpty {
                let fileURL = ComicPanelDiskCache.fileURL(relativePath: path)
                if let image = loadImageFromDisk(fileURL) {
                    memoryCache.setObject(image, forKey: key as NSString, cost: 1)
                    cacheRevision &+= 1
                    return image
                }
            }
            return await loadImage(from: panel.remoteURL)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    @discardableResult
    func load(url: URL) async -> UIImage? {
        if let existing = image(for: url) {
            return existing
        }
        let key = url.absoluteString
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task<UIImage?, Never> { await loadImage(from: url) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func loadImageFromDisk(_ fileURL: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    private func loadImage(from url: URL) async -> UIImage? {
        if let existing = image(for: url) {
            return existing
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            let request = URLRequest(url: url)
            Self.urlCache.storeCachedResponse(
                CachedURLResponse(response: response, data: data),
                for: request
            )
            memoryCache.setObject(image, forKey: url.absoluteString as NSString, cost: data.count)
            cacheRevision &+= 1
            return image
        } catch {
            return nil
        }
    }
}

// MARK: - SwiftUI 单格

struct ComicPanelImage: View {
    let panel: ComicPanelDisplay
    @ObservedObject private var loader = ComicImageLoader.shared

    var body: some View {
        Group {
            if let uiImage = loader.image(for: panel) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(AppTheme.surface)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: loader.cacheKey(for: panel)) {
            _ = await loader.load(panel: panel)
        }
        .onChange(of: loader.cacheRevision) { _, _ in }
    }
}

extension VisualDetail {
    var prefetchableThumbImageURLs: [URL] {
        if let partial = imageThumbUrlsPartial, !partial.isEmpty {
            return partial.compactMap { $0 }.compactMap { URL(string: $0) }
        }
        return (imageThumbUrls ?? imageUrls ?? []).compactMap { URL(string: $0) }
    }

    var prefetchableImageURLs: [URL] {
        if let partial = imageUrlsPartial, !partial.isEmpty {
            return partial.compactMap { $0 }.compactMap { URL(string: $0) }
        }
        return (imageUrls ?? []).compactMap { URL(string: $0) }
    }
}
