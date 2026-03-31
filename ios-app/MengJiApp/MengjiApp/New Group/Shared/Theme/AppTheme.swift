import SwiftUI

enum AppTheme {
    static let primaryColor = Color(red: 0xD4/255, green: 0xFF/255, blue: 0x33/255)
    static let background   = Color(red: 0x0D/255, green: 0x0C/255, blue: 0x0F/255)
    static let surface      = Color(red: 0x1E/255, green: 0x1A/255, blue: 0x25/255)
    static let text         = Color(red: 0xF4/255, green: 0xF0/255, blue: 0xEB/255)
    static let muted        = Color(red: 0x7A/255, green: 0x75/255, blue: 0x85/255)
    static let accent       = Color(red: 0xFF/255, green: 0x33/255, blue: 0x66/255)

    /// 统一标题字体：使用系统 serif，保持优雅感与中文可读性。
    static func titleFont(size: CGFloat) -> Font {
        return .system(size: size, weight: .semibold, design: .serif)
    }

    /// 统一正文字体：使用系统 default。
    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .default)
    }

    /// 统一小号全大写标签字体（用于元信息、section label、chip）。
    static func capsFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

enum AppAuroraStyle {
    case insight
    case workshop
}

/// 页面级极光背景：低电量强制静态，梦析可额外压暗保证文本优先。
struct AppAuroraBackground: View {
    let style: AppAuroraStyle
    var prioritizeTextReadability: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        ZStack {
            AppTheme.background

            if !isLowPowerMode {
                SpotAuroraMetalBackgroundView(
                    isPaused: reduceMotion,
                    motionAllowed: true,
                    config: spotAuroraConfig
                )
                .opacity(auroraOpacity)
            }

            LinearGradient(
                gradient: Gradient(colors: [
                    AppTheme.background.opacity(topBottomVignetteOpacity),
                    AppTheme.background.opacity(0.08),
                    AppTheme.background.opacity(topBottomVignetteOpacity)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )

            if readabilityOverlayOpacity > 0 {
                AppTheme.background
                    .opacity(readabilityOverlayOpacity)
            }
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private var auroraOpacity: CGFloat {
        switch style {
        case .insight:
            return 0.24
        case .workshop:
            return 0.35
        }
    }

    private var topBottomVignetteOpacity: CGFloat {
        switch style {
        case .insight:
            return 0.52
        case .workshop:
            return 0.4
        }
    }

    private var readabilityOverlayOpacity: CGFloat {
        guard prioritizeTextReadability else { return 0 }
        switch style {
        case .insight:
            return 0.3
        case .workshop:
            return 0.18
        }
    }

    private var spotAuroraConfig: SpotAuroraMetalBackgroundView.Config {
        switch style {
        case .insight:
            return .init(
                amplitude: 0.72,
                blend: 0.4,
                speed: 0.82,
                colorStop0: SIMD4<Float>(0x7C / 255, 0x8F / 255, 0x2A / 255, 0),
                colorStop1: SIMD4<Float>(0xD4 / 255, 0xFF / 255, 0x33 / 255, 0),
                colorStop2: SIMD4<Float>(0x7C / 255, 0x8F / 255, 0x2A / 255, 0)
            )
        case .workshop:
            return .init(
                amplitude: 0.95,
                blend: 0.52,
                speed: 1.25,
                colorStop0: SIMD4<Float>(0x89 / 255, 0x98 / 255, 0x2C / 255, 0),
                colorStop1: SIMD4<Float>(0xD4 / 255, 0xFF / 255, 0x33 / 255, 0),
                colorStop2: SIMD4<Float>(0xA3 / 255, 0xBD / 255, 0x34 / 255, 0)
            )
        }
    }
}
