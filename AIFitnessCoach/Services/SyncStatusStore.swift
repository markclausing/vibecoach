import Foundation

// MARK: - Epic #51-F1/F2/F5: Sync-status-store
//
// Houdt per data-source de laatste succes-timestamp en de laatste fout-
// categorie bij zodat de Dashboard-`SyncStatusBanner` met één snapshot
// kan beslissen wat hij toont (offline > rate-limit > error > nil).
//
// Single-source-of-truth voor de zichtbaarheid van sync-resultaten —
// auto-sync schrijft naar deze store, View leest via een snapshot. Bewust
// AppStorage-vrij zodat de helper unit-testbaar blijft met een fresh
// `UserDefaults(suiteName:)` (CLAUDE.md §6).
//
// `.missingToken` is geen banner-waardige fout (gebruiker heeft Strava
// bewust niet gekoppeld) en moet door de caller via `recordStravaError`
// worden uitgefilterd. Zie `SyncErrorCategory.from(strava:)`.

/// Categoriseert sync-fouten zodat het banner-builder zonder de oorspronkelijke
/// `Error`-instance het juiste type-bericht kan kiezen.
enum SyncErrorCategory: String, Codable, Equatable {
    case network          // -1009 offline, hostname not found, generieke transport-fout
    case authentication   // 401 / token-issue
    case rateLimit        // 429 — gepaard met `stravaRateLimitedUntil`
    case decoding         // Server-response misvormd
    case other            // Onbekend / niet-categoriseerbaar

    /// Mapping voor `FitnessDataError` — `.missingToken` retourneert `nil`
    /// omdat dat geen banner-fout is.
    static func from(strava error: Error) -> SyncErrorCategory? {
        if let fitnessError = error as? FitnessDataError {
            switch fitnessError {
            case .missingToken:
                return nil
            case .unauthorized:
                return .authentication
            case .rateLimited:
                return .rateLimit
            case .networkError:
                return .network
            case .decodingError:
                return .decoding
            case .invalidResponse:
                return .other
            }
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return .network
        }
        return .other
    }

    /// Mapping voor HealthKit-fouten — vrijwel altijd netwerk- of permissie-
    /// gerelateerd, maar HK gooit `HKError` met eigen codes. Voor banner-doel-
    /// einden is een grove categorisering genoeg.
    static func from(healthKit error: Error) -> SyncErrorCategory {
        if (error as NSError).domain == NSURLErrorDomain {
            return .network
        }
        return .other
    }
}

/// Pure-Swift snapshot voor `SyncBannerStateBuilder`. Geen reference-types,
/// geen UserDefaults — caller bouwt 'm en geeft 'm aan de builder.
struct SyncStatusSnapshot: Equatable {
    var isOffline: Bool
    var stravaRateLimitedUntil: Date?
    var lastStravaError: SyncErrorCategory?
    var lastStravaErrorAt: Date?
    var lastHKError: SyncErrorCategory?
    var lastHKErrorAt: Date?
    var lastStravaSuccessAt: Date?
    var lastHKSuccessAt: Date?

    /// Meest recente succesvolle sync (Strava óf HK) — gebruikt voor de
    /// offline-banner *"Geen verbinding — laatste sync HH:MM"*.
    var lastAnySyncSuccessAt: Date? {
        switch (lastStravaSuccessAt, lastHKSuccessAt) {
        case let (s?, h?): return max(s, h)
        case let (s?, nil): return s
        case let (nil, h?): return h
        case (nil, nil):    return nil
        }
    }
}

struct SyncStatusStore {

    enum Keys {
        static let lastStravaSyncAt        = "vibecoach_lastStravaSyncAt"
        static let lastHKSyncAt            = "vibecoach_lastHKSyncAt"
        static let lastStravaErrorCategory = "vibecoach_lastStravaErrorCategory"
        static let lastStravaErrorAt       = "vibecoach_lastStravaErrorAt"
        static let lastHKErrorCategory     = "vibecoach_lastHKErrorCategory"
        static let lastHKErrorAt           = "vibecoach_lastHKErrorAt"
        static let dismissedRateLimitUntil = "vibecoach_dismissedRateLimitUntil"
    }

    private let defaults: UserDefaults
    private let rateLimitStore: StravaRateLimitStore

    init(defaults: UserDefaults = .standard,
         rateLimitStore: StravaRateLimitStore = StravaRateLimitStore()) {
        self.defaults = defaults
        self.rateLimitStore = rateLimitStore
    }

    // MARK: Recording (caller-side van auto-sync)

    func recordStravaSuccess(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: Keys.lastStravaSyncAt)
        defaults.removeObject(forKey: Keys.lastStravaErrorCategory)
        defaults.removeObject(forKey: Keys.lastStravaErrorAt)
    }

    func recordHKSuccess(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: Keys.lastHKSyncAt)
        defaults.removeObject(forKey: Keys.lastHKErrorCategory)
        defaults.removeObject(forKey: Keys.lastHKErrorAt)
    }

    /// Schrijft alleen wanneer de fout banner-waardig is — `.missingToken`
    /// (gebruiker heeft Strava niet gekoppeld) wordt expliciet uitgefilterd
    /// zodat we geen "Strava-sync mislukt"-melding tonen aan iemand zonder
    /// Strava-koppeling.
    func recordStravaError(_ error: Error, at date: Date = Date()) {
        guard let category = SyncErrorCategory.from(strava: error) else { return }
        defaults.set(category.rawValue, forKey: Keys.lastStravaErrorCategory)
        defaults.set(date.timeIntervalSince1970, forKey: Keys.lastStravaErrorAt)
    }

    func recordHKError(_ error: Error, at date: Date = Date()) {
        let category = SyncErrorCategory.from(healthKit: error)
        defaults.set(category.rawValue, forKey: Keys.lastHKErrorCategory)
        defaults.set(date.timeIntervalSince1970, forKey: Keys.lastHKErrorAt)
    }

    /// Wist beide error-meldingen — gebruikt door de banner-dismiss-actie
    /// voor de generieke fout-banner.
    func clearErrors() {
        defaults.removeObject(forKey: Keys.lastStravaErrorCategory)
        defaults.removeObject(forKey: Keys.lastStravaErrorAt)
        defaults.removeObject(forKey: Keys.lastHKErrorCategory)
        defaults.removeObject(forKey: Keys.lastHKErrorAt)
    }

    // MARK: Snapshot

    func snapshot(isOffline: Bool, now: Date = Date()) -> SyncStatusSnapshot {
        SyncStatusSnapshot(
            isOffline: isOffline,
            stravaRateLimitedUntil: rateLimitStore.currentCooldown(now: now),
            lastStravaError: readErrorCategory(key: Keys.lastStravaErrorCategory),
            lastStravaErrorAt: readDate(key: Keys.lastStravaErrorAt),
            lastHKError: readErrorCategory(key: Keys.lastHKErrorCategory),
            lastHKErrorAt: readDate(key: Keys.lastHKErrorAt),
            lastStravaSuccessAt: readDate(key: Keys.lastStravaSyncAt),
            lastHKSuccessAt: readDate(key: Keys.lastHKSyncAt)
        )
    }

    private func readErrorCategory(key: String) -> SyncErrorCategory? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return SyncErrorCategory(rawValue: raw)
    }

    private func readDate(key: String) -> Date? {
        let value = defaults.double(forKey: key)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }
}
