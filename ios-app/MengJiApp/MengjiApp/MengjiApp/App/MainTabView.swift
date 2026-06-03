//
//  MainTabView.swift
//  MengjiApp
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var appState = AppState()
    @StateObject private var dreamStore = DreamStore.shared
    @ObservedObject private var jobStore = ComicGenerationJobStore.shared
    @State private var recordingBlurTitleReplayToken: UInt = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: Binding(
            get: { appState.selectedTab },
            set: { appState.selectedTab = $0 }
        )) {
            RecordingTabView(
                blurTitleReplayToken: recordingBlurTitleReplayToken,
                onFinishRecording: { dreamId in
                    appState.openInsightAfterRecording(dreamId: dreamId)
                }
            )
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

            StarMapView(
                isTabActive: appState.selectedTab == .starMap,
                onSelectDream: { dreamId in
                    appState.openInsight(dreamId: dreamId)
                },
                onViewComic: { dreamId in
                    appState.openComic(dreamId: dreamId)
                }
            )
                .tabItem {
                    Label(AppTab.starMap.title, systemImage: AppTab.starMap.systemImage)
                }
                .tag(AppTab.starMap)
        }
        .tint(AppTheme.primaryColor)
        .preferredColorScheme(.dark)
        .environmentObject(dreamStore)
        .appToastOverlay(message: $jobStore.toastMessage, style: .success, bottomPadding: 96)
        .fullScreenCover(isPresented: $jobStore.isShowingFullScreenCover) {
            ComicGeneratingView(
                dreamTitle: jobStore.activeJob?.dreamTitle ?? "",
                panelCount: jobStore.panelProgress,
                statusMessage: jobStore.statusMessage,
                onMinimize: { jobStore.minimize() }
            )
        }
        .fullScreenCover(isPresented: $jobStore.showFailureCover) {
            if let payload = jobStore.failurePayload {
                ComicGenerationFailureView(
                    payload: payload,
                    onRetry: {
                        jobStore.dismissFailure()
                        appState.openWorkshop(from: payload.dreamId)
                    },
                    onChangeStyle: {
                        jobStore.dismissFailure()
                        appState.selectedTab = .workshop
                    },
                    onEditDream: {
                        jobStore.dismissFailure()
                        appState.openInsight(dreamId: payload.dreamId)
                    },
                    onStayInStarMap: {
                        jobStore.dismissFailure()
                        appState.openStarMap()
                    }
                )
            }
        }
        .onChange(of: appState.selectedTab) { old, new in
            if new == .recording && old != .recording {
                recordingBlurTitleReplayToken &+= 1
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                jobStore.pausePolling()
            case .active:
                jobStore.refreshPendingIfNeeded()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .task {
            PushNotificationService.shared.onVisualPush = { visualId in
                appState.selectedTab = .workshop
                if let dreamId = ComicGenerationJobStore.shared.activeJob?.dreamId {
                    appState.pendingDreamIdForWorkshop = dreamId
                } else {
                    await refreshWorkshopDreamForVisual(visualId: visualId, appState: appState)
                }
            }
            jobStore.refreshPendingIfNeeded()
            await PushNotificationService.shared.processPendingPushIfNeeded()
            await PushNotificationService.shared.requestAuthorizationIfNeeded()
        }
    }

    private func refreshWorkshopDreamForVisual(visualId: String, appState: AppState) async {
        do {
            let detail = try await VisualService.shared.fetchAuthorized(visualId: visualId)
            if let dreamId = UUID(uuidString: detail.dreamId) {
                appState.pendingDreamIdForWorkshop = dreamId
            }
        } catch {
            // 梦作间仍可手动选择梦境
        }
    }
}

/// 录梦 Tab 容器（仅包装一层，便于传入完成回调）
private struct RecordingTabView: View {
    var blurTitleReplayToken: UInt
    var onFinishRecording: (UUID) -> Void

    var body: some View {
        NavigationStack {
            RecordingView(
                onFinishRecording: onFinishRecording,
                blurTitleReplayToken: blurTitleReplayToken
            )
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
        .onAppear {
            // 兜底：当 pendingDreamIdForInsight 在 Tab 切换瞬间写入时，onChange 可能出现时序错过。
            if let id = appState.pendingDreamIdForInsight {
                navigationPath.append(id)
                appState.clearPendingDreamId()
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(\.openPersonalCenter, {})
}
