import LocalAuthentication

/// Wraps LAContext so the rest of the app deals in a plain yes/no rather than the framework's
/// own error types — a bill/insurance tracker is exactly the kind of app where "someone picks up
/// my unlocked phone" matters, so this is opt-in in Settings, not on by default.
struct AppLockService {
    static let shared = AppLockService()

    /// Whether this device can even offer Face ID/Touch ID/passcode — checked before showing the
    /// Settings toggle at all, so turning it on can't silently promise a lock that never engages.
    func canUseBiometrics() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// `.deviceOwnerAuthentication` (not the biometrics-only variant) so a passcode still unlocks
    /// the app on a device with Face ID temporarily unavailable (a mask, a bandage, Face ID
    /// disabled) — falling back to "no way in at all" would be worse than falling back to passcode.
    func authenticate() async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "appLock.reason"))
        } catch {
            return false
        }
    }
}
