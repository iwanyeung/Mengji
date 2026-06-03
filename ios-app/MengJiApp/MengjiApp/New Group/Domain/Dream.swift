import Foundation

struct ComicArtifact: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let styleId: String
    let previewDescription: String
    /// 本地完整分辨率相对路径（Documents/comic-panels/…）
    let imagePaths: [String]
    /// 服务端完整分辨率 URL
    let remoteImageURLs: [URL]
    /// 本地缩略图相对路径
    let thumbImagePaths: [String]
    /// 服务端 768px 缩略图 URL
    let remoteThumbImageURLs: [URL]

    init(
        id: UUID,
        createdAt: Date,
        styleId: String,
        previewDescription: String,
        imagePaths: [String] = [],
        remoteImageURLs: [URL] = [],
        thumbImagePaths: [String] = [],
        remoteThumbImageURLs: [URL] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.styleId = styleId
        self.previewDescription = previewDescription
        self.imagePaths = imagePaths
        self.remoteImageURLs = remoteImageURLs
        self.thumbImagePaths = thumbImagePaths
        self.remoteThumbImageURLs = remoteThumbImageURLs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        styleId = try container.decode(String.self, forKey: .styleId)
        previewDescription = try container.decode(String.self, forKey: .previewDescription)
        imagePaths = try container.decodeIfPresent([String].self, forKey: .imagePaths) ?? []
        remoteImageURLs = try container.decodeIfPresent([URL].self, forKey: .remoteImageURLs) ?? []
        thumbImagePaths = try container.decodeIfPresent([String].self, forKey: .thumbImagePaths) ?? []
        remoteThumbImageURLs = try container.decodeIfPresent([URL].self, forKey: .remoteThumbImageURLs) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, styleId, previewDescription, imagePaths, remoteImageURLs
        case thumbImagePaths, remoteThumbImageURLs
    }
}

enum ComicImageQuality {
    /// 结果页条漫：768px 缩略图
    case preview
    /// 全屏查看：优先本地/缩略图，网络层按最长边降采样（非 2K 原图）
    case fullscreen
    case full
}

struct ComicPanelDisplay: Identifiable {
    let id: Int
    let remoteURL: URL
    let localRelativePath: String?

    init(index: Int, remoteURL: URL, localRelativePath: String?) {
        self.id = index
        self.remoteURL = remoteURL
        self.localRelativePath = localRelativePath
    }
}

extension ComicArtifact {
    func panels(for quality: ComicImageQuality) -> [ComicPanelDisplay] {
        let count = max(
            remoteImageURLs.count,
            remoteThumbImageURLs.count,
            imagePaths.count,
            thumbImagePaths.count
        )
        guard count > 0 else { return [] }

        return (0..<count).map { index in
            switch quality {
            case .preview:
                let remote = remoteThumbImageURLs.indices.contains(index)
                    ? remoteThumbImageURLs[index]
                    : remoteImageURLs[index]
                let localRel = thumbImagePaths.indices.contains(index) ? thumbImagePaths[index] : ""
                let local = (!localRel.isEmpty && ComicPanelDiskCache.fileExists(relativePath: localRel))
                    ? localRel
                    : nil
                return ComicPanelDisplay(index: index, remoteURL: remote, localRelativePath: local)
            case .fullscreen:
                let remote = remoteImageURLs.indices.contains(index)
                    ? remoteImageURLs[index]
                    : remoteThumbImageURLs[index]
                let fullRel = imagePaths.indices.contains(index) ? imagePaths[index] : ""
                let thumbRel = thumbImagePaths.indices.contains(index) ? thumbImagePaths[index] : ""
                let localRel: String = {
                    if !fullRel.isEmpty, ComicPanelDiskCache.fileExists(relativePath: fullRel) {
                        return fullRel
                    }
                    if !thumbRel.isEmpty, ComicPanelDiskCache.fileExists(relativePath: thumbRel) {
                        return thumbRel
                    }
                    return ""
                }()
                let local = localRel.isEmpty ? nil : localRel
                return ComicPanelDisplay(index: index, remoteURL: remote, localRelativePath: local)
            case .full:
                let remote = remoteImageURLs.indices.contains(index)
                    ? remoteImageURLs[index]
                    : remoteThumbImageURLs[index]
                let localRel = imagePaths.indices.contains(index) ? imagePaths[index] : ""
                let local = (!localRel.isEmpty && ComicPanelDiskCache.fileExists(relativePath: localRel))
                    ? localRel
                    : nil
                return ComicPanelDisplay(index: index, remoteURL: remote, localRelativePath: local)
            }
        }
    }

    func remoteURLs(for quality: ComicImageQuality) -> [URL] {
        switch quality {
        case .preview:
            return remoteThumbImageURLs.isEmpty ? remoteImageURLs : remoteThumbImageURLs
        case .fullscreen, .full:
            return remoteImageURLs.isEmpty ? remoteThumbImageURLs : remoteImageURLs
        }
    }

    /// 四格是否已具备全屏所需资源（缩略图在内存 + 全屏档降采样图在内存）
    func isReadyForFullscreenDisplay() -> Bool {
        let previews = panels(for: .preview)
        let sharps = panels(for: .fullscreen)
        guard previews.count >= 4, sharps.count >= 4 else {
            return false
        }
        let loader = ComicImageLoader.shared
        return previews.allSatisfy { loader.image(for: $0) != nil }
            && sharps.allSatisfy {
                loader.image(for: $0, maxPixelEdge: ComicImageLoader.fullscreenMaxPixelEdge) != nil
            }
    }
}

enum DreamFeedbackType: String, Codable {
    case veryClose = "very_close"
    case aBitOff = "a_bit_off"
    case uncomfortable = "uncomfortable"
}

struct DreamFeedbackState: Equatable, Codable {
    var type: DreamFeedbackType?
    var optionalNote: String?
    var aBitOffSheetSeen: Bool = false
}

struct Dream: Identifiable, Codable {
    let id: UUID
    let createdAt: Date

    var rawTranscript: String
    var organizedText: String
    var interpretation: String
    var tags: [String]

    var title: String
    var note: String?

    var isArchived: Bool

    var comicArtifacts: [ComicArtifact]

    /// 梦境整理与当前解读是否可能不一致（服务端 narrative vs analysis hash）
    var analysisStale: Bool = false
    var feedback: DreamFeedbackState = DreamFeedbackState()
    var interpretationCollapsed: Bool = false

    var hasComic: Bool {
        !comicArtifacts.isEmpty
    }
}

