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

enum AppToastPlacement {
    case top
    case bottom
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
    var placement: AppToastPlacement
    var edgePadding: CGFloat
    var autoDismissSeconds: TimeInterval

    func body(content: Content) -> some View {
        content
            .overlay(alignment: placement == .top ? .top : .bottom) {
                if let message {
                    AppToast(message: message, style: style)
                        .padding(.horizontal, 24)
                        .padding(placement == .top ? .top : .bottom, edgePadding)
                        .transition(
                            .move(edge: placement == .top ? .top : .bottom)
                                .combined(with: .opacity)
                        )
                        .task(id: message) {
                            let expected = message
                            try? await Task.sleep(for: .seconds(autoDismissSeconds))
                            if self.message == expected {
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
        placement: AppToastPlacement = .top,
        edgePadding: CGFloat = 12,
        autoDismissSeconds: TimeInterval = 2.5
    ) -> some View {
        modifier(
            AppToastOverlayModifier(
                message: message,
                style: style,
                placement: placement,
                edgePadding: edgePadding,
                autoDismissSeconds: autoDismissSeconds
            )
        )
    }

    /// 兼容梦析页等仍使用底部 Toast 的调用方。
    func appToastOverlay(
        message: Binding<String?>,
        style: AppToastStyle = .info,
        bottomPadding: CGFloat
    ) -> some View {
        appToastOverlay(
            message: message,
            style: style,
            placement: .bottom,
            edgePadding: bottomPadding
        )
    }
}
