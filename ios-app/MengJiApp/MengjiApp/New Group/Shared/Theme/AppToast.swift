import SwiftUI

enum AppToastStyle {
    case info
    case success
    case error

    var borderColor: Color {
        switch self {
        case .info:
            return AppTheme.muted.opacity(0.45)
        case .success:
            return AppTheme.primaryColor.opacity(0.55)
        case .error:
            return AppTheme.accent.opacity(0.55)
        }
    }

    var systemImage: String? {
        switch self {
        case .info:
            return nil
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }
}

struct AppToast: View {
    let message: String
    var style: AppToastStyle = .info

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage = style.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
            }

            Text(message)
                .font(AppTheme.bodyFont(size: 14))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(AppTheme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(style.borderColor, lineWidth: 1)
        )
        .shadow(color: AppTheme.background.opacity(0.5), radius: 16, x: 0, y: 6)
    }
}

private struct AppToastOverlayModifier: ViewModifier {
    @Binding var message: String?
    var style: AppToastStyle
    var bottomPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    AppToast(message: message, style: style)
                        .padding(.horizontal, 24)
                        .padding(.bottom, bottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                self.message = nil
                            }
                        }
                }
            }
            .animation(.easeOut(duration: 0.25), value: message)
    }
}

extension View {
    func appToastOverlay(
        message: Binding<String?>,
        style: AppToastStyle = .info,
        bottomPadding: CGFloat = 132
    ) -> some View {
        modifier(
            AppToastOverlayModifier(
                message: message,
                style: style,
                bottomPadding: bottomPadding
            )
        )
    }
}
