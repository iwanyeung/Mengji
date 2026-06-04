import SwiftUI

/// 已完成段为实心填充，当前段内为不确定进度光带（梦悸整理 / 四格生成共用）
struct MengjiSegmentedProgressBar: View {
    let solidProgress: Double
    let showsIndeterminate: Bool
    var barHeight: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let solid = min(1, max(0, solidProgress))
            let solidWidth = width * solid
            let activeWidth = max(0, width - solidWidth)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.surface)
                    .frame(height: barHeight)

                Rectangle()
                    .fill(AppTheme.primaryColor)
                    .frame(width: solidWidth, height: barHeight)
                    .animation(.easeInOut(duration: 0.35), value: solidWidth)

                if showsIndeterminate, activeWidth > 1 {
                    MengjiIndeterminateProgressCap(
                        trackWidth: activeWidth,
                        barHeight: barHeight
                    )
                    .offset(x: solidWidth)
                    .clipped()
                    .frame(width: activeWidth, height: barHeight, alignment: .leading)
                    .clipped()
                }
            }
        }
        .frame(height: barHeight)
    }
}

/// 在指定轨道宽度内左右滑动的酸性黄高亮段
struct MengjiIndeterminateProgressCap: View {
    let trackWidth: CGFloat
    var barHeight: CGFloat = 6
    var segmentRatio: CGFloat = 0.28
    var cycleDuration: TimeInterval = 1.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 4.0 : 1.0 / 20.0)) { context in
            let cycle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
            let segment = trackWidth * segmentRatio
            let x = (trackWidth + segment) * cycle - segment
            Rectangle()
                .fill(AppTheme.primaryColor.opacity(0.85))
                .frame(width: segment, height: barHeight)
                .offset(x: x)
        }
        .frame(width: trackWidth, height: barHeight, alignment: .leading)
        .clipped()
    }
}
