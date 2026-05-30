import Foundation

// MARK: - Epic #51-F1/F2/F5: Sync-status store
//
// Tracks per data source the last success timestamp and the last error
// category so the Dashboard `SyncStatusBanner` can decide with one snapshot
// what to show (offline > rate-limit > error > nil).
//
// Single source of truth for the visibility of sync results —
// auto-sync writes to this store, the View reads via a snapshot. Deliberately
// AppStorage-free so the helper stays unit-testable with a fresh
// `UserDefaults(suiteName:)` (CLAUDE.md §6).
//
// `.missingToken` is not a banner-worthy error (the user deliberately did not
// connect Strava) and must be filtered out by the caller via `recordStravaError`.
// See `SyncErrorCategory.from(strava:)`.

/// Categorises sync errors so the banner builder can pick the right type message
/// without the original `Error` instance.
enum SyncErrorCategory: String, Codable, Equatable {
    case network          // -1009 offline, hostname not found, generic transport error
    case authentication   // 401 / token issue
    case rateLimit        // 429 — paired with `stravaRateLimitedUntil`
    case decoding         // Server response malformed
    case other            // Unknown / non-categorisable

    /// Mapping for `FitnessDataError` — `.missingToken` returns `nil`
    /// because that is not a banner error.
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

    /// Mapping for HealthKit errors — almost always network- or permission-
    /// related, but HK throws `HKError` with its own codes. For banner purposes
    /// a coarse categorisation is enough.
    static func from(healthKit error: Error) -> SyncErrorCategory {
        if (error as NSError).domain == NSURLErrorDomain {
            return .network
        }
        return .other
    }
}

/// Pure-Swift snapshot for `SyncBannerStateBuilder`. No reference types,
/// no UserDefaults — the caller builds it and hands it to the builder.
struct SyncStatusSnapshot: Equatable {
    var isOffline: Bool
    var stravaRateLimitedUntil: Date?
    var lastStravaError: SyncErrorCategory?
    var lastStravaErrorAt: Date?
    var lastHKError: SyncErrorCategory?
    var lastHKErrorAt: Date?
    var lastStravaSuccessAt: Date?
    var lastHKSuccessAt: Date?

    /// Most recent successful sync (Strava or HK) — used for the
    /// offline banner *"No connection — last sync HH:MM"*.
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

    // MARK: Recording (auto-sync caller side)

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

    /// Only writes when the error is banner-worthy — `.missingToken`
    /// (the user has not connected Strava) is explicitly filtered out
    /// so we don't show a "Strava sync failed" message to someone without a
    /// Strava connection.
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

    /// Clears both error messages — used by the banner-dismiss action
    /// for the generic error banner.
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
