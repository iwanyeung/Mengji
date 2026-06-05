import SwiftUI

struct ComicReadinessBanner: View {
    let readiness: ComicReadiness

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                readinessBadge
                Text(readinessTitle)
                    .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.text)
            }

            Text(readiness.userHint)
                .font(AppTheme.bodyFont(size: 12))
                .foregroundColor(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(borderColor, lineWidth: 1)
                .background(AppTheme.background.opacity(0.65))
        )
    }

    private var readinessTitle: String {
        switch readiness.level {
        case .rich: return "很适合落成四格"
        case .moderate: return "可以落成，偏意象化"
        case .sparse: return "记录偏少，建议补录"
        }
    }

    private var readinessBadge: some View {
        Text(levelLabel)
            .font(AppTheme.capsFont(size: 10, weight: .semibold))
            .foregroundColor(badgeForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeBackground)
    }

    private var levelLabel: String {
        switch readiness.level {
        case .rich: return "画面感足"
        case .moderate: return "偏短"
        case .sparse: return "较少"
        }
    }

    private var borderColor: Color {
        switch readiness.level {
        case .rich: return AppTheme.primaryColor.opacity(0.45)
        case .moderate: return AppTheme.surface
        case .sparse: return AppTheme.accent.opacity(0.35)
        }
    }

    private var badgeForeground: Color {
        switch readiness.level {
        case .rich: return AppTheme.background
        case .moderate: return AppTheme.text
        case .sparse: return AppTheme.text
        }
    }

    private var badgeBackground: Color {
        switch readiness.level {
        case .rich: return AppTheme.primaryColor
        case .moderate: return AppTheme.surface
        case .sparse: return AppTheme.surface.opacity(0.9)
        }
    }
}
