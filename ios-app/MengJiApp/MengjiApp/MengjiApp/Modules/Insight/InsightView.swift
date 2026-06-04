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
    @State private var editedOrganizedText: String = ""
    @State private var isEditingOrganizedText = false
    @State private var draftOrganizedText: String = ""
    @State private var showDeleteConfirmation = false
    @State private var navigateToComicResult = false
    @State private var selectedComicArtifactId: UUID?
    @State private var selectedArtifactIndexForReview: Int = 0
    @FocusState private var organizedTextFieldFocused: Bool
    @State private var showABitOffSheet = false
    @State private var showUncomfortableSheet = false
    @State private var showOrganizedSaveSheet = false
    @State private var feedbackOptionalNote = ""
    @State private var pendingOrganizedDraft = ""

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
                    if viewModel.analysisStale || viewModel.pendingSubstantialSave {
                        analysisStaleBanner
                    }
                    tagsSection
                    interpretationSection
                    if viewModel.feedback == .aBitOff {
                        aBitOffContinueBar
                    }
                    comicSection
                    feedbackSection
                    disclaimerSection
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, isEditingOrganizedText ? 40 : 120)
            }
            .scrollDismissesKeyboard(.interactively)

            if !isEditingOrganizedText {
                bottomCTA
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    dismissOrganizedTextKeyboard()
                }
                .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.primaryColor)
            }
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
            Task { await viewModel.refreshFromServer() }
        }
        .appToastOverlay(
            message: $viewModel.toastMessage,
            style: viewModel.toastStyle,
            bottomPadding: isEditingOrganizedText ? 48 : 132
        )
        .sheet(isPresented: $showABitOffSheet) {
            ABitOffFeedbackSheet(
                optionalNote: $feedbackOptionalNote,
                onEditNarrative: {
                    Task { await viewModel.markABitOffSheetSeen() }
                    startOrganizedTextEdit()
                },
                onReinterpretInterpretation: {
                    Task {
                        await viewModel.markABitOffSheetSeen()
                        _ = await viewModel.reinterpret(
                            mode: "default",
                            trigger: "feedback_off",
                            note: feedbackOptionalNote.nilIfEmpty
                        )
                    }
                },
                onReinterpretTags: {
                    Task {
                        await viewModel.markABitOffSheetSeen()
                        _ = await viewModel.reinterpret(
                            mode: "default",
                            trigger: "feedback_off",
                            note: feedbackOptionalNote.nilIfEmpty,
                            updateTags: true
                        )
                    }
                },
                onDismiss: {
                    showABitOffSheet = false
                    Task { await viewModel.markABitOffSheetSeen() }
                }
            )
        }
        .sheet(isPresented: $showUncomfortableSheet) {
            UncomfortableFeedbackSheet(
                onGentlerReinterpret: {
                    Task {
                        _ = await viewModel.reinterpret(mode: "gentler", trigger: "feedback_uncomfortable")
                    }
                },
                onCollapseInterpretation: {
                    viewModel.setInterpretationCollapsed(true)
                    viewModel.presentToast("已收起解读，你仍可查看梦境整理。")
                },
                onEditNarrative: { startOrganizedTextEdit() },
                onDismiss: { showUncomfortableSheet = false }
            )
        }
        .sheet(isPresented: $showOrganizedSaveSheet) {
            OrganizedTextSaveSheet(
                onSaveOnly: {
                    showOrganizedSaveSheet = false
                    Task {
                        _ = await viewModel.saveOrganizedText(pendingOrganizedDraft, andReinterpret: false)
                        dismissOrganizedTextKeyboard()
                        isEditingOrganizedText = false
                    }
                },
                onSaveAndReinterpret: {
                    showOrganizedSaveSheet = false
                    Task {
                        _ = await viewModel.saveOrganizedText(pendingOrganizedDraft, andReinterpret: true)
                        dismissOrganizedTextKeyboard()
                        isEditingOrganizedText = false
                    }
                },
                onCancel: { showOrganizedSaveSheet = false }
            )
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
                    if isEditingOrganizedText {
                        cancelOrganizedTextEdit()
                    }
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

            Text("你的感受会帮助梦悸调整这一条梦的解读方式；不是医疗或心理诊断。")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)

            HStack(spacing: 8) {
                Button {
                    Task { await handleFeedbackTap(.veryClose) }
                } label: {
                    feedbackChip(
                        text: "很贴近我",
                        systemImage: "hand.thumbsup.fill",
                        isSelected: viewModel.feedback == .veryClose
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Task { await handleFeedbackTap(.aBitOff) }
                } label: {
                    feedbackChip(
                        text: "有点偏差",
                        systemImage: "hand.thumbsdown.fill",
                        isSelected: viewModel.feedback == .aBitOff
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Task { await handleFeedbackTap(.uncomfortable) }
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
            HStack(alignment: .center, spacing: 8) {
                sectionLabel("梦境整理")
                Spacer(minLength: 8)
                if isEditingOrganizedText {
                    Button("取消") {
                        cancelOrganizedTextEdit()
                    }
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundColor(AppTheme.muted)
                    .buttonStyle(.plain)

                    Button("保存") {
                        saveOrganizedTextEdit()
                    }
                    .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.primaryColor)
                    .buttonStyle(.plain)
                } else {
                    Button {
                        startOrganizedTextEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AppTheme.primaryColor)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.background.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: 0)
                                    .strokeBorder(AppTheme.primaryColor.opacity(0.85), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("编辑梦境整理")
                }
            }

            if isEditingOrganizedText {
                TextEditor(text: $draftOrganizedText)
                    .font(AppTheme.bodyFont(size: 16))
                    .foregroundColor(AppTheme.text.opacity(0.95))
                    .scrollContentBackground(.hidden)
                    .focused($organizedTextFieldFocused)
                    .frame(minHeight: 140)
                    .padding(12)
                    .background(AppTheme.surface.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(AppTheme.muted.opacity(0.45), lineWidth: 1)
                    )
            } else {
                Text(viewModel.current.organizedText)
                    .font(AppTheme.bodyFont(size: 16))
                    .foregroundColor(AppTheme.text.opacity(0.95))
                    .lineSpacing(6)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("关键词与意象")

            TagFlowLayout(spacing: 8, maxRows: 2) {
                ForEach(viewModel.current.tags, id: \.self) { tag in
                    insightKeywordTag(tag)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func insightKeywordTag(_ tag: String) -> some View {
        Text(tag)
            .font(AppTheme.bodyFont(size: 12))
            .foregroundColor(AppTheme.text.opacity(0.9))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 999)
                    .strokeBorder(AppTheme.surface, lineWidth: 1)
                    .background(AppTheme.background.opacity(0.4))
            )
    }

    private var interpretationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("梦的可能含义")
                Spacer()
                if viewModel.interpretationCollapsed {
                    Button("展开") {
                        viewModel.setInterpretationCollapsed(false)
                    }
                    .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.primaryColor)
                } else {
                    Button("收起") {
                        viewModel.setInterpretationCollapsed(true)
                    }
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundColor(AppTheme.muted)
                }
            }

            if viewModel.isReinterpreting {
                ProgressView()
                    .tint(AppTheme.primaryColor)
                Text("正在根据你的整理更新解读…")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundColor(AppTheme.muted)
            } else if viewModel.interpretationCollapsed {
                Text("解读已收起。需要时可点「展开」。")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundColor(AppTheme.muted)
            } else {
                Text(viewModel.current.interpretation)
                    .font(AppTheme.bodyFont(size: 15))
                    .foregroundColor(
                        viewModel.analysisStale ? AppTheme.muted : AppTheme.text.opacity(0.9)
                    )
                    .lineSpacing(6)

                if viewModel.analysisStale {
                    Text("基于较早版本的整理")
                        .font(AppTheme.capsFont(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.muted)
                }
            }
        }
    }

    private var analysisStaleBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("梦境整理已更新，解读可能尚未同步。")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.text.opacity(0.9))

            Button {
                Task {
                    _ = await viewModel.reinterpret(mode: "default", trigger: "edit")
                }
            } label: {
                Text("根据当前内容更新解读")
                    .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.primaryColor)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(AppTheme.primaryColor.opacity(0.5), lineWidth: 1)
                .background(AppTheme.surface.opacity(0.35))
        )
    }

    private var aBitOffContinueBar: some View {
        Button {
            showABitOffSheet = true
        } label: {
            HStack(spacing: 6) {
                Text(
                    viewModel.analysisStale
                        ? "梦境整理已更新"
                        : "你标记了有点偏差"
                )
                Text("·")
                Text("继续调整")
                    .underline()
            }
            .font(AppTheme.bodyFont(size: 12, weight: .semibold))
            .foregroundColor(AppTheme.primaryColor)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        Section("梦境整理") {
                            TextField("修正语音转写或整理后的内容", text: $editedOrganizedText, axis: .vertical)
                                .lineLimit(5...20)
                        }

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
                                tagsText: editedTagsText,
                                organizedText: editedOrganizedText
                            )
                            Task {
                                let organized = editedOrganizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !organized.isEmpty {
                                    _ = await viewModel.saveOrganizedText(organized, andReinterpret: false)
                                }
                                if !editedTagsText.isEmpty {
                                    let separators = CharacterSet(charactersIn: "，,、 ")
                                    let tags = editedTagsText
                                        .components(separatedBy: separators)
                                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                    try? await DreamService.shared.patchTags(dreamId: viewModel.current.id, tags: tags)
                                }
                            }
                            if isEditingOrganizedText {
                                draftOrganizedText = viewModel.current.organizedText
                            }
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
        editedOrganizedText = viewModel.current.organizedText
    }

    private func startOrganizedTextEdit() {
        draftOrganizedText = viewModel.current.organizedText
        isEditingOrganizedText = true
        DispatchQueue.main.async {
            organizedTextFieldFocused = true
        }
    }

    private func cancelOrganizedTextEdit() {
        draftOrganizedText = viewModel.current.organizedText
        dismissOrganizedTextKeyboard()
        isEditingOrganizedText = false
    }

    private func saveOrganizedTextEdit() {
        let draft = draftOrganizedText
        guard viewModel.applyOrganizedTextEditLocally(draft) else { return }
        pendingOrganizedDraft = draft
        if viewModel.pendingSubstantialSave {
            showOrganizedSaveSheet = true
        } else {
            Task {
                _ = await viewModel.saveOrganizedText(draft, andReinterpret: false)
                dismissOrganizedTextKeyboard()
                isEditingOrganizedText = false
                editedOrganizedText = viewModel.current.organizedText
            }
        }
    }

    private func handleFeedbackTap(_ value: InsightViewModel.DreamFeedback) async {
        let action = await viewModel.toggleFeedback(value)
        switch action {
        case .showABitOffSheetFirstTime:
            showABitOffSheet = true
        case .showUncomfortableSheet:
            showUncomfortableSheet = true
        default:
            break
        }
    }

    private func dismissOrganizedTextKeyboard() {
        organizedTextFieldFocused = false
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

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#Preview {
    InsightView(dreamId: nil, appState: AppState())
        .preferredColorScheme(.dark)
}

