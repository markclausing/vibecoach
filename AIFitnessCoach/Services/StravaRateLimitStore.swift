import Foundation

// MARK: - Epic #51-F2: Strava Rate-Limit Cooldown Store
//
// Persists the Strava `Retry-After` time in UserDefaults so a
// 429 response is respected across app launches. An auto-sync trigger
// right after launch would otherwise immediately hit the rate limit again
// (Strava 100/15-min, 1,000/day), causing a retry storm and making the
// rate-limit banner flicker permanently.
//
// Pure-Swift, AppStorage-free — UserDefaults injectable via the init so
// unit tests work with a fresh `UserDefaults(suiteName:)` (CLAUDE.md §6).

struct StravaRateLimitStore {
    static let key = "vibecoach_stravaRateLimitedUntil"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Time the cooldown expires, or `nil` if no active limit is in place.
    /// Stored as a `Double` (Unix timestamp) so `@AppStorage` in
    /// `SyncStatusBanner` can bind to it directly — `@AppStorage` has
    /// no native support for `Date`.
    var rateLimitedUntil: Date? {
        let value = defaults.double(forKey: Self.key)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    /// Returns the active cooldown only if it has not yet expired.
    /// Expired entries are cleared immediately — prevents stale state.
    func currentCooldown(now: Date = Date()) -> Date? {
        guard let until = rateLimitedUntil else { return nil }
        if until > now {
            return until
        }
        clear()
        return nil
    }

    func record(until date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
