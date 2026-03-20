import SwiftUI

struct WorkshopHomeView: View {
    @ObservedObject var appState: AppState
    @EnvironmentObject private var dreamStore: DreamStore

    @State private var selectedDreamId: UUID?
    @State private var navigateToStyleSelection = false
    @State private var showDreamPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    header
                    selectedDreamSection
                    actionButtons

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)

                NavigationLink(
                    destination: StyleSelectionView(dreamId: selectedDreamId),
                    isActive: $navigateToStyleSelection
                ) {
                    EmptyView()
                }
                .hidden()
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
            .navigationTitle("显化工坊")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if let pendingId = appState.pendingDreamIdForWorkshop {
                selectedDreamId = pendingId
                appState.pendingDreamIdForWorkshop = nil
            } else if selectedDreamId == nil {
                selectedDreamId = dreamStore.visibleDreams().first?.id
            }
        }
        .onChange(of: appState.pendingDreamIdForWorkshop) { _, newId in
            if let id = newId {
                selectedDreamId = id
                appState.pendingDreamIdForWorkshop = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("把某一晚的梦，变成可以拿在手里的四格故事。")
                .font(.system(size: 16, weight: .regular, design: .default))
                .foregroundColor(AppTheme.text)

            Text("请选择一条你想显化的梦，再为它挑一个合适的视觉风格。")
                .font(.system(size: 12, weight: .regular, design: .default))
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
                    .font(.system(size: 11, weight: .semibold, design: .default))
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
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(AppTheme.text)
                    Text("可以从最近整理好的梦里挑一条，作为这次显化的起点。")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(AppTheme.muted)
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showDreamPicker = true
            } label: {
                HStack(spacing: 10) {
                    Text("从梦中挑选")
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.text)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(AppTheme.surface, lineWidth: 1)
                        .background(AppTheme.background.opacity(0.8))
                )
            }
            .buttonStyle(.plain)

            Button {
                if selectedDreamId == nil {
                    selectedDreamId = dreamStore.visibleDreams().first?.id
                }
                if selectedDreamId != nil {
                    Analytics.track("workshop_start_from_home", properties: [
                        "dreamId": selectedDreamId?.uuidString ?? ""
                    ])
                    navigateToStyleSelection = true
                }
            } label: {
                HStack(spacing: 10) {
                    Text("继续 · 选择四格漫画风格")
                    Spacer()
                    Image(systemName: "sparkles")
                }
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.background)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(AppTheme.primaryColor)
            }
            .buttonStyle(.plain)
            .disabled(dreamStore.visibleDreams().isEmpty)
            .opacity(dreamStore.visibleDreams().isEmpty ? 0.4 : 1.0)
        }
    }
}

private struct DreamSummaryCard: View {
    let dream: Dream

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dream.title)
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.text)

            Text(shortPreview(from: dream.organizedText))
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundColor(AppTheme.muted)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(dateString(for: dream.createdAt))
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundColor(AppTheme.muted)
                if dream.hasComic {
                    Text("已显化")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundColor(AppTheme.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppTheme.primaryColor)
                }
            }
        }
        .padding(16)
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

