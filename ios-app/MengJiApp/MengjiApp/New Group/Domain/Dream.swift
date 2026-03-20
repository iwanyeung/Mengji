import Foundation

struct ComicArtifact: Identifiable {
    let id: UUID
    let createdAt: Date
    let styleId: String
    let previewDescription: String
    let imagePaths: [String]
}

struct Dream: Identifiable {
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

    var hasComic: Bool {
        !comicArtifacts.isEmpty
    }
}

