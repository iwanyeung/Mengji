import SwiftUI

struct StoryboardPreviewView: View {
    var dreamId: UUID?
    var styleId: String

    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var preview: ComicStoryboardPreview?
    @State private var editableCaptions: [Int: String] = [:]
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var navigateToCheckout = false

    var body: some View {
        ZStack {
            AppAuroraBackground(style: .workshop)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if isLoading {
                        ProgressView("正在构思分镜…")
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundColor(AppTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 24)
                    } else if let preview {
                        if let readiness = preview.readiness {
                            ComicReadinessBanner(readiness: readiness)
                        }

                        modeHint(for: preview)

                        ForEach(preview.panels) { panel in
                            panelCard(panel)
                        }

                        if preview.inferredPanelCount > 0 {
                            Text("有 \(preview.inferredPanelCount) 格为 AI 补充过渡，确认后将按此构思落成画面。")
                                .font(AppTheme.bodyFont(size: 12))
                                .foregroundColor(AppTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundColor(AppTheme.accent)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
        }
        .navigationDestination(isPresented: $navigateToCheckout) {
            CheckoutView(
                dreamId: dreamId,
                styleId: styleId,
                appState: appState
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomCTA
        }
        .navigationTitle("确认分镜")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .task {
            await loadStoryboard()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("落成前，先看看四格故事线。")
                .font(AppTheme.bodyFont(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("你可以修改每格描述；确认后再进入落成流程。记录越具体，画面越贴近你梦里的样子。")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modeHint(for preview: ComicStoryboardPreview) -> some View {
        let text = preview.storyboardMode == .imagery
            ? "本次将采用「意象四格」：围绕核心意象用不同镜头表现，减少编造剧情。"
            : "本次将采用「叙事四格」：在你已有情节基础上串联起承转合。"
        return Text(text)
            .font(AppTheme.bodyFont(size: 12))
            .foregroundColor(AppTheme.text.opacity(0.88))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(AppTheme.surface, lineWidth: 1)
            )
    }

    private func panelCard(_ panel: ComicStoryboardPanel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("第 \(panel.panelIndex) 格")
                    .font(AppTheme.capsFont(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.muted)

                Spacer()

                Text(panel.source.label)
                    .font(AppTheme.capsFont(size: 10, weight: .semibold))
                    .foregroundColor(sourceColor(panel.source))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(sourceColor(panel.source).opacity(0.5), lineWidth: 1)
                    )
            }

            TextField("这一格的画面描述", text: captionBinding(for: panel), axis: .vertical)
                .font(AppTheme.bodyFont(size: 14))
                .foregroundColor(AppTheme.text)
                .lineLimit(2...4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(AppTheme.surface, lineWidth: 1)
                .background(AppTheme.background.opacity(0.7))
        )
    }

    private func captionBinding(for panel: ComicStoryboardPanel) -> Binding<String> {
        Binding(
            get: { editableCaptions[panel.panelIndex] ?? panel.caption },
            set: { editableCaptions[panel.panelIndex] = $0 }
        )
    }

    private func sourceColor(_ source: ComicPanelSource) -> Color {
        switch source {
        case .verbatim: return AppTheme.primaryColor
        case .atmosphere: return AppTheme.muted
        case .inferred: return AppTheme.accent.opacity(0.9)
        }
    }

    private var bottomCTA: some View {
        VStack(spacing: 10) {
            Button {
                Task { await confirmAndContinue() }
            } label: {
                HStack(spacing: 10) {
                    Text(isSaving ? "保存中…" : "确认分镜，继续落成")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(AppTheme.bodyFont(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.background)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(AppTheme.primaryColor)
            }
            .buttonStyle(WorkshopPrimaryCTAButtonStyle())
            .disabled(isLoading || isSaving || preview == nil)

            if preview?.readiness?.isSparse == true {
                Button {
                    appState.selectedTab = .recording
                    dismiss()
                } label: {
                    Text("先回去补录一点画面")
                        .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.muted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(AppTheme.background.opacity(0.92))
    }

    private func loadStoryboard() async {
        guard let dreamId else {
            isLoading = false
            errorMessage = "找不到梦境记录"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await AuthService.shared.ensureAnonymousSession()
            let loaded = try await DreamService.shared.fetchComicStoryboard(dreamId: dreamId, styleKey: styleId)
            preview = loaded
            editableCaptions = Dictionary(uniqueKeysWithValues: loaded.panels.map { ($0.panelIndex, $0.caption) })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmAndContinue() async {
        guard let dreamId, preview != nil else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let edits = editableCaptions
                .map { ComicStoryboardCaptionUpdate(panelIndex: $0.key, caption: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.caption.isEmpty }

            if !edits.isEmpty {
                _ = try await DreamService.shared.updateComicStoryboard(
                    dreamId: dreamId,
                    styleKey: styleId,
                    panels: edits
                )
            }

            withAnimation(WorkshopMotion.navigationSpring) {
                navigateToCheckout = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
