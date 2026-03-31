import Foundation
import SwiftUI

// MARK: - 性别认同

enum GenderIdentity: String, Codable, CaseIterable, Hashable {
    case male
    case female
    case nonBinary
    case preferNotToSay

    var displayTitle: String {
        switch self {
        case .male: return "男"
        case .female: return "女"
        case .nonBinary: return "非二元"
        case .preferNotToSay: return "不愿透露"
        }
    }
}

// MARK: - 年龄段

enum AgeRange: String, Codable, CaseIterable, Hashable {
    case under18
    case age18_24
    case age25_34
    case age35_44
    case age45Plus

    var displayTitle: String {
        switch self {
        case .under18: return "18 岁以下"
        case .age18_24: return "18–24 岁"
        case .age25_34: return "25–34 岁"
        case .age35_44: return "35–44 岁"
        case .age45Plus: return "45 岁及以上"
        }
    }
}

// MARK: - 色彩氛围偏好（与设计令牌对应）

enum ColorPreference: String, Codable, CaseIterable, Hashable {
    case acidYellow
    case neonPink
    case boneWhite
    case deepPurple
    case ashMuted
    case inkBlack

    var displayTitle: String {
        switch self {
        case .acidYellow: return "明亮 · 聚焦"
        case .neonPink: return "情绪 · 张力"
        case .boneWhite: return "克制 · 清晰"
        case .deepPurple: return "夜色 · 内敛"
        case .ashMuted: return "安静 · 观察"
        case .inkBlack: return "极简 · 留白"
        }
    }

    /// 设计系统色块（用于列表旁展示）
    var swatchColor: Color {
        switch self {
        case .acidYellow: return AppTheme.primaryColor
        case .neonPink: return AppTheme.accent
        case .boneWhite: return AppTheme.text
        case .deepPurple: return AppTheme.surface
        case .ashMuted: return AppTheme.muted
        case .inkBlack: return AppTheme.background
        }
    }
}

// MARK: - 个人资料（本地持久化，后续可同步云端）

struct UserProfile: Codable, Equatable {
    var gender: GenderIdentity?
    var ageRange: AgeRange?
    var colorPreference: ColorPreference?

    static let empty = UserProfile(gender: nil, ageRange: nil, colorPreference: nil)
}
