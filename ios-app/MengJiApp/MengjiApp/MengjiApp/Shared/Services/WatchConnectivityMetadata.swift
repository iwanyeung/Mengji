import Foundation

/// Watch ↔ iPhone 传输元数据键（两端须保持一致）
enum WatchConnectivityMetadata {
    static let dreamId = "dreamId"
    static let occurredAt = "occurredAt"
    static let source = "source"
    static let durationSeconds = "durationSeconds"
    static let segmentIndex = "segmentIndex"
    static let segmentId = "segmentId"
    /// iPhone → Watch：当前活跃录梦会话
    static let activeDreamId = "activeDreamId"
    static let draftCount = "draftCount"
    /// iPhone → Watch：完成类通知
    static let notifyEvent = "event"
    static let notifyVisualId = "visualId"
}
