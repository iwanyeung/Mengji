import SwiftUI

struct InsightView: View {
    var dreamId: UUID?
    @StateObject private var viewModel: InsightViewModel
    @ObservedObject private var appState: AppState
    @EnvironmentObject private var dreamStore: DreamStore
    @Environment(\.dismiss) private var dismiss

    @State private var showManageSheet = false
    @State private var editedTitle: String = ""
    @State private var editedNote: String = ""
    @State private var editedTagsText: String = ""
    @State private var showDeleteConfirmation = false
    @State private var navigateToComicResult = false
    @State private var selectedComicArtifactId: UUID?
    @State private var selectedArtifactIndexForReview: Int = 0

    init(dreamId: UUID? = nil, appState: AppState) {
        self.dreamId = dreamId
        _appState = ObservedObject(wrappedValue: appState)
        _viewModel = StateObject(wrappedValue: InsightViewModel(dreamId: dreamId))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppAuroraBackground(
                style: .insight,
                prioritizeTextReadability: true
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    headerSection
                    organizedTextSection
                    tagsSection
                    interpretationSection
                    comicSection
                    feedbackSection
                    disclaimerSection
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 120)
            }

            bottomCTA
        }
        .navigationDestination(isPresented: $navigateToComicResult) {
            ComicResultView(
                dreamId: currentDream?.id,
                artifactId: selectedComicArtifactId,
                appState: appState
            )
        }
        .onAppear {
            if appState.pendingOpenComicFromInsight {
                openLatestComicIfAvailable()
                appState.clearPendingComicOpenFlag()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.current.dateString)
                        .font(AppTheme.capsFont(size: 12, weight: .semibold))
                        .textCase(.uppercase)
                        .kerning(1.6)
                        .foregroundColor(AppTheme.muted)

                    Text(viewModel.current.timeString)
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundColor(AppTheme.muted.opacity(0.9))
                }
                Spacer()
                Button {
                    prepareEditState()
                    showManageSheet = true
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(AppTheme.muted)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(viewModel.current.title)
                .font(AppTheme.titleFont(size: 26))
                .kerning(-1)
                .foregroundColor(AppTheme.text)
                .padding(.top, 8)

            Rectangle()
                .fill(AppTheme.surface)
                .frame(height: 1)
                .padding(.top, 12)
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("这一段梦给你的感觉")

            Text("如果你觉得这次梦析有哪里不对劲、太刺激，或者特别有共鸣，都可以告诉梦悸。你的感受会被用来温柔地调整后续的解读。")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)

            HStack(spacing: 8) {
                Button {
                    viewModel.toggleFeedback(.veryClose)
                } label: {
                    feedbackChip(
                        text: "很贴近我",
                        systemImage: "hand.thumbsup.fill",
                        isSelected: viewModel.feedback == .veryClose
                    )
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.toggleFeedback(.aBitOff)
                } label: {
                    feedbackChip(
                        text: "有点偏差",
                        systemImage: "hand.thumbsdown.fill",
                        isSelected: viewModel.feedback == .aBitOff
                    )
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.toggleFeedback(.uncomfortable)
                } label: {
                    feedbackChip(
                        text: "让我有点不舒服",
                        systemImage: "exclamationmark.triangle.fill",
                        isSelected: viewModel.feedback == .uncomfortable
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var organizedTextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("梦境整理")

            Text(viewModel.current.organizedText)
                .font(AppTheme.bodyFont(size: 16))
                .foregroundColor(AppTheme.text.opacity(0.95))
                .lineSpacing(6)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("关键词与意象")

            FlexibleTagWrap(tags: viewModel.current.tags)
        }
    }

    private var interpretationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("梦的可能含义")

            Text(viewModel.current.interpretation)
                .font(AppTheme.bodyFont(size: 15))
                .foregroundColor(AppTheme.text.opacity(0.9))
                .lineSpacing(6)
        }
    }

    @ViewBuilder
    private var comicSection: some View {
        if let dream = currentDream, let latest = dream.comicArtifacts.last {
            let sortedArtifacts = dream.comicArtifacts.sorted { $0.createdAt > $1.createdAt }
            let selectedArtifact = selectedArtifactFrom(sortedArtifacts) ?? latest
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("已落成四格")

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("共 \(dream.comicArtifacts.count) 版")
                            .font(AppTheme.capsFont(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.muted)

                        Text("最近落成：\(comicDateTimeString(from: latest.createdAt))")
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundColor(AppTheme.muted.opacity(0.95))
                    }

                    if sortedArtifacts.count > 1 {
                        Picker("选择回看版本", selection: $selectedArtifactIndexForReview) {
                            ForEach(Array(sortedArtifacts.enumerated()), id: \.element.id) { index, artifact in
                                Text("第\(sortedArtifacts.count - index)版 · \(comicDateTimeString(from: artifact.createdAt))")
                                    .tag(index)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppTheme.text)
                    }

                    Text(selectedArtifact.previewDescription)
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundColor(AppTheme.muted)
                        .lineSpacing(4)

                    Button {
                        selectedComicArtifactId = selectedArtifact.id
                        navigateToComicResult = true
                    } label: {
                        HStack {
                            Text("回看这组四格故事")
                            Spacer()
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.text)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(AppTheme.surface.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .strokeBorder(AppTheme.muted.opacity(0.45), lineWidth: 1)
                        )
                    }
                    .tint(AppTheme.muted)
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(AppTheme.surface, lineWidth: 1)
                        .background(AppTheme.background.opacity(0.55))
                )
            }
            .onAppear {
                selectedArtifactIndexForReview = 0
            }
        }
    }

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("温柔提醒")
                .font(AppTheme.capsFont(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(1.4)
                .foregroundColor(AppTheme.muted)

            Text("梦悸提供的是一种温柔的心理陪伴视角，而不是医学或心理治疗建议。如你正在经历强烈的情绪波动或长期的身心困扰，请优先寻求专业帮助。")
                .font(AppTheme.bodyFont(size: 11))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(AppTheme.surface, lineWidth: 1)
                .background(AppTheme.background.opacity(0.6))
        )
    }

    private var bottomCTA: some View {
        VStack(spacing: 10) {
            Button {
                if let id = dreamId {
                    Analytics.track("insight_to_workshop", properties: [
                        "dreamId": id.uuidString
                    ])
                    appState.openWorkshop(from: id)
                }
            } label: {
                HStack {
                    Text(hasComicForCurrentDream ? "重新落成四格故事" : "让这条梦落成四格故事")
                    Spacer()
                    Image(systemName: "sparkles")
                }
                .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.background)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .background(AppTheme.primaryColor)
                .cornerRadius(0)
            }

            if hasComicForCurrentDream {
                Text("将基于同一梦境生成新版本，不会覆盖你已落成的四格。")
                    .font(AppTheme.bodyFont(size: 11))
                    .foregroundColor(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                if let id = dreamId {
                    Analytics.track("insight_save_to_star_map", properties: [
                        "dreamId": id.uuidString
                    ])
                    appState.openStarMap()
                }
            } label: {
                HStack {
                    Text("先留在潜意识星图里")
                    Spacer()
                    Image(systemName: "point.topleft.down.curvedto.point.filled.bottomright.up")
                }
                .font(AppTheme.bodyFont(size: 12, weight: .medium))
                .foregroundColor(AppTheme.text.opacity(0.9))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(AppTheme.surface.opacity(0.95))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .background(
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [AppTheme.background.opacity(0.0), AppTheme.background.opacity(0.95)]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                // CTA 区局部加深：在极光亮度波峰时保持按钮文字对比稳定。
                LinearGradient(
                    gradient: Gradient(colors: [Color.clear, AppTheme.background.opacity(0.78)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .sheet(isPresented: $showManageSheet) {
            NavigationStack {
                VStack(spacing: 0) {
                    Form {
                        Section("标题与备注") {
                            TextField("梦的标题", text: $editedTitle)
                            TextField("给这条梦加一句你的注解", text: $editedNote, axis: .vertical)
                        }

                        Section("关键词与标签") {
                            TextField("用顿号、逗号或空格分隔多个标签", text: $editedTagsText)
                        }

                        Section {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Text("删除这条梦")
                            }
                        }
                    }
                    .alert("确认删除这条梦？", isPresented: $showDeleteConfirmation) {
                        Button("删除这条梦", role: .destructive) {
                            viewModel.deleteCurrent()
                            dismiss()
                        }
                        Button("取消", role: .cancel) {}
                    }

                    HStack {
                        Button("取消") {
                            showManageSheet = false
                        }
                        .foregroundColor(AppTheme.muted)

                        Spacer()

                        Button("保存修改") {
                            viewModel.applyEdits(
                                title: editedTitle,
                                note: editedNote,
                                tagsText: editedTagsText
                            )
                            showManageSheet = false
                        }
                        .foregroundColor(AppTheme.background)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.primaryColor)
                    }
                    .padding()
                }
                .navigationTitle("管理这条梦")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(AppTheme.primaryColor)
                .frame(width: 18, height: 1)
            Text(text)
                .font(AppTheme.capsFont(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(1.4)
                .foregroundColor(AppTheme.muted)
        }
    }

    private func feedbackChip(
        text: String,
        systemImage: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(AppTheme.bodyFont(size: 11))
        .foregroundColor(
            isSelected ? AppTheme.background : AppTheme.text.opacity(0.9)
        )
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(isSelected ? AppTheme.primaryColor : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .strokeBorder(AppTheme.surface, lineWidth: 1)
                )
        )
    }

    private func prepareEditState() {
        editedTitle = viewModel.current.title
        editedNote = viewModel.current.note ?? ""
        editedTagsText = viewModel.current.tags.joined(separator: "、")
    }

    private var currentDream: Dream? {
        let id = dreamId ?? viewModel.current.id
        return dreamStore.dream(id: id)
    }

    private var hasComicForCurrentDream: Bool {
        currentDream?.hasComic == true
    }

    private func openLatestComicIfAvailable() {
        guard let latest = currentDream?.comicArtifacts.last else { return }
        selectedComicArtifactId = latest.id
        navigateToComicResult = true
    }

    private func selectedArtifactFrom(_ artifacts: [ComicArtifact]) -> ComicArtifact? {
        guard !artifacts.isEmpty else { return nil }
        let index = min(max(selectedArtifactIndexForReview, 0), artifacts.count - 1)
        return artifacts[index]
    }

    private func comicDateTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: date)
    }
}

private struct TagWrapWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 340
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FlexibleTagWrap: View {
    let tags: [String]
    @State private var containerWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows(maxWidth: containerWidth), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { tag in
                        Text(tag)
                            .font(AppTheme.bodyFont(size: 12))
                            .foregroundColor(AppTheme.text.opacity(0.9))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 999)
                                    .strokeBorder(AppTheme.surface, lineWidth: 1)
                                    .background(AppTheme.background.opacity(0.4))
                            )
                    }
                }
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TagWrapWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(TagWrapWidthPreferenceKey.self) { containerWidth = $0 }
    }

    private func rows(maxWidth: CGFloat) -> [[String]] {
        var rows: [[String]] = [[]]
        var currentRowWidth: CGFloat = 0

        for tag in tags {
            let tagWidth = estimateTagWidth(tag)
            if currentRowWidth + tagWidth > maxWidth {
                rows.append([tag])
                currentRowWidth = tagWidth
            } else {
                rows[rows.count - 1].append(tag)
                currentRowWidth += tagWidth
            }
        }

        return rows
    }

    private func estimateTagWidth(_ text: String) -> CGFloat {
        let baseWidth = CGFloat(text.count) * 7.5
        let padding: CGFloat = 10 * 2 + 4 // 左右 padding + 预留
        return baseWidth + padding
    }
}

#Preview {
    InsightView(dreamId: nil, appState: AppState())
        .preferredColorScheme(.dark)
}

