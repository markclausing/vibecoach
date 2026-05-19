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
    /// Epic #51-F6: captive-portal-mirror naar UserDefaults zodat `SyncStatusBanner`
    /// via `@AppStorage` reactief kan lezen zonder dependency op deze singleton.
    static let captivePortalKey = "vibecoach_isCaptivePortal"

    @Published private(set) var isOnline: Bool = true

    /// "Schijnbaar online maar geblokkeerd" — NWPathMonitor zegt `.satisfied`
    /// maar de actieve probe of een live API-response leverde HTML i.p.v. JSON
    /// op (hotel-portal, corporate VPN-redirect). Aparte staat van `isOnline`
    /// zodat de banner een specifieke melding kan tonen.
    @Published private(set) var isCaptivePortal: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.markclausing.aifitnesscoach.NetworkReachability")
    private var hasStarted = false

    /// Probe-hook — injecteerbaar zodat tests een synthetische probe-uitkomst
    /// kunnen leveren zonder daadwerkelijke netwerk-call.
    private let probe: () async -> Bool

    init(probe: @escaping () async -> Bool = NetworkReachabilityMonitor.defaultProbe) {
        self.probe = probe
    }

    /// Idempotent — kan veilig vanuit meerdere lifecycle-hooks worden
    /// aangeroepen. Tweede en latere calls zijn no-ops zodat we niet meerdere
    /// path-update-handlers stapelen.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            Task { @MainActor in
                await self?.applyStatus(online)
            }
        }
        monitor.start(queue: queue)
    }

    /// Wordt aangeroepen door services (FitnessDataService, HistoricalWeatherService)
    /// zodra ze HTML zien op een JSON-endpoint. Schrijft direct naar de banner-
    /// state zodat de gebruiker niet hoeft te wachten op de volgende probe.
    func flagCaptivePortal() {
        if !isCaptivePortal {
            isCaptivePortal = true
        }
        UserDefaults.standard.set(true, forKey: Self.captivePortalKey)
    }

    /// Wis de captive-portal-state — wordt aangeroepen door de probe of door
    /// een succesvolle JSON-response op een eerder verdacht endpoint.
    func clearCaptivePortal() {
        if isCaptivePortal {
            isCaptivePortal = false
        }
        UserDefaults.standard.set(false, forKey: Self.captivePortalKey)
    }

    // MARK: Private

    private func applyStatus(_ online: Bool) async {
        if isOnline != online {
            isOnline = online
        }
        UserDefaults.standard.set(!online, forKey: Self.userDefaultsKey)

        if !online {
            // Offline → captive-portal-detectie is per definitie niet relevant;
            // wis de flag zodat de banner direct naar de offline-staat zakt.
            clearCaptivePortal()
            return
        }

        // Online — voer de probe uit om te checken of er een captive-portal
        // tussen zit. Faalt de probe (timeout/HTML)? Flag zetten. Slaagt 'm?
        // Cooldown wissen.
        let probeSuccessful = await probe()
        if probeSuccessful {
            clearCaptivePortal()
        } else {
            flagCaptivePortal()
        }
    }

    /// Productie-probe: HEAD/GET naar Apple's `captive.apple.com`. Faalt
    /// graceful — bij netwerk-fout retourneren we `true` zodat we de gebruiker
    /// niet onnodig met een banner lastigvallen wanneer alleen de probe-host
    /// onbereikbaar is.
    static func defaultProbe() async -> Bool {
        var request = URLRequest(url: CaptivePortalDetector.appleProbeURL,
                                  cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                  timeoutInterval: 5)
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return true }
            return CaptivePortalDetector.isAppleProbeSuccess(data: data, response: http)
        } catch {
            // Probe-host onbereikbaar ≠ captive-portal. Geef geen valse melding.
            return true
        }
    }
}
