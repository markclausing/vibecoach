import Foundation

// MARK: - Epic #51-F2: Strava Rate-Limit Cooldown Store
//
// Persisteert het Strava `Retry-After`-tijdstip in UserDefaults zodat een
// 429-response wordt gerespecteerd over app-launches heen. Auto-sync trigger
// vlak na launch zou anders direct opnieuw tegen de rate-limit aanlopen
// (Strava 100/15-min, 1.000/dag), wat een retry-storm geeft en de
// rate-limit-banner permanent zou laten knipperen.
//
// Pure-Swift, AppStorage-vrij — UserDefaults via init injecteerbaar zodat
// unit-tests met een fresh `UserDefaults(suiteName:)` werken (CLAUDE.md §6).

struct StravaRateLimitStore {
    static let key = "vibecoach_stravaRateLimitedUntil"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Tijdstip waarop de cooldown afloopt, of `nil` als geen actieve limiet hangt.
    /// Wordt als `Double` (Unix-timestamp) opgeslagen zodat `@AppStorage` in
    /// `SyncStatusBanner` er rechtstreeks op kan binden — `@AppStorage` heeft
    /// geen native ondersteuning voor `Date`.
    var rateLimitedUntil: Date? {
        let value = defaults.double(forKey: Self.key)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    /// Geeft de actieve cooldown alleen terug als hij nog niet verlopen is.
    /// Verlopen entries worden meteen gewist — voorkomt stale state.
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
