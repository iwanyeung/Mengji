import SwiftUI

struct StyleSelectionView: View {
    var dreamId: UUID?

    @ObservedObject var appState: AppState
    @State private var selectedStyleId: String?
    @State private var navigateToPayment = false

    private let styles: [WorkshopStyle] = [
        WorkshopStyle(
            id: "noir-comic",
            title: "高对比黑白 · 颗粒感四格",
            description: "像旧时代报纸上的连载漫画，用粗线条和颗粒噪点讲完一段梦。",
            accent: .primaryColor
        ),
        WorkshopStyle(
            id: "neon-surreal",
            title: "霓虹超现实 · 拼贴四格",
            description: "颜色偏离现实，人物与场景像被剪贴在同一张夜空里。",
            accent: .accentColor
        )
    ]

    var body: some View {
        ZStack {
            AppAuroraBackground(style: .workshop)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    ForEach(styles) { style in
                        StyleCard(
                            style: style,
                            isSelected: style.id == selectedStyleId
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: WorkshopMotion.selectDuration)) {
                                selectedStyleId = style.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
        }
        .navigationDestination(isPresented: $navigateToPayment) {
            MockPaymentView(
                dreamId: dreamId,
                styleId: selectedStyleId ?? styles.first?.id ?? "",
                appState: appState
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomCTA
        }
        .navigationTitle("选择风格")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .onAppear {
            if selectedStyleId == nil {
                selectedStyleId = styles.first?.id
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("为这条梦选择一种落成风格。")
                .font(AppTheme.bodyFont(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.text)

            Text("给这条梦选一个最合适的画面语言。")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
        }
    }

    private var bottomCTA: some View {
        Button {
            if selectedStyleId == nil {
                selectedStyleId = styles.first?.id
            }
            if selectedStyleId != nil {
                withAnimation(WorkshopMotion.navigationSpring) {
                    navigateToPayment = true
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text("继续 · 让这条梦落成四格")
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
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(AppTheme.background.opacity(0.92))
    }
}

private struct WorkshopStyle: Identifiable {
    enum Accent {
        case primaryColor
        case accentColor
    }

    let id: String
    let title: String
    let description: String
    let accent: Accent
}

private struct StyleCard: View {
    let style: WorkshopStyle
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(accentColor.opacity(0.9))
                .frame(height: 120)
                .overlay(
                    VStack {
                        Text("4")
                            .font(.system(size: 48, weight: .black, design: .default))
                            .foregroundColor(AppTheme.background)
                        Text("格")
                            .font(.system(size: 14, weight: .semibold, design: .default))
                            .foregroundColor(AppTheme.background)
                    }
                )

            Text(style.title)
                .font(AppTheme.titleFont(size: 15))
                .foregroundColor(AppTheme.text)

            Text(style.description)
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(
                    isSelected ? accentColor : AppTheme.surface,
                    lineWidth: isSelected ? 2 : 1
                )
                .background(AppTheme.background.opacity(0.7))
        )
        .scaleEffect(isSelected ? 1.0 : 0.995)
        .shadow(
            color: isSelected ? accentColor.opacity(0.2) : .clear,
            radius: isSelected ? 12 : 0,
            x: 0,
            y: 3
        )
        .animation(.easeInOut(duration: WorkshopMotion.selectDuration), value: isSelected)
    }

    private var accentColor: Color {
        switch style.accent {
        case .primaryColor:
            return AppTheme.primaryColor
        case .accentColor:
            return AppTheme.accent
        }
    }
}

