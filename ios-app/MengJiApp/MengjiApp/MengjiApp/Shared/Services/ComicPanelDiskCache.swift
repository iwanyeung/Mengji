import Foundation

enum ComicPanelDiskCache {
    private static let rootFolderName = "comic-panels"

    static func rootDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent(rootFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    static func fileURL(relativePath: String) -> URL {
        rootDirectory().appendingPathComponent(relativePath)
    }

    static func fileExists(relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(relativePath: relativePath).path)
    }

    /// 仅下载缩略图（结果页快速展示）。
    static func persistThumbs(artifactId: UUID, thumbURLs: [URL]) async -> [String] {
        let folder = artifactId.uuidString.lowercased()
        let dir = rootDirectory().appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        return await withTaskGroup(of: (Int, String?).self) { group in
            for (index, url) in thumbURLs.enumerated() {
                group.addTask {
                    let rel = "\(folder)/panel_\(index)_thumb.jpg"
                    let ok = await download(url: url, to: fileURL(relativePath: rel))
                    return (index, ok ? rel : nil)
                }
            }
            var map: [Int: String] = [:]
            for await result in group {
                if let path = result.1 { map[result.0] = path }
            }
            return (0..<thumbURLs.count).map { map[$0] ?? "" }
        }
    }

    /// 下载完整分辨率（全屏/离线回看）。
    static func persistFullPanels(artifactId: UUID, fullURLs: [URL]) async -> [String] {
        let folder = artifactId.uuidString.lowercased()
        let dir = rootDirectory().appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        return await withTaskGroup(of: (Int, String?).self) { group in
            for (index, url) in fullURLs.enumerated() {
                group.addTask {
                    let rel = "\(folder)/panel_\(index)_full.png"
                    let ok = await download(url: url, to: fileURL(relativePath: rel))
                    return (index, ok ? rel : nil)
                }
            }
            var map: [Int: String] = [:]
            for await result in group {
                if let path = result.1 { map[result.0] = path }
            }
            return (0..<fullURLs.count).map { map[$0] ?? "" }
        }
    }

    /// 下载缩略图与完整图到本地；返回相对路径（相对于 comic-panels 根目录）。
    static func persistPanels(
        artifactId: UUID,
        thumbURLs: [URL],
        fullURLs: [URL]
    ) async -> (thumbPaths: [String], fullPaths: [String]) {
        async let thumbs = persistThumbs(artifactId: artifactId, thumbURLs: thumbURLs)
        async let fulls = persistFullPanels(artifactId: artifactId, fullURLs: fullURLs)
        return (await thumbs, await fulls)
    }

    private static func download(url: URL, to destination: URL) async -> Bool {
        if FileManager.default.fileExists(atPath: destination.path) {
            return true
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !data.isEmpty else { return false }
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

enum ComicArtifactService {
    @MainActor
    static func build(
        styleId: String,
        previewDescription: String,
        fullURLStrings: [String],
        thumbURLStrings: [String]? = nil,
        artifactId: UUID = UUID()
    ) async -> ComicArtifact {
        let fullURLs = fullURLStrings.compactMap { URL(string: $0) }
        let thumbURLs: [URL] = {
            if let thumbURLStrings, !thumbURLStrings.isEmpty {
                return thumbURLStrings.compactMap { URL(string: $0) }
            }
            return fullURLs
        }()

        await ComicImageLoader.shared.prefetchAll(thumbURLs)

        let thumbPaths = await ComicPanelDiskCache.persistThumbs(
            artifactId: artifactId,
            thumbURLs: thumbURLs
        )

        let artifact = ComicArtifact(
            id: artifactId,
            createdAt: Date(),
            styleId: styleId,
            previewDescription: previewDescription,
            imagePaths: [],
            remoteImageURLs: fullURLs,
            thumbImagePaths: thumbPaths,
            remoteThumbImageURLs: thumbURLs
        )

        return artifact
    }

    @MainActor
    static func scheduleFullDownload(artifactId: UUID, dreamId: UUID?, fullURLs: [URL]) {
        Task { @MainActor in
            await ComicImageLoader.shared.prefetchAll(fullURLs)
            let fullPaths = await ComicPanelDiskCache.persistFullPanels(
                artifactId: artifactId,
                fullURLs: fullURLs
            )
            guard fullPaths.contains(where: { !$0.isEmpty }) else { return }
            applyFullPaths(artifactId: artifactId, dreamId: dreamId, fullPaths: fullPaths)
        }
    }

    @MainActor
    private static func applyFullPaths(artifactId: UUID, dreamId: UUID?, fullPaths: [String]) {
        if let dreamId, var dream = DreamStore.shared.dream(id: dreamId),
           let index = dream.comicArtifacts.firstIndex(where: { $0.id == artifactId }) {
            let existing = dream.comicArtifacts[index]
            dream.comicArtifacts[index] = ComicArtifact(
                id: existing.id,
                createdAt: existing.createdAt,
                styleId: existing.styleId,
                previewDescription: existing.previewDescription,
                imagePaths: fullPaths,
                remoteImageURLs: existing.remoteImageURLs,
                thumbImagePaths: existing.thumbImagePaths,
                remoteThumbImageURLs: existing.remoteThumbImageURLs
            )
            DreamStore.shared.upsert(dream)
            return
        }

        for dream in DreamStore.shared.visibleDreams() {
            guard let index = dream.comicArtifacts.firstIndex(where: { $0.id == artifactId }) else { continue }
            var updated = dream
            let existing = updated.comicArtifacts[index]
            updated.comicArtifacts[index] = ComicArtifact(
                id: existing.id,
                createdAt: existing.createdAt,
                styleId: existing.styleId,
                previewDescription: existing.previewDescription,
                imagePaths: fullPaths,
                remoteImageURLs: existing.remoteImageURLs,
                thumbImagePaths: existing.thumbImagePaths,
                remoteThumbImageURLs: existing.remoteThumbImageURLs
            )
            DreamStore.shared.upsert(updated)
            break
        }
    }

    @MainActor
    static func refreshLocalCache(for artifact: ComicArtifact) async -> ComicArtifact {
        guard !artifact.remoteImageURLs.isEmpty else { return artifact }

        let thumbURLs = artifact.remoteThumbImageURLs.isEmpty
            ? artifact.remoteImageURLs
            : artifact.remoteThumbImageURLs

        let paths = await ComicPanelDiskCache.persistPanels(
            artifactId: artifact.id,
            thumbURLs: thumbURLs,
            fullURLs: artifact.remoteImageURLs
        )

        guard paths.thumbPaths.contains(where: { !$0.isEmpty })
            || paths.fullPaths.contains(where: { !$0.isEmpty }) else {
            return artifact
        }

        return ComicArtifact(
            id: artifact.id,
            createdAt: artifact.createdAt,
            styleId: artifact.styleId,
            previewDescription: artifact.previewDescription,
            imagePaths: paths.fullPaths.contains(where: { !$0.isEmpty }) ? paths.fullPaths : artifact.imagePaths,
            remoteImageURLs: artifact.remoteImageURLs,
            thumbImagePaths: paths.thumbPaths.contains(where: { !$0.isEmpty }) ? paths.thumbPaths : artifact.thumbImagePaths,
            remoteThumbImageURLs: thumbURLs
        )
    }
}
