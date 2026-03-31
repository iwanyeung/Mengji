//
//  StaticStarfieldBackgroundView.swift
//  「关」档与 Metal 预热阶段：静态渐变 + 少量星点（低 GPU）。
//

import SwiftUI

struct StaticStarfieldBackgroundView: View {
    private static let starCount = 56

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0x0D / 255, green: 0x0C / 255, blue: 0x0F / 255),
                    Color(red: 0x12 / 255, green: 0x0E / 255, blue: 0x18 / 255),
                    Color(red: 0x0D / 255, green: 0x0C / 255, blue: 0x0F / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                gradient: Gradient(colors: [
                    AppTheme.primaryColor.opacity(0.12),
                    AppTheme.background.opacity(0)
                ]),
                center: UnitPoint(x: 0.35, y: 0.28),
                startRadius: 40,
                endRadius: 420
            )

            Canvas { context, size in
                for i in 0..<Self.starCount {
                    let u = Self.stableUnit(salt: UInt64(i) * 7 + 1)
                    let v = Self.stableUnit(salt: UInt64(i) * 7 + 3)
                    let w = Self.stableUnit(salt: UInt64(i) * 7 + 5)
                    let x = CGFloat(u) * size.width
                    let y = CGFloat(v) * size.height
                    let r = 0.6 + 1.4 * CGFloat(w)
                    let opacity = 0.15 + 0.35 * Double(w)
                    let rect = CGRect(x: x - r * 0.5, y: y - r * 0.5, width: r, height: r)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(AppTheme.text.opacity(opacity))
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private static func stableUnit(salt: UInt64) -> Double {
        var hash: UInt64 = 14695981039346656037
        for b in "mengji-static-starfield-\(salt)".utf8 {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return Double(hash % 10001) / 10000.0
    }
}
