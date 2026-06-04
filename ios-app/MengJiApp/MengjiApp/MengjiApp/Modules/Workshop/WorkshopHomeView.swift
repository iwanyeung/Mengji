import SwiftUI

struct WorkshopHomeView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var jobStore = ComicGenerationJobStore.shared
    @EnvironmentObject private var dreamStore: DreamStore
    @Environment(\.openPersonalCenter) private var openPersonalCenter

    @State private var selectedDreamId: UUID?
    @State private var navigateToStyleSelection = false
    @State private var navigateToComicResult = false
    @State private var showDreamPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppAuroraBackground(style: .workshop)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ComicJobBanner(
                            jobStore: jobStore,
                            onViewProgress: { jobStore.reopenProgress() },
                            onViewResult: { navigateToComicResult = true },
                            onRetryAfterFailure: {
                                if let payload = jobStore.failurePayload {
                                    jobStore.clearFailureState()
                                    appState.openWorkshop(from: payload.dreamId)
                                }
                            }
                        )

                        header
                        selectedDreamSection
                        dreamPickerButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }
            .navigationDestination(isPresented: $navigateToStyleSelection) {
                StyleSelectionView(dreamId: selectedDreamId, appState: appState)
            }
            .navigationDestination(isPresented: $navigateToComicResult) {
                if let artifact = jobStore.completedArtifact {
                    ComicResultView(
                        dreamId: dreamId(for: artifact),
                        artifact: artifact,
                        appState: appState
                    )
                    .onDisappear {
                        jobStore.clearCompletedArtifact()
                    }
                }
            }
            .sheet(isPresented: $showDreamPicker) {
                DreamSelectionView(
                    selectedId: $selectedDreamId,
                    onConfirm: {
                        showDreamPicker = false
                    }
                )
                .environmentObject(dreamStore)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomCTA
            }
            .navigationTitle("梦作间")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileNavButton(style: .compact) {
                        openPersonalCenter()
                    }
                }
            }
        }
        .onAppear {
            if let pendingId = appState.pendingDreamIdForWorkshop {
                selectedDreamId = pendingId
                appState.pendingDreamIdForWorkshop = nil
            } else if selectedDreamId == nil {
                selectedDreamId = dreamStore.visibleDreams().first?.id
            }
            openComicResultIfNeeded()
        }
        .onChange(of: appState.pendingDreamIdForWorkshop) { _, newId in
            if let id = newId {
                selectedDreamId = id
                appState.pendingDreamIdForWorkshop = nil
            }
        }
        .onChange(of: jobStore.completedArtifact?.id) { _, _ in
            openComicResultIfNeeded()
        }
        .onChange(of: jobStore.shouldAutoOpenComicResult) { _, _ in
            openComicResultIfNeeded()
        }
    }

    private func openComicResultIfNeeded() {
        guard jobStore.shouldAutoOpenComicResult,
              jobStore.completedArtifact != nil else { return }
        navigateToComicResult = true
        jobStore.shouldAutoOpenComicResult = false
    }

    private func dreamId(for artifact: ComicArtifact) -> UUID? {
        dreamStore.visibleDreams().first(where: { dream in
            dream.comicArtifacts.contains(where: { $0.id == artifact.id })
        })?.id
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("把某一晚的梦，变成可以拿在手里的四格故事。")
                .font(AppTheme.bodyFont(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.text)

            Text("选一条你想继续的梦，让它落成一组四格故事。")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
        }
    }

    private var selectedDreamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(AppTheme.primaryColor)
                    .frame(width: 18, height: 1)
                Text("已选中的梦")
                    .font(AppTheme.capsFont(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(1.4)
                    .foregroundColor(AppTheme.muted)
            }

            if let id = selectedDreamId,
               let dream = dreamStore.dream(id: id) {
                DreamSummaryCard(dream: dream)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("还没有选中哪一条梦")
                        .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.text)
                    Text("可以从最近整理好的梦里挑一条，作为这次落成的起点。")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundColor(AppTheme.muted)
                }
            }
        }
    }

    private var dreamPickerButton: some View {
        Button {
            withAnimation(WorkshopMotion.navigationSpring) {
                showDreamPicker = true
            }
        } label: {
            HStack(spacing: 10) {
                Text("从梦中挑选")
                Spacer()
                Image(systemName: "chevron.down")
            }
            .font(AppTheme.bodyFont(size: 14, weight: .semibold))
            .foregroundColor(AppTheme.text)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(AppTheme.surface, lineWidth: 1)
                    .background(AppTheme.background.opacity(0.8))
            )
        }
        .buttonStyle(WorkshopSecondaryButtonStyle())
    }

    private var bottomCTA: some View {
        VStack(spacing: 0) {
            Button {
                if selectedDreamId == nil {
                    selectedDreamId = dreamStore.visibleDreams().first?.id
                }
                if selectedDreamId != nil {
                    Analytics.track("workshop_start_from_home", properties: [
                        "dreamId": selectedDreamId?.uuidString ?? ""
                    ])
                    withAnimation(WorkshopMotion.navigationSpring) {
                        navigateToStyleSelection = true
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text("继续 · 选择四格漫画风格")
                    Spacer()
                    Image(systemName: "sparkles")
                }
                .font(AppTheme.bodyFont(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.background)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(AppTheme.primaryColor)
            }
            .buttonStyle(WorkshopPrimaryCTAButtonStyle())
            .disabled(dreamStore.visibleDreams().isEmpty)
            .opacity(dreamStore.visibleDreams().isEmpty ? 0.4 : 1.0)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(AppTheme.background.opacity(0.92))
    }
}

private struct ComicJobBanner: View {
    @ObservedObject var jobStore: ComicGenerationJobStore
    var onViewProgress: () -> Void
    var onViewResult: () -> Void
    var onRetryAfterFailure: () -> Void

    var body: some View {
        Group {
            if jobStore.phase == .polling, let job = jobStore.activeJob {
                bannerCard(
                    title: "《\(job.dreamTitle)》四格生成中 · 第 \(min(jobStore.panelProgress, 4))/4 格",
                    subtitle: jobStore.statusMessage,
                    actionTitle: "查看进度",
                    action: onViewProgress
                )
            } else if jobStore.hasUnreadCompletion {
                let title = jobStore.completedDreamTitle ?? "你的梦"
                bannerCard(
                    title: "《\(title)》四格已落成",
                    subtitle: "点按查看这次落成的四格故事。",
                    actionTitle: "查看四格",
                    action: onViewResult
                )
            } else if jobStore.phase == .failed, let payload = jobStore.failurePayload,
                      let dream = DreamStore.shared.dream(id: payload.dreamId) {
                bannerCard(
                    title: "《\(dream.title)》四格未能完整落成",
                    subtitle: payload.userMessage,
                    actionTitle: "重试",
                    action: onRetryAfterFailure,
                    accent: AppTheme.accent
                )
            }
        }
    }

    private func bannerCard(
        title: String,
        subtitle: String,
        actionTitle: String,
        action: @escaping () -> Void,
        accent: Color = AppTheme.primaryColor
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(AppTheme.bodyFont(size: 12))
                .foregroundColor(AppTheme.muted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                Text(actionTitle)
                    .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                    .foregroundColor(accent)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(accent.opacity(0.45), lineWidth: 1)
                .background(AppTheme.background.opacity(0.75))
        )
    }
}

private struct DreamSummaryCard: View {
    let dream: Dream

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dream.title)
                .font(AppTheme.titleFont(size: 16))
                .kerning(-0.2)
                .foregroundColor(AppTheme.text)

            Text(shortPreview(from: dream.organizedText))
                .font(AppTheme.bodyFont(size: 14))
                .foregroundColor(AppTheme.muted)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(dateString(for: dream.createdAt))
                    .font(AppTheme.capsFont(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.muted)
                if dream.hasComic {
                    Text("已落成")
                        .font(AppTheme.capsFont(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppTheme.primaryColor)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(AppTheme.surface, lineWidth: 1)
                .background(AppTheme.background.opacity(0.7))
        )
    }

    private func shortPreview(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 40
        if trimmed.count <= limit { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<idx]) + "…"
    }

    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}
