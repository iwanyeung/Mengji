import SwiftUI

struct DreamSelectionView: View {
    @EnvironmentObject private var dreamStore: DreamStore

    @Binding var selectedId: UUID?
    var onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()

                List {
                    ForEach(dreamStore.visibleDreams()) { dream in
                        Button {
                            selectedId = dream.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(dream.title)
                                        .font(AppTheme.titleFont(size: 15))
                                        .foregroundColor(AppTheme.text)
                                        .multilineTextAlignment(.leading)

                                    Text(shortPreview(from: dream.organizedText))
                                        .font(AppTheme.bodyFont(size: 12))
                                        .foregroundColor(AppTheme.muted)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if dream.id == selectedId {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(AppTheme.primaryColor)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Button {
                            onConfirm()
                        } label: {
                            HStack(spacing: 10) {
                                Text("确定")
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                            .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.background)
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .background(AppTheme.primaryColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedId == nil)
                        .opacity(selectedId == nil ? 0.4 : 1)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .background(AppTheme.background)
                    }
                }
            }
            .navigationTitle("选择一条梦")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        onConfirm()
                    }
                    .foregroundColor(AppTheme.muted)
                }
            }
        }
    }

    private func shortPreview(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 30
        if trimmed.count <= limit { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<idx]) + "…"
    }
}

