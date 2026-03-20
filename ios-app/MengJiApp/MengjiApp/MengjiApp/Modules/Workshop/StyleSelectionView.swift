import SwiftUI

struct StyleSelectionView: View {
    var dreamId: UUID?

    @EnvironmentObject private var dreamStore: DreamStore
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
            AppTheme.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                header

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(styles) { style in
                            StyleCard(
                                style: style,
                                isSelected: style.id == selectedStyleId
                            )
                            .onTapGesture {
                                selectedStyleId = style.id
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }

                Button {
                    if selectedStyleId == nil {
                        selectedStyleId = styles.first?.id
                    }
                    if selectedStyleId != nil {
                        navigateToPayment = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("继续 · 确认并显化")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(AppTheme.background)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(AppTheme.primaryColor)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            NavigationLink(
                destination: MockPaymentView(
                    dreamId: dreamId,
                    styleId: selectedStyleId ?? styles.first?.id ?? ""
                ),
                isActive: $navigateToPayment
            ) {
                EmptyView()
            }
            .hidden()
        }
        .navigationTitle("选择风格")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedStyleId == nil {
                selectedStyleId = styles.first?.id
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("给这条梦选一个最合适的画面语言。")
                .font(.system(size: 16, weight: .regular, design: .default))
                .foregroundColor(AppTheme.text)
            Text("MVP 阶段先提供两种典型风格，后续可以慢慢扩展更多模板。")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(AppTheme.muted)
        }
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
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.text)

            Text(style.description)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(
                    isSelected ? accentColor : AppTheme.surface,
                    lineWidth: isSelected ? 2 : 1
                )
                .background(AppTheme.background.opacity(0.7))
        )
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

