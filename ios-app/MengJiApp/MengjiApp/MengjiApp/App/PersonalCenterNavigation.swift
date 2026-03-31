import SwiftUI

private struct OpenPersonalCenterKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openPersonalCenter: () -> Void {
        get { self[OpenPersonalCenterKey.self] }
        set { self[OpenPersonalCenterKey.self] = newValue }
    }
}

/// 个人中心入口：各 Tab 均使用导航栏右侧紧凑图标（无障碍标签仍为「个人中心」）。
struct ProfileNavButton: View {
    enum Style {
        case compact
        case prominent
    }

    var style: Style = .compact
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch style {
            case .compact:
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(AppTheme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            case .prominent:
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundColor(AppTheme.text)
                    Text("个人中心")
                        .font(AppTheme.capsFont(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.muted)
                }
                .padding(.vertical, 4)
                .padding(.leading, 8)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("个人中心")
    }
}
