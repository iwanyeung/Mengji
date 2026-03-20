import SwiftUI

struct InsightView: View {
    var dreamId: UUID?
    @StateObject private var viewModel: InsightViewModel
    @ObservedObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showManageSheet = false
    @State private var editedTitle: String = ""
    @State private var editedNote: String = ""
    @State private var editedTagsText: String = ""
    @State private var showDeleteConfirmation = false

    init(dreamId: UUID? = nil, appState: AppState) {
        self.dreamId = dreamId
        _appState = ObservedObject(wrappedValue: appState)
        _viewModel = StateObject(wrappedValue: InsightViewModel(dreamId: dreamId))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    headerSection
                    organizedTextSection
                    tagsSection
                    interpretationSection
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
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.current.dateString)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .textCase(.uppercase)
                        .kerning(1.6)
                        .foregroundColor(AppTheme.muted)

                    Text(viewModel.current.timeString)
                        .font(.system(size: 12, weight: .regular, design: .default))
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
                .font(.system(size: 26, weight: .bold, design: .serif))
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
                .font(.system(size: 13, weight: .regular, design: .default))
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
                .font(.system(size: 16, weight: .regular, design: .default))
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
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundColor(AppTheme.text.opacity(0.9))
                .lineSpacing(6)
        }
    }

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("温柔提醒")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .textCase(.uppercase)
                .kerning(1.4)
                .foregroundColor(AppTheme.muted)

            Text("梦悸提供的是一种温柔的心理陪伴视角，而不是医学或心理治疗建议。如你正在经历强烈的情绪波动或长期的身心困扰，请优先寻求专业帮助。")
                .font(.system(size: 11, weight: .regular, design: .default))
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
                    Text("显化为四格漫画")
                    Spacer()
                    Image(systemName: "sparkles")
                }
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.background)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .background(AppTheme.primaryColor)
                .cornerRadius(0)
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
                .font(.system(size: 12, weight: .medium, design: .default))
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
            LinearGradient(
                gradient: Gradient(colors: [AppTheme.background.opacity(0.0), AppTheme.background.opacity(0.95)]),
                startPoint: .top,
                endPoint: .bottom
            )
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
                            Text(viewModel.current.tags.joined(separator: " · "))
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.muted)
                        }

                        Section {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Text("删除或归档这条梦")
                            }
                        }
                    }
                    .confirmationDialog(
                        "这条梦要如何处理？",
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("删除这条梦", role: .destructive) {
                            viewModel.deleteCurrent()
                            dismiss()
                        }
                        Button("仅归档，不在列表展示") {
                            viewModel.archiveCurrent()
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
                .font(.system(size: 11, weight: .semibold, design: .default))
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
        .font(.system(size: 11, weight: .regular, design: .default))
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
}

private struct FlexibleTagWrap: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            var currentRowWidth: CGFloat = 0
            let maxWidth = UIScreen.main.bounds.width - 48 // 24pt padding * 2

            ForEach(rows(maxWidth: maxWidth), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .regular, design: .default))
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

