import Foundation
import LocalAuthentication

/// 仅用于「进入个人中心」前的本机生物识别（面容 ID / 触控 ID 等），不替代 Apple 账号体系。
enum PersonalCenterBiometric {
    static let userDefaultsKey = "personalCenter.biometricEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// 是否具备可用的生物识别（需在主线程调用 UI 相关逻辑时可忽略，此处仅查询能力）
    static func canEvaluateBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// 用于界面短文案，例如「面容 ID」「触控 ID」
    static func biometryShortLabel() -> String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "生物识别"
        }
        switch context.biometryType {
        case .none:
            return "生物识别"
        case .faceID:
            return "面容 ID"
        case .touchID:
            return "触控 ID"
        case .opticID:
            return "Optic ID"
        @unknown default:
            return "生物识别"
        }
    }

    /// 进入个人中心前的验证（用户已开启开关时由 `MengjiAppApp` 调用）
    @MainActor
    static func authenticateForEntry() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        let reason = "验证身份以进入个人中心"
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}
