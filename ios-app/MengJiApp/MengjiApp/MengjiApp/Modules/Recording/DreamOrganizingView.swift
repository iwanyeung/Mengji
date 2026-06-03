import SwiftUI

/// 录梦「完成并整理」全屏等待（与 ComicGeneratingView 同系视觉语言）
struct DreamOrganizingView: View {
    let segmentCount: Int
    let uploadedSegmentIndex: Int
    let phase: DreamOrganizingPhase
    let statusMessage: String
    let showsSuccess: Bool
    let errorMessage: String?
    let onRetry: () -> Void
    let onCancel: () -> Void

    private var stepProgress: Double {
        if showsSuccess { return 1 }
        let total = Double(DreamOrganizingPhase.analyzing.rawValue + 1)
        return min(1, Double(phase.rawValue + 1) / total)
    }

    var body: some View {
        ZStack {
            AppAuroraBackground(
                style: .insight,
                prioritizeTextReadability: true
            )

            VStack(alignment: .leading, spacing: 24) {
                if showsSuccess {
                    successContent
                } else if let errorMessage {
                    errorContent(message: errorMessage)
                } else {
                    organizingContent
                }

                Spacer()
            }
            .padding(24)
            .padding(.top, 32)
        }
        .interactiveDismissDisabled(errorMessage == nil && !showsSuccess)
    }

    private var organizingContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("梦悸正在整理这条梦")
                .font(AppTheme.titleFont(size: 22))
                .foregroundColor(AppTheme.text)

            Text("共 \(segmentCount) 段口述")
                .font(AppTheme.bodyFont(size: 15))
                .foregroundColor(AppTheme.muted)

            Text(statusMessage)
                .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.25), value: statusMessage)

            progressBar

            if phase == .uploading && segmentCount > 0 {
                Text("第 \(min(uploadedSegmentIndex, segmentCount))/\(segmentCount) 段已保存")
                    .font(AppTheme.capsFont(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.primaryColor)
            }

            stepIndicators

            Text("请保持应用在前台，通常需要约 30 秒～2 分钟")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)
                .padding(.top, 4)
        }
    }

    private var successContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.primaryColor)

            Text("整理完成")
                .font(AppTheme.titleFont(size: 22))
                .foregroundColor(AppTheme.text)

            Text("即将进入梦析，陪你看这条梦。")
                .font(AppTheme.bodyFont(size: 15))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)
        }
    }

    private func errorContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("整理未完成")
                .font(AppTheme.titleFont(size: 22))
                .foregroundColor(AppTheme.text)

            Text(message)
                .font(AppTheme.bodyFont(size: 14))
                .foregroundColor(AppTheme.accent)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                Text("重试")
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.primaryColor)
            }
            .buttonStyle(.plain)

            Button(action: onCancel) {
                Text("留在录梦页")
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundColor(AppTheme.muted)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.surface)
                    .frame(height: 6)
                Rectangle()
                    .fill(AppTheme.primaryColor)
                    .frame(width: geo.size.width * stepProgress, height: 6)
                    .animation(.easeInOut(duration: 0.35), value: stepProgress)
            }
        }
        .frame(height: 6)
    }

    private var stepIndicators: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(DreamOrganizingPhase.organizingSteps, id: \.rawValue) { step in
                HStack(spacing: 10) {
                    stepIcon(for: step)
                    Text(step.label)
                        .font(AppTheme.bodyFont(size: 13, weight: step == phase ? .semibold : .regular))
                        .foregroundColor(step == phase ? AppTheme.text : AppTheme.muted)
                }
            }
        }
    }

    @ViewBuilder
    private func stepIcon(for step: DreamOrganizingPhase) -> some View {
        if step.rawValue < phase.rawValue || showsSuccess {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.background)
                .frame(width: 20, height: 20)
                .background(AppTheme.primaryColor)
        } else if step == phase {
            Circle()
                .strokeBorder(AppTheme.primaryColor, lineWidth: 2)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .fill(AppTheme.primaryColor)
                        .frame(width: 8, height: 8)
                )
        } else {
            Circle()
                .strokeBorder(AppTheme.surface, lineWidth: 1)
                .frame(width: 20, height: 20)
        }
    }
}

enum DreamOrganizingPhase: Int, CaseIterable {
    case preparing = 0
    case uploading = 1
    case transcribing = 2
    case analyzing = 3
    case complete = 4

    static var organizingSteps: [DreamOrganizingPhase] {
        [.preparing, .uploading, .transcribing, .analyzing]
    }

    var label: String {
        switch self {
        case .preparing: return "正在保存梦境"
        case .uploading: return "正在上传语音片段"
        case .transcribing: return "正在转写与合并"
        case .analyzing: return "正在温柔整理与解读"
        case .complete: return "即将进入梦析"
        }
    }

    var defaultStatusMessage: String {
        switch self {
        case .preparing: return "正在为你准备好记录…"
        case .uploading: return "把你的口述轻轻放进云端…"
        case .transcribing: return "聆听梦里的字句与停顿…"
        case .analyzing: return "梦悸正在陪你整理这条梦…"
        case .complete: return "整理完成"
        }
    }
}
