import Foundation

final class RecordingViewModel: ObservableObject {
    struct Segment: Identifiable {
        let id: UUID
        let preview: String
        let meta: String
    }

    @Published var segments: [Segment] = [
        Segment(id: UUID(), preview: "从高楼坠落到钟楼下方……", meta: "Oct 24 • 03:14 AM"),
        Segment(id: UUID(), preview: "牙齿碎成玻璃，在地上反光。", meta: "Oct 22 • 05:02 AM")
    ]

    var buttonHint: String {
        "按住录音"
    }
}

