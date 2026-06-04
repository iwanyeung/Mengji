import SwiftUI
import UIKit

/// 前台推送横幅：系统 banner 在 Xcode 调试包上常显示占位图标，改用带 BrandLogo 的顶层横幅。
struct MengjiPushBannerView: View {
    let title: String
    let bodyText: String
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image("BrandLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.text)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("现在")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.muted)
                }

                Text(bodyText)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.text.opacity(0.92))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .onTapGesture(perform: onDismiss)
    }
}

@MainActor
enum MengjiPushBannerPresenter {
    private static var bannerWindow: UIWindow?

    static func show(title: String, body: String) {
        dismiss()

        guard
            !title.isEmpty || !body.isEmpty,
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
        else {
            return
        }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear

        let host = UIHostingController(
            rootView: MengjiPushBannerView(title: title, bodyText: body, onDismiss: dismiss)
        )
        host.view.backgroundColor = .clear
        host.view.frame = scene.screen.bounds

        window.rootViewController = host
        window.isHidden = false
        bannerWindow = window

        Task {
            try? await Task.sleep(for: .seconds(4))
            dismiss()
        }
    }

    static func dismiss() {
        bannerWindow?.isHidden = true
        bannerWindow = nil
    }
}
