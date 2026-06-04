import SwiftUI

enum WatchTheme {
    static let background = Color(red: 0x0D / 255, green: 0x0C / 255, blue: 0x0F / 255)
    static let primary = Color(red: 0xD4 / 255, green: 0xFF / 255, blue: 0x33 / 255)
    static let accent = Color(red: 0xFF / 255, green: 0x33 / 255, blue: 0x66 / 255)
    static let text = Color(red: 0xF4 / 255, green: 0xF0 / 255, blue: 0xEB / 255)
    static let muted = Color(red: 0x7A / 255, green: 0x75 / 255, blue: 0x85 / 255)

    static func titleFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}
