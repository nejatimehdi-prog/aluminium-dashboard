import Foundation
import LocalAuthentication

/// Optional Face ID / Touch ID lock with the device passcode as fallback.
/// This is an access gate only; data at rest is protected by iOS Data Protection.
enum AppLock {
    enum Availability {
        case available(biometry: String)
        case passcodeOnly
        case unavailable(String)
    }

    static func availability() -> Availability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable("برای قفل برنامه باید روی دستگاه رمز عبور فعال باشد.")
        }
        var bioError: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &bioError) {
            switch context.biometryType {
            case .faceID: return .available(biometry: "Face ID")
            case .touchID: return .available(biometry: "Touch ID")
            default: return .passcodeOnly
            }
        }
        return .passcodeOnly
    }

    /// Returns true when the owner authenticated (biometrics or device passcode).
    static func authenticate(reason: String = "بازکردن چُرتکه") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "انصراف"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
