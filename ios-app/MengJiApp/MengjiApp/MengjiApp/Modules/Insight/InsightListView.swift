//
//  InsightListView.swift
//  MengjiApp
//

import SwiftUI

struct InsightListView: View {
    var onSelectDream: (UUID) -> Void

    @ObservedObject private var store = DreamStore.shared

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已整理的梦")
                .font(.system(size: 11, weight: .semibold, design: .default))
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
                                .font(.system(size: 16, weight: .semibold, design: .default))
                                .foregroundColor(AppTheme.text)
                                .multilineTextAlignment(.leading)
                            Text(dateString(for: dream.createdAt))
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundColor(AppTheme.muted)
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
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.text)
            Text("从「录梦」开始说说最近的一场梦，它会出现在这里。")
                .font(.system(size: 12, weight: .regular, design: .default))
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
