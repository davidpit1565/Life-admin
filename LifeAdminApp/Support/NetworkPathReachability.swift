import Foundation
import Network
import LifeAdminCore

/// A real network-reachability check, replacing LifeAdminAIService's default
/// AlwaysOnlineReachability. Without this, adding an item while genuinely offline still attempts
/// the Gemini request and waits for it to time out (up to 12 seconds) before falling back to
/// local parsing — this lets that fallback happen immediately instead.
final class NetworkPathReachability: ReachabilityChecking, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var satisfied = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.satisfied = path.status == .satisfied
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "com.lifeadmin.reachability"))
    }

    var isNetworkAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return satisfied
    }
}
