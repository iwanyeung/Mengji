import AuthenticationServices
import SwiftUI

// 使用系统「通过 Apple 登录」按钮前，请在 Xcode → Signing & Capabilities 为目标添加「Sign in with Apple」，
// 并在 Apple Developer 中为该 Bundle ID 启用该能力；否则真机授权可能失败。调试可用下方「模拟 Apple 登录」。

struct SettingsView: View {
    @ObservedObject private var sessionStore = UserSessionStore.shared
    @State private var showSignOutConfirm = false
    @AppStorage(PersonalCenterBiometric.userDefaultsKey) private var biometricGateEnabled = false
    @AppStorage(StarfieldSettings.appStorageKey) private var starfieldModeRaw = StarfieldBackgroundMode.full.rawValue
    @State private var showBiometricUnavailableAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()

                List {
                    sectionAccount
                    sectionInvite
                    sectionPersonalCenterSecurity
                    sectionProfile
                    sectionStarfield
                    sectionSafety
                    sectionAbout
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("个人中心")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("确定退出登录？", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    sessionStore.signOut()
                }
                Button("取消", role: .cancel) {}
            }
            .alert("无法使用生物识别", isPresented: $showBiometricUnavailableAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text("请在本机「设置」中开启\(PersonalCenterBiometric.biometryShortLabel())，或稍后再试。")
            }
        }
    }

    private var sectionPersonalCenterSecurity: some View {
        Section {
            Toggle(isOn: $biometricGateEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("进入个人中心时验证")
                        .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.text)
                    Text("使用 \(PersonalCenterBiometric.biometryShortLabel())")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundColor(AppTheme.muted)
                }
            }
            .tint(AppTheme.primaryColor)
            .onChange(of: biometricGateEnabled) { _, new in
                guard new else { return }
                Task { @MainActor in
                    if !PersonalCenterBiometric.canEvaluateBiometrics() {
                        biometricGateEnabled = false
                        showBiometricUnavailableAlert = true
                        return
                    }
                    let ok = await PersonalCenterBiometric.authenticateForEntry()
                    if !ok {
                        biometricGateEnabled = false
                    }
                }
            }
        } header: {
            Text("安全与隐私")
        } footer: {
            Text("开启后，从录梦、梦析、梦作间、潜意识星图等入口进入个人中心前，需先通过\(PersonalCenterBiometric.biometryShortLabel())验证；仅作用于本机，可随时关闭。")
                .font(AppTheme.bodyFont(size: 11))
        }
    }

    private var sectionAccount: some View {
        Section("账号与登录") {
            if sessionStore.session.isLoggedIn {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已使用 Apple 账号登录")
                        .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.text)
                    Text("显示名：\(displayNameLine)")
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundColor(AppTheme.muted)
                    if let biz = sessionStore.session.businessNumericId {
                        Text("个人 ID：\(biz)")
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundColor(AppTheme.muted)
                    }
                }
                .padding(.vertical, 4)

                Button(role: .destructive) {
                    showSignOutConfirm = true
                } label: {
                    Text("退出登录")
                }
            } else {
                Text("当前为游客模式。梦境会同步到云端，但重装后需使用 Apple 登录才能恢复历史记录。")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundColor(AppTheme.muted)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                        sessionStore.applyAppleAuthorization(
                            appleUserId: credential.user,
                            fullName: credential.fullName,
                            email: credential.email
                        )
                    case .failure:
                        break
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 44)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

#if DEBUG
                Button {
                    sessionStore.simulateAppleSignInForDevelopment()
                } label: {
                    Text("模拟 Apple 登录（仅调试）")
                        .font(AppTheme.bodyFont(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.primaryColor)
                }
#endif
            }
        }
    }

    private var sectionInvite: some View {
        Section("邀请体验") {
            NavigationLink {
                InviteRedeemView()
            } label: {
                Text("输入邀请码")
                    .font(AppTheme.bodyFont(size: 15))
                    .foregroundColor(AppTheme.text)
            }
        }
    }

    private var displayNameLine: String {
        let n = sessionStore.session.appleDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n, !n.isEmpty { return n }
        return "（首次授权时可填写姓名）"
    }

    private var sectionProfile: some View {
        Section {
            if sessionStore.session.isLoggedIn {
                Text("以下信息用于调整解读语气与意象风格，不构成任何医学或心理判断。")
                    .font(AppTheme.bodyFont(size: 11))
                    .foregroundColor(AppTheme.muted)
                    .listRowBackground(Color.clear)

                Picker(selection: genderSelection) {
                    Text("未选择").tag(Optional<GenderIdentity>.none)
                    ForEach(GenderIdentity.allCases, id: \.self) { g in
                        Text(g.displayTitle).tag(Optional(g))
                    }
                } label: {
                    Text("性别认同")
                }
                .foregroundColor(AppTheme.text)

                Picker(selection: ageSelection) {
                    Text("未选择").tag(Optional<AgeRange>.none)
                    ForEach(AgeRange.allCases, id: \.self) { r in
                        Text(r.displayTitle).tag(Optional(r))
                    }
                } label: {
                    Text("年龄段")
                }
                .foregroundColor(AppTheme.text)

                Picker(selection: colorSelection) {
                    Text("未选择").tag(Optional<ColorPreference>.none)
                    ForEach(ColorPreference.allCases, id: \.self) { c in
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(c.swatchColor)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .strokeBorder(
                                            c == .inkBlack ? AppTheme.muted.opacity(0.8) : AppTheme.muted.opacity(0.35),
                                            lineWidth: 1
                                        )
                                )
                            Text("\(c.displayTitle)")
                        }
                        .tag(Optional(c))
                    }
                } label: {
                    Text("色彩氛围偏好")
                }
                .foregroundColor(AppTheme.text)
            } else {
                Text("登录后可完善性别认同、年龄段与色彩氛围偏好，用于辅助梦悸更贴合你的表达习惯。")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundColor(AppTheme.muted)
            }
        } header: {
            Text("个人资料")
        }
    }

    private var genderSelection: Binding<GenderIdentity?> {
        Binding(
            get: { sessionStore.session.profile.gender },
            set: { newValue in
                var p = sessionStore.session.profile
                p.gender = newValue
                sessionStore.updateProfile(p)
            }
        )
    }

    private var ageSelection: Binding<AgeRange?> {
        Binding(
            get: { sessionStore.session.profile.ageRange },
            set: { newValue in
                var p = sessionStore.session.profile
                p.ageRange = newValue
                sessionStore.updateProfile(p)
            }
        )
    }

    private var colorSelection: Binding<ColorPreference?> {
        Binding(
            get: { sessionStore.session.profile.colorPreference },
            set: { newValue in
                var p = sessionStore.session.profile
                p.colorPreference = newValue
                sessionStore.updateProfile(p)
            }
        )
    }

    private var sectionStarfield: some View {
        Section {
            Picker(selection: $starfieldModeRaw) {
                ForEach(StarfieldBackgroundMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            } label: {
                Text("动态星野")
            }
            .foregroundColor(AppTheme.text)
        } header: {
            Text("潜意识星图")
        } footer: {
            Text(StarfieldBackgroundMode(rawValue: starfieldModeRaw)?.footnote ?? "")
                .font(AppTheme.bodyFont(size: 11))
        }
    }

    private var sectionSafety: some View {
        Section("安全与心理健康提示") {
            Text("梦悸提供的梦境整理和解释，仅用于自我观察与灵感启发，不构成医学或心理诊断建议。")
                .font(AppTheme.bodyFont(size: 12))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)

            Text("如果你正在经历强烈的情绪波动，或出现自伤、自杀等想法，请优先联系当地专业机构或紧急热线，而不是仅依赖本应用。")
                .font(AppTheme.bodyFont(size: 12))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)
        }
    }

    private var sectionAbout: some View {
        Section("关于梦悸") {
            Text("梦悸是一款以梦境记录为入口、以温柔陪伴式 AI 解读为桥梁、以视觉化内容生成为核心价值的灵感创作工具。")
                .font(AppTheme.bodyFont(size: 12))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)
        }
    }
}
