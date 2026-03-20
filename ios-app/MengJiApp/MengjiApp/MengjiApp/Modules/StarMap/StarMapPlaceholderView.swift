//
//  StarMapPlaceholderView.swift
//  MengjiApp
//

import SwiftUI

struct StarMapPlaceholderView: View {
    @ObservedObject private var store = DreamStore.shared
    @State private var offset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()

                starField
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = value.translation
                    }
                    .onEnded { _ in }
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("重置视图") {
                        offset = .zero
                    }
                    .foregroundColor(AppTheme.muted)
                }
            }
            .navigationTitle("潜意识星图")
        }
    }

    private var starField: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let dreams = store.visibleDreams()

            ZStack {
                ForEach(Array(dreams.enumerated()), id: \.element.id) { index, dream in
                    let position = positionFor(index: index, total: dreams.count, in: size)

                    Circle()
                        .fill(AppTheme.surface)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    dream.hasComic ? AppTheme.primaryColor : AppTheme.surface,
                                    lineWidth: dream.hasComic ? 2 : 1
                                )
                        )
                        .position(
                            x: position.x + offset.width,
                            y: position.y + offset.height
                        )
                }
            }
        }
    }

    private func positionFor(index: Int, total: Int, in size: CGSize) -> CGPoint {
        guard total > 0 else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.3
        let angle = 2 * Double.pi * Double(index) / Double(max(total, 1))

        let dx = CGFloat(cos(angle)) * radius
        let dy = CGFloat(sin(angle)) * radius

        return CGPoint(x: center.x + dx, y: center.y + dy)
    }
}
