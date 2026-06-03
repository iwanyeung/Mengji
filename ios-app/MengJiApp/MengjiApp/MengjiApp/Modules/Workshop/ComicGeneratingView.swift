import SwiftUI

struct ComicGeneratingView: View {
    let dreamTitle: String
    let panelCount: Int
    let statusMessage: String
    var onMinimize: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsePhase = false

    private var progress: Double {
        min(1, Double(panelCount) / 4.0)
    }

    private var showsIndeterminateProgress: Bool {
        panelCount == 0
    }

    var body: some View {
        ZStack {
            AppAuroraBackground(style: .workshop)

            VStack(alignment: .leading, spacing: 24) {
                Text("梦正在落成四格")
                    .font(AppTheme.titleFont(size: 22))
                    .foregroundColor(AppTheme.text)

                if !dreamTitle.isEmpty {
                    Text("《\(dreamTitle)》")
                        .font(AppTheme.bodyFont(size: 15))
                        .foregroundColor(AppTheme.muted)
                }

                Text(statusMessage)
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeInOut(duration: 0.25), value: statusMessage)

                progressBar

                Text("第 \(min(panelCount, 4))/4 格")
                    .font(AppTheme.capsFont(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.primaryColor)

                panelIndicators

                Text("你可以先去别处看看；回到梦作间可查看进度，完成后会在这里提醒你。")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundColor(AppTheme.muted)
                    .lineSpacing(4)
                    .padding(.top, 4)

                Spacer()

                Button(action: onMinimize) {
                    Text("后台继续")
                        .font(AppTheme.bodyFont(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.primaryColor)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .padding(.top, 32)
        }
        .interactiveDismissDisabled()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulsePhase = true
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.surface)
                    .frame(height: 6)

                if showsIndeterminateProgress {
                    indeterminateBar(width: geo.size.width)
                } else {
                    Rectangle()
                        .fill(AppTheme.primaryColor)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.easeInOut(duration: 0.35), value: progress)
                }
            }
        }
        .frame(height: 6)
    }

    private func indeterminateBar(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 4.0 : 1.0 / 20.0)) { context in
            let cycle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let segment = width * 0.28
            let x = (width + segment) * cycle - segment
            Rectangle()
                .fill(AppTheme.primaryColor.opacity(0.85))
                .frame(width: segment, height: 6)
                .offset(x: x)
        }
    }

    private var panelIndicators: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                panelCell(for: index)
            }
        }
    }

    @ViewBuilder
    private func panelCell(for index: Int) -> some View {
        let isCompleted = index < panelCount
        let isCurrent = index == panelCount && panelCount < 4

        RoundedRectangle(cornerRadius: 0)
            .strokeBorder(
                isCompleted ? AppTheme.primaryColor : (isCurrent ? AppTheme.primaryColor : AppTheme.surface),
                lineWidth: isCompleted || isCurrent ? 2 : 1
            )
            .frame(height: 48)
            .background(
                isCompleted
                    ? AppTheme.primaryColor.opacity(0.12)
                    : AppTheme.background.opacity(0.3)
            )
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(AppTheme.primaryColor.opacity(pulsePhase ? 0.35 : 0.9), lineWidth: 1)
                        .padding(3)
                }
            }
            .scaleEffect(isCurrent && pulsePhase && !reduceMotion ? 1.02 : 1.0)
            .animation(isCurrent ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default, value: pulsePhase)
    }
}
