import SwiftUI

/// 逐字从模糊到清晰，受 `replayToken` 驱动；每次切回 Tab 递增 token 重播。
struct BlurRevealTitle: View {
    let text: String
    let fontSize: CGFloat
    let replayToken: UInt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var characters: [String] {
        text.map { String($0) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, ch in
                BlurRevealCharacter(
                    character: ch,
                    index: index,
                    fontSize: fontSize,
                    replayToken: replayToken,
                    reduceMotion: reduceMotion
                )
            }
        }
    }
}

private struct BlurRevealCharacter: View {
    let character: String
    let index: Int
    let fontSize: CGFloat
    let replayToken: UInt
    let reduceMotion: Bool

    @State private var blurRadius: CGFloat = 7
    @State private var opacity: Double = 0.15

    var body: some View {
        Text(character)
            .font(AppTheme.titleFont(size: fontSize))
            .foregroundColor(AppTheme.text)
            .blur(radius: blurRadius)
            .opacity(opacity)
            .task(id: replayToken) {
                play()
            }
    }

    private func play() {
        if reduceMotion {
            blurRadius = 0
            opacity = 1
            return
        }
        blurRadius = 7
        opacity = 0.15
        let delay = Double(index) * 0.085
        withAnimation(.easeInOut(duration: 0.95).delay(delay)) {
            blurRadius = 0
            opacity = 1
        }
    }
}
