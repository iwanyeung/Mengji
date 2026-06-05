//
//  InsightListView.swift
//  MengjiApp
//

import SwiftUI

struct InsightListView: View {
    var onSelectDream: (UUID) -> Void

    @ObservedObject private var store = DreamStore.shared
    @Environment(\.openPersonalCenter) private var openPersonalCenter

    var body: some View {
        ZStack {
            AppAuroraBackground(
                style: .insight,
                prioritizeTextReadability: true
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    listContent
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("梦析")
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已整理的梦")
                .font(AppTheme.capsFont(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(1.4)
                .foregroundColor(AppTheme.muted)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
    }

    private var listContent: some View {
        let dreams = store.visibleDreams()

        return VStack(alignment: .leading, spacing: 12) {
            if dreams.isEmpty {
                emptyState
            } else {
                ForEach(dreams) { dream in
                    Button {
                        onSelectDream(dream.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(dream.title)
                                .font(AppTheme.titleFont(size: 16))
                                .kerning(-0.2)
                                .foregroundColor(AppTheme.text)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 8) {
                                Text(dateString(for: dream.createdAt))
                                    .font(AppTheme.bodyFont(size: 12))
                                    .foregroundColor(AppTheme.muted)

                                if dream.hasComic {
                                    Text("已落成")
                                        .font(AppTheme.capsFont(size: 11, weight: .semibold))
                                        .foregroundColor(AppTheme.background)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.primaryColor)

                                    if dream.comicArtifacts.count > 1 {
                                        Text("共 \(dream.comicArtifacts.count) 版")
                                            .font(AppTheme.bodyFont(size: 11))
                                            .foregroundColor(AppTheme.muted)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.muted)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(AppTheme.surface, lineWidth: 1)
                            .background(AppTheme.background.opacity(0.6))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                }
            }
        }
        .padding(.top, 16)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有已整理的梦")
                .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.text)
            Text("从「录梦」开始说说最近的一场梦，它会出现在这里。")
                .font(AppTheme.bodyFont(size: 12))
                .foregroundColor(AppTheme.muted)
        }
        .padding(.horizontal, 24)
    }

    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        InsightListView(onSelectDream: { _ in })
    }
}
