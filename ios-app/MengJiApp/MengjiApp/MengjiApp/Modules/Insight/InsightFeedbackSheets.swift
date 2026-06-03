import SwiftUI

struct ABitOffFeedbackSheet: View {
    @Binding var optionalNote: String
    var onEditNarrative: () -> Void
    var onReinterpretInterpretation: () -> Void
    var onReinterpretTags: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("哪里不太对？")
                    .font(AppTheme.titleFont(size: 18))
                    .foregroundColor(AppTheme.text)

                VStack(spacing: 10) {
                    sheetButton("梦境整理和我想的不一样", icon: "pencil") {
                        onDismiss()
                        onEditNarrative()
                    }
                    sheetButton("整理没问题，主要是解读", icon: "text.quote") {
                        onDismiss()
                        onReinterpretInterpretation()
                    }
                    sheetButton("标签 / 意象不太准", icon: "tag") {
                        onDismiss()
                        onReinterpretTags()
                    }
                }

                TextField("可以简单说哪里不对（选填）", text: $optionalNote, axis: .vertical)
                    .lineLimit(2...4)
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundColor(AppTheme.text)
                    .padding(12)
                    .background(AppTheme.surface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(AppTheme.muted.opacity(0.4), lineWidth: 1)
                    )

                Spacer()
            }
            .padding(24)
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        onDismiss()
                    }
                    .foregroundColor(AppTheme.muted)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sheetButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.primaryColor)
                Text(title)
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.muted)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(AppTheme.surface, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct UncomfortableFeedbackSheet: View {
    var onGentlerReinterpret: () -> Void
    var onCollapseInterpretation: () -> Void
    var onEditNarrative: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("先陪你在这一下")
                    .font(AppTheme.titleFont(size: 18))
                    .foregroundColor(AppTheme.text)

                Text("梦悸不会给你下结论或做诊断。若这段文字让你紧绷，我们可以换一种更轻的说法。")
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundColor(AppTheme.muted)
                    .lineSpacing(5)

                Button {
                    onDismiss()
                    onGentlerReinterpret()
                } label: {
                    primaryLabel("换一种更轻柔的解读")
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                    onCollapseInterpretation()
                } label: {
                    secondaryLabel("先收起解读，只看整理")
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                    onEditNarrative()
                } label: {
                    secondaryLabel("去改梦境整理")
                }
                .buttonStyle(.plain)

                Text("若你正在经历强烈情绪困扰，请优先寻求专业帮助。可在设置中查看支持资源说明。")
                    .font(AppTheme.bodyFont(size: 11))
                    .foregroundColor(AppTheme.muted)
                    .lineSpacing(4)
                    .padding(.top, 8)

                Spacer()
            }
            .padding(24)
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onDismiss() }
                        .foregroundColor(AppTheme.muted)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func primaryLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.bodyFont(size: 15, weight: .semibold))
            .foregroundColor(AppTheme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.primaryColor)
    }

    private func secondaryLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.bodyFont(size: 14, weight: .semibold))
            .foregroundColor(AppTheme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(AppTheme.surface, lineWidth: 1)
            )
    }
}

struct OrganizedTextSaveSheet: View {
    var onSaveOnly: () -> Void
    var onSaveAndReinterpret: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("梦境整理已更新")
                .font(AppTheme.titleFont(size: 17))
                .foregroundColor(AppTheme.text)

            Text("解读可能尚未同步。要按当前内容更新梦析解读吗？")
                .font(AppTheme.bodyFont(size: 14))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)

            Button(action: onSaveAndReinterpret) {
                Text("保存并更新梦析解读")
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.primaryColor)
            }
            .buttonStyle(.plain)

            Button(action: onSaveOnly) {
                Text("仅保存整理")
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundColor(AppTheme.muted)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button("取消", action: onCancel)
                .font(AppTheme.bodyFont(size: 14))
                .foregroundColor(AppTheme.muted)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .presentationDetents([.height(280)])
    }
}
