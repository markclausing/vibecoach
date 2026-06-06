import SwiftUI

// MARK: - Epic #51-F1/F2/F5: Sync status banner
//
// One central banner on the Dashboard that — depending on the current
// `SyncStatusSnapshot` — shows an offline, rate-limit or error message.
// Pure UI wrapper around `SyncBannerStateBuilder`; all logic lives there,
// this view only picks the correct icon, color and text.
//
// Reactivity:
//   • Offline state via `@StateObject NetworkReachabilityMonitor` (NWPath).
//   • Cooldown and error state via `@AppStorage` keys on
//     `UserDefaults.standard`; the store writes there behind the scenes.
//     On every change SwiftUI re-renders automatically.
//
// Cooldown and offline banners are not dismissable — they correct
// themselves when the status changes. Error banners have a close button
// that clears the error fields in the store.

struct SyncStatusBanner: View {
    @ObservedObject private var reachability = NetworkReachabilityMonitor.shared

    @AppStorage(StravaRateLimitStore.key) private var rateLimitedUntilTimestamp: Double = 0
    @AppStorage(SyncStatusStore.Keys.lastStravaErrorCategory) private var stravaErrorRaw: String = ""
    @AppStorage(SyncStatusStore.Keys.lastStravaErrorAt) private var stravaErrorAtTimestamp: Double = 0
    @AppStorage(SyncStatusStore.Keys.lastHKErrorCategory) private var hkErrorRaw: String = ""
    @AppStorage(SyncStatusStore.Keys.lastHKErrorAt) private var hkErrorAtTimestamp: Double = 0
    @AppStorage(SyncStatusStore.Keys.lastStravaSyncAt) private var stravaSuccessTimestamp: Double = 0
    @AppStorage(SyncStatusStore.Keys.lastHKSyncAt) private var hkSuccessTimestamp: Double = 0

    private let store: SyncStatusStore

    init(store: SyncStatusStore = SyncStatusStore()) {
        self.store = store
    }

    var body: some View {
        Group {
            if let state = currentState() {
                bannerView(for: state)
            }
        }
        .onAppear {
            reachability.start()
        }
    }

    // MARK: State

    private func currentState() -> SyncBannerState? {
        let snapshot = SyncStatusSnapshot(
            isOffline: !reachability.isOnline,
            stravaRateLimitedUntil: timestampOrNil(rateLimitedUntilTimestamp),
            lastStravaError: SyncErrorCategory(rawValue: stravaErrorRaw),
            lastStravaErrorAt: timestampOrNil(stravaErrorAtTimestamp),
            lastHKError: SyncErrorCategory(rawValue: hkErrorRaw),
            lastHKErrorAt: timestampOrNil(hkErrorAtTimestamp),
            lastStravaSuccessAt: timestampOrNil(stravaSuccessTimestamp),
            lastHKSuccessAt: timestampOrNil(hkSuccessTimestamp)
        )
        return SyncBannerStateBuilder.state(from: snapshot)
    }

    private func timestampOrNil(_ value: Double) -> Date? {
        // `@AppStorage<Date>` does not work reliably; the store writes Unix
        // timestamps so the view can observe via a primitive `Double` binding.
        // `0` is our sentinel for "empty".
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    // MARK: Rendering

    @ViewBuilder
    private func bannerView(for state: SyncBannerState) -> some View {
        switch state {
        case .offline(let lastSyncAt):
            DashboardBannerView(icon: "wifi.slash", color: .gray) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Geen verbinding")
                        .font(.subheadline.bold())
                    if let date = lastSyncAt {
                        Text("Laatste sync \(Self.timeFormatter.string(from: date)).")
                            .font(.caption)
                    } else {
                        Text("Open de app opnieuw als je weer online bent.")
                            .font(.caption)
                    }
                }
            }
        case .rateLimited(let until):
            DashboardBannerView(icon: "hourglass", color: .orange) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Strava-limiet bereikt")
                        .font(.subheadline.bold())
                    Text("Hervat om \(Self.timeFormatter.string(from: until)).")
                        .font(.caption)
                }
            }
        case .stravaError(let category):
            errorBanner(
                title: "Strava-sync mislukt",
                message: message(for: category, source: "Strava"),
                onDismiss: store.clearErrors
            )
        case .healthKitError(let category):
            errorBanner(
                title: "Apple Health-sync mislukt",
                message: message(for: category, source: "HealthKit"),
                onDismiss: store.clearErrors
            )
        }
    }

    @ViewBuilder
    private func errorBanner(title: String, message: String, onDismiss: @escaping () -> Void) -> some View {
        DashboardBannerView(icon: "exclamationmark.arrow.triangle.2.circlepath", color: .red) {
            VStack(alignment: .leading, spacing: 8) {
                // Epic #37 story 37.1c: title is a Dutch literal -> catalog; message is already
                // localized by message(for:source:).
                Text(LocalizedStringKey(title))
                    .font(.subheadline.bold())
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    onDismiss()
                } label: {
                    Text("Sluit")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // Epic #37 story 37.1c: rendered via Text(message) -> verbatim, so resolve via the catalog.
    // `source` (Strava/HealthKit, a brand name) interpolates as %@.
    private func message(for category: SyncErrorCategory, source: String) -> String {
        switch category {
        case .network:
            return String(localized: "Geen verbinding met \(source). Probeer opnieuw vanuit Instellingen.")
        case .authentication:
            return String(localized: "Aanmelden bij \(source) is nodig — controleer de koppeling in Instellingen.")
        case .rateLimit:
            // Defensive fallback; rateLimit should go through the separate banner.
            return String(localized: "\(source)-limiet bereikt. Probeer het later opnieuw.")
        case .decoding:
            return String(localized: "\(source) gaf een onleesbaar antwoord. Probeer opnieuw vanuit Instellingen.")
        case .other:
            return String(localized: "\(source)-sync mislukt. Probeer opnieuw vanuit Instellingen.")
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.currentLocale
        f.dateFormat = "HH:mm"
        return f
    }()
}
