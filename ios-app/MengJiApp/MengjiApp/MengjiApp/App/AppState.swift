//
//  AppState.swift
//  MengjiApp
//

import SwiftUI
import Combine

enum AppTab: Int, CaseIterable {
    case recording = 0
    case insight = 1
    case workshop = 2
    case starMap = 3

    var title: String {
        switch self {
        case .recording: return "录梦"
        case .insight: return "梦析"
        case .workshop: return "显化工坊"
        case .starMap: return "潜意识星图"
        }
    }

    var systemImage: String {
        switch self {
        case .recording: return "mic.fill"
        case .insight: return "text.book.closed.fill"
        case .workshop: return "paintbrush.pointed.fill"
        case .starMap: return "point.topleft.down.curvedto.point.filled.bottomright.up"
        }
    }
}

final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .recording
    /// 录梦完成后要打开的梦 ID，打开梦析后清空
    @Published var pendingDreamIdForInsight: UUID?
    /// 从梦析跳转到显化工坊时要预选的梦 ID，用完后清空
    @Published var pendingDreamIdForWorkshop: UUID?

    func openInsightAfterRecording(dreamId: UUID) {
        pendingDreamIdForInsight = dreamId
        selectedTab = .insight
    }

    func clearPendingDreamId() {
        pendingDreamIdForInsight = nil
    }

    /// 从梦析页进入显化工坊，并携带当前梦
    func openWorkshop(from dreamId: UUID) {
        pendingDreamIdForWorkshop = dreamId
        selectedTab = .workshop
    }

    /// 从梦析页跳转到潜意识星图
    func openStarMap() {
        selectedTab = .starMap
    }
}
