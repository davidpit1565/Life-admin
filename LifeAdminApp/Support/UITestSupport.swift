import Foundation

/// Detects the launch argument the `LifeAdminUITests` screenshot target passes so the app can
/// seed deterministic demo data, skip real system-permission prompts, and force an in-memory
/// store — App Store screenshots must never depend on a Simulator's permission state, a system
/// alert appearing, or (worse) a real user's on-disk data. Never true outside that test target:
/// nothing in the shipping app ever passes this argument itself.
enum UITestSupport {
    static var isCapturingScreenshots: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestScreenshots")
    }
}
