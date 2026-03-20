//
//  MainTabView.swift
//  MengjiApp
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var appState = AppState()
    @StateObject private var dreamStore = DreamStore.shared

    var body: some View {
        TabView(selection: Binding(
            get: { appState.selectedTab },
            set: { appState.selectedTab = $0 }
        )) {
            RecordingTabView(onFinishRecording: { dreamId in
                appState.openInsightAfterRecording(dreamId: dreamId)
            })
            .tabItem {
                Label(AppTab.recording.title, systemImage: AppTab.recording.systemImage)
            }
            .tag(AppTab.recording)

            InsightTabView(appState: appState)
                .tabItem {
                    Label(AppTab.insight.title, systemImage: AppTab.insight.systemImage)
                }
                .tag(AppTab.insight)

            WorkshopHomeView(appState: appState)
                .tabItem {
                    Label(AppTab.workshop.title, systemImage: AppTab.workshop.systemImage)
                }
                .tag(AppTab.workshop)

            StarMapPlaceholderView()
                .tabItem {
                    Label(AppTab.starMap.title, systemImage: AppTab.starMap.systemImage)
                }
                .tag(AppTab.starMap)
        }
        .tint(AppTheme.primaryColor)
        .preferredColorScheme(.dark)
        .environmentObject(dreamStore)
    }
}

/// 录梦 Tab 容器（仅包装一层，便于传入完成回调）
private struct RecordingTabView: View {
    var onFinishRecording: (UUID) -> Void

    var body: some View {
        NavigationStack {
            RecordingView(onFinishRecording: onFinishRecording)
        }
    }
}

/// 梦析 Tab：列表 + 导航到详情；支持从录梦完成后直接推入指定 dreamId
struct InsightTabView: View {
    @ObservedObject var appState: AppState
    @State private var navigationPath = [UUID]()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            InsightListView(onSelectDream: { dreamId in
                navigationPath.append(dreamId)
            })
            .navigationDestination(for: UUID.self) { dreamId in
                InsightView(dreamId: dreamId, appState: appState)
            }
            .onChange(of: appState.pendingDreamIdForInsight) { _, newId in
                if let id = newId {
                    navigationPath.append(id)
                    appState.clearPendingDreamId()
                }
            }
        }
    }
}

#Preview {
    MainTabView()
}
