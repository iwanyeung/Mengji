//
//  StarfieldBackgroundSettings.swift
//  潜意识星图动态星野：用户档位 + 低电量策略
//

import Foundation
import SwiftUI

enum StarfieldBackgroundMode: String, CaseIterable, Identifiable {
    case full
    case powerSaving
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "开（完整）"
        case .powerSaving: return "省电"
        case .off: return "关（静态）"
        }
    }

    var footnote: String {
        switch self {
        case .full:
            return "全屏动态星野，视觉最强，设备负载较高。"
        case .powerSaving:
            return "降低帧率与运算量，略糊、星更少、飞行动画更慢。"
        case .off:
            return "仅静态渐变与少量星点，最省电。"
        }
    }
}

enum StarfieldSettings {
    static let appStorageKey = "starfieldBackgroundMode"

    /// 用户选择；低电量时若未选「关」则强制省电档。
    static func effectiveMode(stored: StarfieldBackgroundMode, isLowPower: Bool) -> StarfieldBackgroundMode {
        if stored == .off { return .off }
        if isLowPower { return .powerSaving }
        return stored
    }
}

/// Metal 星野档位参数（与 `StarFieldShader.metal` 中 `StarFieldUniforms` 对应）。
struct StarfieldMetalConfig {
    var preferredFPS: Int
    var flightSpeed: Float
    var maxSteps: Int32
    var drawDistance: Float
    var starThreshold: Float
    var nebulaLastIndex: Int32

    static func forMode(_ mode: StarfieldBackgroundMode) -> StarfieldMetalConfig? {
        switch mode {
        case .full:
            return StarfieldMetalConfig(
                preferredFPS: 24,
                flightSpeed: 8,
                maxSteps: 64,
                drawDistance: 58,
                starThreshold: 0.798,
                nebulaLastIndex: 2
            )
        case .powerSaving:
            return StarfieldMetalConfig(
                preferredFPS: 15,
                flightSpeed: 5,
                maxSteps: 44,
                drawDistance: 48,
                starThreshold: 0.82,
                nebulaLastIndex: 2
            )
        case .off:
            return nil
        }
    }
}
