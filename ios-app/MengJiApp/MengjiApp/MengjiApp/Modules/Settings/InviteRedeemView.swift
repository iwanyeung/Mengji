import SwiftUI

struct InviteRedeemView: View {
    @ObservedObject private var sessionStore = UserSessionStore.shared
    @State private var code = ""
    @State private var message: String?
    @State private var isError = false
    @State private var isSubmitting = false
    @State private var entitlements: Entitlements?

    var body: some View {
        Form {
            Section {
                if sessionStore.session.isLoggedIn {
                    Text("已登录 Apple 账号，可兑换邀请码。")
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundColor(AppTheme.muted)
                } else {
                    Text("兑换前请先使用 Apple 登录。")
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundColor(AppTheme.accent)
                }

                TextField("MENGJI-XXXX-XXXX", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(AppTheme.bodyFont(size: 15))

                Button {
                    Task { await redeem() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("兑换")
                    }
                }
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !sessionStore.session.isLoggedIn || isSubmitting)

                if let entitlements, entitlements.hasRedeemedInvite {
                    Text("体验额度：剩余 \(entitlements.freeComicsRemaining)/\(entitlements.freeComicsTotal) 次")
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundColor(AppTheme.primaryColor)
                }

                if let message {
                    Text(message)
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundColor(isError ? AppTheme.accent : AppTheme.muted)
                }
            } header: {
                Text("邀请体验")
            } footer: {
                Text("输入邀请码后可免费生成 10 张四格漫画；第 11 张起按 App Store 价格计费。")
                    .font(AppTheme.bodyFont(size: 11))
            }
        }
        .navigationTitle("邀请体验")
        .task { await loadEntitlements() }
    }

    private func loadEntitlements() async {
        do {
            try await AuthService.shared.ensureAnonymousSession()
            entitlements = try await EntitlementService.shared.fetch()
        } catch {
            entitlements = nil
        }
    }

    private func redeem() async {
        isSubmitting = true
        isError = false
        defer { isSubmitting = false }
        do {
            try await AuthService.shared.ensureAnonymousSession()
            let msg = try await EntitlementService.shared.redeem(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            message = msg
            code = ""
            await loadEntitlements()
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }
}
