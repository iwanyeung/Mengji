import SwiftUI

struct ComicGenerationFailurePayload: Equatable {
    let failureCode: String
    let userMessage: String
    let quotaRefunded: Bool
    let successfulPanelCount: Int
    let dreamId: UUID
    let styleId: String
}

struct ComicGenerationFailureView: View {
    let payload: ComicGenerationFailurePayload
    var onRetry: () -> Void
    var onChangeStyle: () -> Void
    var onEditDream: () -> Void
    var onStayInStarMap: () -> Void

    private var title: String {
        switch payload.failureCode {
        case "moderation_blocked":
            return "这次还未能落成画面"
        case "service_unavailable":
            return "生成服务暂时不可用"
        case "partial_success":
            return "四格还未完整落成"
        default:
            return "这次还未能落成四格"
        }
    }

    private var quotaNote: String? {
        if payload.quotaRefunded {
            return "已使用的 1 次体验额度已退还。"
        }
        if payload.failureCode == "partial_success" {
            return "本次额度已使用，完整四格需重新生成。"
        }
        return nil
    }

    var body: some View {
        ZStack {
            AppAuroraBackground(style: .workshop)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: iconName)
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(AppTheme.primaryColor)
                        .padding(.top, 8)

                    Text(title)
                        .font(AppTheme.titleFont(size: 22))
                        .foregroundColor(AppTheme.text)

                    Text(payload.userMessage)
                        .font(AppTheme.bodyFont(size: 15))
                        .foregroundColor(AppTheme.text.opacity(0.92))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    if let quotaNote {
                        Text(quotaNote)
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundColor(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if payload.failureCode == "moderation_blocked" {
                        suggestionBlock
                    }

                    VStack(spacing: 10) {
                        if payload.failureCode != "partial_success" {
                            Button(action: onRetry) {
                                primaryCTA("调整后再试", icon: "arrow.clockwise")
                            }
                            .buttonStyle(WorkshopPrimaryCTAButtonStyle())
                        }

                        if payload.failureCode == "moderation_blocked" || payload.failureCode == "partial_success" {
                            if payload.failureCode == "partial_success" {
                                Button(action: onChangeStyle) {
                                    primaryCTA("换一种画面风格", icon: "paintbrush")
                                }
                                .buttonStyle(WorkshopPrimaryCTAButtonStyle())
                            } else {
                                Button(action: onChangeStyle) {
                                    secondaryCTA("换一种画面风格", icon: "paintbrush")
                                }
                                .buttonStyle(WorkshopSecondaryButtonStyle())
                            }
                        }

                        if payload.failureCode == "moderation_blocked" {
                            Button(action: onEditDream) {
                                secondaryCTA("回到梦析微调", icon: "text.book.closed")
                            }
                            .buttonStyle(WorkshopSecondaryButtonStyle())
                        }

                        Button(action: onStayInStarMap) {
                            Text("先留在潜意识星图")
                                .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
        }
    }

    private var iconName: String {
        switch payload.failureCode {
        case "moderation_blocked":
            return "sparkles.rectangle.stack"
        case "service_unavailable":
            return "wifi.exclamationmark"
        case "partial_success":
            return "square.grid.2x2"
        default:
            return "moon.stars"
        }
    }

    private var suggestionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("我们可以这样再试一次")
                .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.text)

            Text("换风格、微调整理正文，或稍后再试——都不必改变你记录梦的本意。")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(AppTheme.surface, lineWidth: 1)
                .background(AppTheme.background.opacity(0.6))
        )
    }

    private func primaryCTA(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
            Image(systemName: icon)
        }
        .font(AppTheme.bodyFont(size: 16, weight: .semibold))
        .foregroundColor(AppTheme.background)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(AppTheme.primaryColor)
    }

    private func secondaryCTA(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
            Image(systemName: icon)
        }
        .font(AppTheme.bodyFont(size: 16, weight: .semibold))
        .foregroundColor(AppTheme.text)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(AppTheme.surface, lineWidth: 1)
                .background(AppTheme.background.opacity(0.8))
        )
    }
}
