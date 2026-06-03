import Combine
import SwiftUI
import UIKit

/// 四格漫画图片加载：本地磁盘 → 内存 → URLCache，支持缩略图/全屏降采样/原图分级预取。
@MainActor
final class ComicImageLoader: ObservableObject {
    static let shared = ComicImageLoader()

    /// 全屏展示最长边上限（非 2K，加快解码与内存占用）
    static let fullscreenMaxPixelEdge: CGFloat = 1200

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

    func cacheKey(for panel: ComicPanelDisplay, maxPixelEdge: CGFloat? = nil) -> String {
        let base: String
        if let path = panel.localRelativePath, !path.isEmpty {
            base = "file://\(path)"
        } else {
            base = panel.remoteURL.absoluteString
        }
        guard let edge = maxPixelEdge else { return base }
        return "\(base)|fs\(Int(edge))"
    }

    func image(for panel: ComicPanelDisplay, maxPixelEdge: CGFloat?) -> UIImage? {
        let key = cacheKey(for: panel, maxPixelEdge: maxPixelEdge) as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        guard let edge = maxPixelEdge else {
            return image(for: panel)
        }
        if let path = panel.localRelativePath, !path.isEmpty {
            let fileURL = ComicPanelDiskCache.fileURL(relativePath: path)
            if let image = loadImageFromDisk(fileURL, maxPixelEdge: edge) {
                store(image, key: cacheKey(for: panel, maxPixelEdge: edge))
                return image
            }
        }
        return nil
    }

    func image(for panel: ComicPanelDisplay) -> UIImage? {
        if let path = panel.localRelativePath, !path.isEmpty {
            let fileURL = ComicPanelDiskCache.fileURL(relativePath: path)
            let key = cacheKey(for: panel) as NSString
            if let cached = memoryCache.object(forKey: key) {
                return cached
            }
            if let image = loadImageFromDisk(fileURL, maxPixelEdge: nil) {
                memoryCache.setObject(image, forKey: key, cost: imageCost(image))
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

    func prefetch(panels: [ComicPanelDisplay], maxPixelEdge: CGFloat? = nil) {
        for panel in panels {
            prefetch(panel: panel, maxPixelEdge: maxPixelEdge)
        }
    }

    func prefetch(panel: ComicPanelDisplay, maxPixelEdge: CGFloat? = nil) {
        let key = cacheKey(for: panel, maxPixelEdge: maxPixelEdge)
        if let edge = maxPixelEdge {
            guard image(for: panel, maxPixelEdge: edge) == nil else { return }
        } else {
            guard image(for: panel) == nil else { return }
        }
        guard inFlight[key] == nil else { return }
        inFlight[key] = Task {
            defer { inFlight[key] = nil }
            return await load(panel: panel, maxPixelEdge: maxPixelEdge)
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

    func prefetchAll(panels: [ComicPanelDisplay], maxPixelEdge: CGFloat? = nil) async {
        await withTaskGroup(of: Void.self) { group in
            for panel in panels {
                group.addTask {
                    await self.ensureLoaded(panel: panel, maxPixelEdge: maxPixelEdge)
                }
            }
        }
    }

    func ensureLoaded(panel: ComicPanelDisplay, maxPixelEdge: CGFloat? = nil) async {
        if let edge = maxPixelEdge {
            if image(for: panel, maxPixelEdge: edge) != nil { return }
        } else if image(for: panel) != nil {
            return
        }
        let key = cacheKey(for: panel, maxPixelEdge: maxPixelEdge)
        if let task = inFlight[key] {
            _ = await task.value
            return
        }
        _ = await load(panel: panel, maxPixelEdge: maxPixelEdge)
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
    func load(panel: ComicPanelDisplay, maxPixelEdge: CGFloat? = nil) async -> UIImage? {
        if let edge = maxPixelEdge, let existing = image(for: panel, maxPixelEdge: edge) {
            return existing
        }
        if maxPixelEdge == nil, let existing = image(for: panel) {
            return existing
        }
        let key = cacheKey(for: panel, maxPixelEdge: maxPixelEdge)
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task<UIImage?, Never> {
            if let path = panel.localRelativePath, !path.isEmpty {
                let fileURL = ComicPanelDiskCache.fileURL(relativePath: path)
                if let image = loadImageFromDisk(fileURL, maxPixelEdge: maxPixelEdge) {
                    store(image, key: key)
                    return image
                }
            }
            if let edge = maxPixelEdge {
                guard let raw = await loadImage(from: panel.remoteURL) else { return nil }
                let scaled = Self.downscale(raw, maxPixelEdge: edge)
                store(scaled, key: key)
                return scaled
            }
            return await loadImage(from: panel.remoteURL, storeKey: key)
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
        let task = Task<UIImage?, Never> {
            await loadImage(from: url, storeKey: key)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func store(_ image: UIImage, key: String) {
        memoryCache.setObject(image, forKey: key as NSString, cost: imageCost(image))
        cacheRevision &+= 1
    }

    private func imageCost(_ image: UIImage) -> Int {
        Int(image.size.width * image.size.height * image.scale * image.scale)
    }

    private func loadImageFromDisk(_ fileURL: URL, maxPixelEdge: CGFloat?) -> UIImage? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        guard let edge = maxPixelEdge else { return image }
        return Self.downscale(image, maxPixelEdge: edge)
    }

    private func loadImage(from url: URL, storeKey: String? = nil) async -> UIImage? {
        if let existing = image(for: url) {
            if let storeKey {
                store(existing, key: storeKey)
            }
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
            let urlKey = url.absoluteString
            memoryCache.setObject(image, forKey: urlKey as NSString, cost: data.count)
            if let storeKey, storeKey != urlKey {
                store(image, key: storeKey)
            } else {
                cacheRevision &+= 1
            }
            return image
        } catch {
            return nil
        }
    }

    static func downscale(_ image: UIImage, maxPixelEdge: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxPixelEdge, maxSide > 0 else { return image }
        let scale = maxPixelEdge / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - SwiftUI 单格

struct ComicPanelImage: View {
    let panel: ComicPanelDisplay
    var maxPixelEdge: CGFloat? = nil
    @ObservedObject private var loader = ComicImageLoader.shared

    var body: some View {
        Group {
            if let edge = maxPixelEdge, let uiImage = loader.image(for: panel, maxPixelEdge: edge) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if maxPixelEdge == nil, let uiImage = loader.image(for: panel) {
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
        .task(id: loader.cacheKey(for: panel, maxPixelEdge: maxPixelEdge)) {
            _ = await loader.load(panel: panel, maxPixelEdge: maxPixelEdge)
        }
        .onChange(of: loader.cacheRevision) { _, _ in }
    }
}

// MARK: - 全屏渐进：先 preview，再降采样清晰图

struct ComicPanelProgressiveImage: View {
    let previewPanel: ComicPanelDisplay
    let sharpPanel: ComicPanelDisplay
    @ObservedObject private var loader = ComicImageLoader.shared
    @State private var revealSharp = false

    private var sharpImage: UIImage? {
        loader.image(for: sharpPanel, maxPixelEdge: ComicImageLoader.fullscreenMaxPixelEdge)
    }

    var body: some View {
        ZStack {
            ComicPanelImage(panel: previewPanel)

            if let sharp = sharpImage {
                Image(uiImage: sharp)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: revealSharp ? 0 : 8)
                    .animation(.easeOut(duration: 0.4), value: revealSharp)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: loader.cacheKey(for: sharpPanel, maxPixelEdge: ComicImageLoader.fullscreenMaxPixelEdge)) {
            _ = await loader.load(
                panel: sharpPanel,
                maxPixelEdge: ComicImageLoader.fullscreenMaxPixelEdge
            )
            if sharpImage != nil {
                revealSharp = true
            }
        }
        .onChange(of: loader.cacheRevision) { _, _ in
            if sharpImage != nil, !revealSharp {
                revealSharp = true
            }
        }
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
