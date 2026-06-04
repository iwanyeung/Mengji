import Foundation

/// WatchConnectivity 入站文件同步拷贝（须在 `didReceive` 返回前完成；须 `nonisolated` 以配合 MengjiApp 的默认 MainActor 隔离）。
enum WatchIncomingFileStaging: Sendable {
    nonisolated static let segmentIdMetadataKey = "segmentId"

    nonisolated static func copy(from sourceURL: URL, segmentId: UUID) -> URL? {
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-ingest-\(segmentId.uuidString).\(ext)")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return dest
        } catch {
            #if DEBUG
            print("[WatchIngest] copyItem error: \(error)")
            #endif
            return nil
        }
    }
}
