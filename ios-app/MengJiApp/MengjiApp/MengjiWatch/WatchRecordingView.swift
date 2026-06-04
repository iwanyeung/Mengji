import SwiftUI

struct WatchRecordingView: View {
    @StateObject private var viewModel = WatchRecordingViewModel()
    @State private var pulse = false

    var body: some View {
        ZStack {
            WatchTheme.background.ignoresSafeArea()

            VStack(spacing: 10) {
                if showsBrandLogo {
                    Image("BrandLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                statusText
                    .font(WatchTheme.bodyFont(size: 11))
                    .foregroundStyle(WatchTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)

                if viewModel.isRecording {
                    Text(viewModel.durationText)
                        .font(WatchTheme.bodyFont(size: 14, weight: .medium))
                        .foregroundStyle(WatchTheme.text)
                        .monospacedDigit()
                }

                if viewModel.segmentCount > 0, !viewModel.isRecording {
                    Text("已传 \(viewModel.segmentCount) 段")
                        .font(WatchTheme.bodyFont(size: 10))
                        .foregroundStyle(WatchTheme.primary)
                }

                recordButton
            }
            .padding(.vertical, 8)
        }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
            viewModel.updateDurationDisplay()
        }
        .onChange(of: viewModel.isRecording) { _, recording in
            pulse = recording
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch viewModel.phase {
        case .idle:
            Text("点击记录梦境")
        case .recording:
            Text("正在聆听…再次点击结束本段")
        case .segmentSent:
            Text("本段已传到手机，可继续录；整理请在 iPhone 完成")
        case .permissionDenied:
            Text("需要麦克风权限")
        case .error(let message):
            Text(message)
        }
    }

    private var recordButton: some View {
        Button {
            Task { await viewModel.handlePrimaryTap() }
        } label: {
            ZStack {
                if viewModel.isRecording {
                    Circle()
                        .stroke(WatchTheme.accent.opacity(0.35), lineWidth: 2)
                        .frame(width: 88, height: 88)
                        .scaleEffect(pulse ? 1.12 : 0.92)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                }

                Circle()
                    .fill(viewModel.isRecording ? WatchTheme.accent : WatchTheme.primary)
                    .frame(width: 72, height: 72)
                    .shadow(color: (viewModel.isRecording ? WatchTheme.accent : WatchTheme.primary).opacity(0.45), radius: 10)

                if case .segmentSent = viewModel.phase {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WatchTheme.background)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var showsBrandLogo: Bool {
        switch viewModel.phase {
        case .idle, .segmentSent, .permissionDenied:
            return true
        case .recording, .error:
            return false
        }
    }
}
