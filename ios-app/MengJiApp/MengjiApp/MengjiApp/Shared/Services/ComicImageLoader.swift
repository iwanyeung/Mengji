import Combine
import ImageIO
import SwiftUI
import UIKit

/// 网络层缓存与会话：使用 `nonisolated(unsafe)` 以在 Swift 6 默认 MainActor 隔离下供后台线程访问。
private enum ComicImageNetwork {
    nonisolated static let urlCache: URLCache = {
        URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "com.mengji.comic-images"
        )
    }()

    nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = urlCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()

    nonisolated static func cachedData(for request: URLRequest) -> Data? {
        urlCache.cachedResponse(for: request)?.data
    }

    nonisolated static func storeCachedResponse(_ cached: CachedURLResponse, for request: URLRequest) {
        urlCache.storeCachedResponse(cached, for: request)
    }
}

/// 四格漫画图片加载：本地磁盘 → 内存 → URLCache。
/// 所有磁盘读取 / 解码 / 降采样都在后台线程完成（ImageIO 一次性解码即降采样），
/// 主线程只负责读内存缓存与状态更新，避免全屏打开时卡死主线程。
@MainActor
final class ComicImageLoader: ObservableObject {
    static let shared = ComicImageLoader()

    /// 全屏展示最长边上限（非 2K，加快解码与内存占用）
    static let fullscreenMaxPixelEdge: CGFloat = 1200

    @Published private(set) var cacheRevision = 0

    private let memoryCache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        memoryCache.countLimit = 64
        memoryCache.totalCostLimit = 96 * 1024 * 1024
    }

    // MARK: - 缓存 Key

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

    // MARK: - 同步访问器（仅查内存，绝不在主线程解码）

    func image(for panel: ComicPanelDisplay, maxPixelEdge: CGFloat?) -> UIImage? {
        memoryCache.object(forKey: cacheKey(for: panel, maxPixelEdge: maxPixelEdge) as NSString)
    }

    func image(for panel: ComicPanelDisplay) -> UIImage? {
        image(for: panel, maxPixelEdge: nil)
    }

    func image(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url.absoluteString as NSString)
    }

    // MARK: - 预取（即发即忘，去重交给 load）

    func prefetch(panels: [ComicPanelDisplay], maxPixelEdge: CGFloat? = nil) {
        for panel in panels {
            prefetch(panel: panel, maxPixelEdge: maxPixelEdge)
        }
    }

    func prefetch(panel: ComicPanelDisplay, maxPixelEdge: CGFloat? = nil) {
        guard image(for: panel, maxPixelEdge: maxPixelEdge) == nil else { return }
        Task { _ = await load(panel: panel, maxPixelEdge: maxPixelEdge) }
    }

    func prefetch(urls: [URL]) {
        for url in urls {
            prefetch(url: url)
        }
    }

    func prefetch(url: URL) {
        guard image(for: url) == nil else { return }
        Task { _ = await load(url: url) }
    }

    func prefetchAll(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { await self.ensureLoaded(url: url) }
            }
        }
    }

    func prefetchAll(panels: [ComicPanelDisplay], maxPixelEdge: CGFloat? = nil) async {
        await withTaskGroup(of: Void.self) { group in
            for panel in panels {
                group.addTask { await self.ensureLoaded(panel: panel, maxPixelEdge: maxPixelEdge) }
            }
        }
    }

    func ensureLoaded(panel: ComicPanelDisplay, maxPixelEdge: CGFloat? = nil) async {
        if image(for: panel, maxPixelEdge: maxPixelEdge) != nil { return }
        _ = await load(panel: panel, maxPixelEdge: maxPixelEdge)
    }

    func ensureLoaded(url: URL) async {
        if image(for: url) != nil { return }
        _ = await load(url: url)
    }

    // MARK: - 加载（内存命中即返回；否则后台解码后回主线程写缓存）

    @discardableResult
    func load(panel: ComicPanelDisplay, maxPixelEdge: CGFloat? = nil) async -> UIImage? {
        if let existing = image(for: panel, maxPixelEdge: maxPixelEdge) {
            return existing
        }
        let key = cacheKey(for: panel, maxPixelEdge: maxPixelEdge)
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.performLoad(panel: panel, maxPixelEdge: maxPixelEdge, key: key)
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
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            guard let data = await Self.downloadData(from: url) else { return nil }
            guard let image = await Self.decodeOffMain(data: data, maxPixelEdge: nil) else { return nil }
            self.store(image, key: key)
            return image
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func performLoad(panel: ComicPanelDisplay, maxPixelEdge: CGFloat?, key: String) async -> UIImage? {
        if let path = panel.localRelativePath, !path.isEmpty {
            let fileURL = ComicPanelDiskCache.fileURL(relativePath: path)
            if let image = await Self.decodeOffMain(fileURL: fileURL, maxPixelEdge: maxPixelEdge) {
                store(image, key: key)
                return image
            }
        }
        guard let data = await Self.downloadData(from: panel.remoteURL) else { return nil }
        guard let image = await Self.decodeOffMain(data: data, maxPixelEdge: maxPixelEdge) else { return nil }
        store(image, key: key)
        return image
    }

    private func store(_ image: UIImage, key: String) {
        memoryCache.setObject(image, forKey: key as NSString, cost: imageCost(image))
        cacheRevision &+= 1
    }

    private func imageCost(_ image: UIImage) -> Int {
        Int(image.size.width * image.size.height * image.scale * image.scale)
    }

    // MARK: - 后台网络 + 解码

    nonisolated private static func downloadData(from url: URL) async -> Data? {
        let request = URLRequest(url: url)
        // URLCache 读写涉及磁盘 I/O，放到后台执行，避免阻塞调用方（可能是主线程）。
        if let cached = await Task.detached(priority: .userInitiated, operation: {
            ComicImageNetwork.cachedData(for: request)
        }).value {
            return cached
        }
        do {
            let (data, response) = try await ComicImageNetwork.session.data(for: request)
            guard !data.isEmpty else { return nil }
            let cached = CachedURLResponse(response: response, data: data)
            await Task.detached(priority: .utility) {
                ComicImageNetwork.storeCachedResponse(cached, for: request)
            }.value
            return data
        } catch {
            return nil
        }
    }

    nonisolated private static func decodeOffMain(fileURL: URL, maxPixelEdge: CGFloat?) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            decodeImageFromDisk(fileURL: fileURL, maxPixelEdge: maxPixelEdge)
        }.value
    }

    nonisolated private static func decodeOffMain(data: Data, maxPixelEdge: CGFloat?) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            decodeImage(data: data, maxPixelEdge: maxPixelEdge)
        }.value
    }

    nonisolated private static func decodeImageFromDisk(fileURL: URL, maxPixelEdge: CGFloat?) -> UIImage? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        return makeImage(from: source, maxPixelEdge: maxPixelEdge)
    }

    nonisolated private static func decodeImage(data: Data, maxPixelEdge: CGFloat?) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        return makeImage(from: source, maxPixelEdge: maxPixelEdge) ?? UIImage(data: data)
    }

    /// 用 ImageIO 一次性「解码即降采样」：避免先解整张大图再二次重绘，主线程零负担。
    nonisolated private static func makeImage(from source: CGImageSource, maxPixelEdge: CGFloat?) -> UIImage? {
        if let edge = maxPixelEdge {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(max(1, edge))
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 骨架闪烁占位

struct ComicShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            Rectangle()
                .fill(AppTheme.surface)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.10),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(1, width * 0.55))
                    .offset(x: phase * width * 1.7)
                    .allowsHitTesting(false)
                )
                .clipped()
        }
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

// MARK: - SwiftUI 单格

struct ComicPanelImage: View {
    let panel: ComicPanelDisplay
    var maxPixelEdge: CGFloat? = nil
    @ObservedObject private var loader = ComicImageLoader.shared

    private var currentImage: UIImage? {
        loader.image(for: panel, maxPixelEdge: maxPixelEdge)
    }

    var body: some View {
        Group {
            if let uiImage = currentImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ComicShimmerView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: loader.cacheKey(for: panel, maxPixelEdge: maxPixelEdge)) {
            _ = await loader.load(panel: panel, maxPixelEdge: maxPixelEdge)
        }
    }
}

// MARK: - 全屏渐进：先 preview，再降采样清晰图

struct ComicPanelProgressiveImage: View {
    let previewPanel: ComicPanelDisplay
    let sharpPanel: ComicPanelDisplay
    @ObservedObject private var loader = ComicImageLoader.shared
    @State private var revealSharp = false

    private var previewImage: UIImage? {
        loader.image(for: previewPanel)
    }

    private var sharpImage: UIImage? {
        loader.image(for: sharpPanel, maxPixelEdge: ComicImageLoader.fullscreenMaxPixelEdge)
    }

    var body: some View {
        ZStack {
            if let preview = previewImage {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
            } else if sharpImage == nil {
                ComicShimmerView()
            }

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
        .task(id: loader.cacheKey(for: previewPanel)) {
            _ = await loader.load(panel: previewPanel)
        }
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
