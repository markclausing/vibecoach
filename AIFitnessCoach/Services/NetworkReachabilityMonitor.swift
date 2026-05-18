import Foundation
import Network
import Combine

// MARK: - Epic #51-F5: Network Reachability Monitor
//
// Lichte wrapper rond `NWPathMonitor` zodat de UI-laag via `@StateObject` /
// `@EnvironmentObject` op de online-status kan reageren. Eén singleton om te
// voorkomen dat parallel actieve monitors duplicate-callbacks geven en de
// path-monitor-thread onnodig belasten.
//
// Schrijft ook een mirror naar `UserDefaults` (`vibecoach_isOffline`) zodat
// niet-View-laag-callers (bv. de toekomstige `SyncStatusStore`-snapshot) een
// synchrone lees-pad hebben zonder dependency op deze ObservableObject.
//
// Privacy: `NWPathMonitor` rapporteert alleen reachability — geen IP-adressen,
// SSIDs of identifiers. Veilig om in release-builds te draaien.

@MainActor
final class NetworkReachabilityMonitor: ObservableObject {

    static let shared = NetworkReachabilityMonitor()

    static let userDefaultsKey = "vibecoach_isOffline"

    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.markclausing.aifitnesscoach.NetworkReachability")
    private var hasStarted = false

    init() {}

    /// Idempotent — kan veilig vanuit meerdere lifecycle-hooks worden
    /// aangeroepen. Tweede en latere calls zijn no-ops zodat we niet meerdere
    /// path-update-handlers stapelen.
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
