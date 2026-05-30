import Foundation
import Network
import Combine

// MARK: - Epic #51-F5: Network Reachability Monitor
//
// Lightweight wrapper around `NWPathMonitor` so the UI layer can react to the
// online status via `@StateObject` / `@EnvironmentObject`. One singleton to
// prevent parallel active monitors from giving duplicate callbacks and
// needlessly loading the path-monitor thread.
//
// Also writes a mirror to `UserDefaults` (`vibecoach_isOffline`) so
// non-View-layer callers (e.g. the future `SyncStatusStore` snapshot) have a
// synchronous read path without a dependency on this ObservableObject.
//
// Privacy: `NWPathMonitor` only reports reachability — no IP addresses,
// SSIDs or identifiers. Safe to run in release builds.

@MainActor
final class NetworkReachabilityMonitor: ObservableObject {

    static let shared = NetworkReachabilityMonitor()

    static let userDefaultsKey = "vibecoach_isOffline"

    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.markclausing.aifitnesscoach.NetworkReachability")
    private var hasStarted = false

    init() {}

    /// Idempotent — can safely be called from multiple lifecycle hooks.
    /// The second and later calls are no-ops so we don't stack multiple
    /// path-update handlers.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            Task { @MainActor in
                self?.applyStatus(online)
            }
        }
        monitor.start(queue: queue)
    }

    private func applyStatus(_ online: Bool) {
        if isOnline != online {
            isOnline = online
        }
        UserDefaults.standard.set(!online, forKey: Self.userDefaultsKey)
    }
}
