import SwiftUI

struct SettingsView: View {
    @ObservedObject private var sessionStore = UserSessionStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()

                List {
                    sectionAccount
                    sectionSafety
                    sectionAbout
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置与关于")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var sectionAccount: some View {
        Section("账号与登录") {
            Text("当前为游客模式，数据仅保存在本机。")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(AppTheme.muted)

            Button {
            } label: {
                Text("使用 Apple 登录（占位）")
                    .foregroundColor(AppTheme.text)
            }

            Button {
            } label: {
                Text("使用微信登录（占位）")
                    .foregroundColor(AppTheme.text)
            }
        }
    }

    private var sectionSafety: some View {
        Section("安全与心理健康提示") {
            Text("梦悸提供的梦境整理和解释，仅用于自我观察与灵感启发，不构成医学或心理诊断建议。")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)

            Text("如果你正在经历强烈的情绪波动，或出现自伤、自杀等想法，请优先联系当地专业机构或紧急热线，而不是仅依赖本应用。")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)
        }
    }

    private var sectionAbout: some View {
        Section("关于梦悸") {
            Text("梦悸是一款以梦境记录为入口、以温柔陪伴式 AI 解读为桥梁、以视觉化内容生成为核心价值的灵感创作工具。")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)
        }
    }
}

