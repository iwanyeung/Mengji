import SwiftUI

enum DreamOrganizingTiming {
    static let successDisplaySeconds: Double = 2
    static let successDisplayNanoseconds: UInt64 = 2_000_000_000
    /// 全屏收起后再切 Tab，避免与成功页叠在一起显得过快
    static let postDismissNavigateNanoseconds: UInt64 = 300_000_000
}

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsePhase = false
    @State private var successReveal = false
    @State private var successBarLit = false
    @State private var successDotCount = 0

    private static let organizingStepCount = Double(DreamOrganizingPhase.organizingSteps.count)

    private var solidProgress: Double {
        if showsSuccess { return 1 }
        let base = Double(phase.rawValue) / Self.organizingStepCount
        let inStep: Double = {
            guard phase == .uploading, segmentCount > 0 else { return 0 }
            let uploaded = Double(min(uploadedSegmentIndex, segmentCount))
            return (uploaded / Double(segmentCount)) / Self.organizingStepCount
        }()
        return min(1, base + inStep)
    }

    private var showsIndeterminateProgress: Bool {
        !showsSuccess && DreamOrganizingPhase.organizingSteps.contains(phase)
    }

    var body: some View {
        ZStack {
            AppAuroraBackground(
                style: .insight,
                prioritizeTextReadability: false
            )

            Group {
                if showsSuccess {
                    successScreen
                } else if let errorMessage {
                    errorScreen(message: errorMessage)
                } else {
                    organizingScreen
                }
            }
        }
        .interactiveDismissDisabled(errorMessage == nil && !showsSuccess)
        .sensoryFeedback(.success, trigger: showsSuccess) { _, isSuccess in
            isSuccess
        }
        .onAppear { startPulseIfNeeded() }
        .onChange(of: showsSuccess) { _, isSuccess in
            if isSuccess {
                playSuccessReveal()
            } else {
                resetSuccessPresentation()
            }
            startPulseIfNeeded()
        }
        .onChange(of: errorMessage) { _, _ in startPulseIfNeeded() }
    }

    private var organizingScreen: some View {
        VStack(alignment: .leading, spacing: 24) {
            organizingContent
            Spacer()
        }
        .padding(24)
        .padding(.top, 32)
    }

    private var successScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            successContent
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func errorScreen(message: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            errorContent(message: message)
            Spacer()
        }
        .padding(24)
        .padding(.top, 32)
    }

    private func playSuccessReveal() {
        successReveal = reduceMotion
        successBarLit = reduceMotion
        guard !reduceMotion else { return }
        successReveal = false
        successBarLit = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
            successReveal = true
        }
        withAnimation(.easeOut(duration: 0.4)) {
            successBarLit = true
        }
    }

    private func resetSuccessPresentation() {
        successReveal = false
        successBarLit = false
        successDotCount = 0
    }

    private func startPulseIfNeeded() {
        guard !reduceMotion, !showsSuccess, errorMessage == nil else { return }
        pulsePhase = false
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulsePhase = true
        }
    }

    private var organizingContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            organizingContentBody
        }
        .animation(.easeInOut(duration: 0.4), value: statusMessage)
    }

    private var organizingContentBody: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("梦悸正在整理这条梦")
                .font(AppTheme.titleFont(size: 22))
                .foregroundColor(AppTheme.text)

            Text("共 \(segmentCount) 段口述")
                .font(AppTheme.bodyFont(size: 15))
                .foregroundColor(AppTheme.muted)

            statusMessageView

            MengjiSegmentedProgressBar(
                solidProgress: solidProgress,
                showsIndeterminate: showsIndeterminateProgress
            )

            if phase == .uploading && segmentCount > 0 {
                Text("第 \(min(uploadedSegmentIndex, segmentCount))/\(segmentCount) 段已保存")
                    .font(AppTheme.capsFont(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.primaryColor)
                    .transition(.opacity)
            }

            stepIndicators

            Text("请保持应用在前台，通常需要约 30 秒～2 分钟")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundColor(AppTheme.muted)
                .lineSpacing(4)
                .padding(.top, 4)
        }
    }

    private var statusMessageView: some View {
        Text(statusMessage)
            .font(AppTheme.bodyFont(size: 15, weight: .semibold))
            .foregroundColor(AppTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .id(statusMessage)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
            )
    }

    private var successContent: some View {
        VStack(spacing: 28) {
            MengjiSegmentedProgressBar(solidProgress: 1, showsIndeterminate: false)
                .opacity(successBarLit ? 1 : 0.35)
                .frame(maxWidth: 280)

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(AppTheme.primaryColor)
                    .scaleEffect(successReveal ? 1 : 0.55)
                    .opacity(successReveal ? 1 : 0)

                VStack(spacing: 10) {
                    Text("整理完成")
                        .font(AppTheme.titleFont(size: 30))
                        .foregroundColor(AppTheme.text)
                        .opacity(successReveal ? 1 : 0)
                        .offset(y: successReveal ? 0 : 10)

                    Text("陪你看这条梦，梦析已准备好。")
                        .font(AppTheme.bodyFont(size: 16))
                        .foregroundColor(AppTheme.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .opacity(successReveal ? 1 : 0)
                        .offset(y: successReveal ? 0 : 8)
                }
            }

            successEnteringHint
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .task(id: showsSuccess) {
            guard showsSuccess else { return }
            successDotCount = 0
            while !Task.isCancelled, showsSuccess {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { break }
                successDotCount = (successDotCount + 1) % 3
            }
        }
    }

    private var successEnteringHint: some View {
        let dots = String(repeating: "·", count: successDotCount + 1)
        return Text("即将进入梦析\(dots)")
            .font(AppTheme.capsFont(size: 12, weight: .semibold))
            .foregroundColor(AppTheme.primaryColor.opacity(0.85))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: successDotCount)
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

    private var stepIndicators: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(DreamOrganizingPhase.organizingSteps, id: \.rawValue) { step in
                HStack(spacing: 10) {
                    stepIcon(for: step)
                    Text(step.label)
                        .font(AppTheme.bodyFont(size: 13, weight: step == phase ? .semibold : .regular))
                        .foregroundColor(step == phase ? AppTheme.text : AppTheme.muted)
                }
                .animation(.easeInOut(duration: 0.25), value: phase)
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
            ZStack {
                Circle()
                    .strokeBorder(
                        AppTheme.primaryColor.opacity(pulsePhase && !reduceMotion ? 0.35 : 0.9),
                        lineWidth: 2
                    )
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(AppTheme.primaryColor)
                    .frame(width: pulsePhase && !reduceMotion ? 9 : 8, height: pulsePhase && !reduceMotion ? 9 : 8)
            }
            .scaleEffect(pulsePhase && !reduceMotion ? 1.06 : 1.0)
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
        comfortMessages.first ?? ""
    }

    /// 各阶段轮播文案（整理等待页定时切换 + 滑入过渡）
    var comfortMessages: [String] {
        switch self {
        case .preparing:
            return [
                "正在为你准备好记录…",
                "轻轻收起这条梦的线索…",
            ]
        case .uploading:
            return [
                "把你的口述轻轻放进云端…",
                "逐段保存你的声音…",
                "梦的话语正在路上…",
            ]
        case .transcribing:
            return [
                "聆听梦里的字句与停顿…",
                "正在辨认口述里的语气…",
                "把几段梦连成一条线…",
            ]
        case .analyzing:
            return [
                "梦悸正在陪你整理这条梦…",
                "仍在聆听你梦里的细节…",
                "温柔整理字里行间…",
                "正在写下陪伴式解读…",
            ]
        case .complete:
            return ["整理完成"]
        }
    }
}
