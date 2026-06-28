import Foundation

/// Epic #62 story 62.4 (was 51.F4) — pure-Swift policy for retrying a failed weather fetch
/// without blocking. A weather error is non-fatal (the dashboard works fine without a forecast),
/// so instead of surfacing a hard error we record a retry marker (the last-failure time) and let
/// the next natural refresh re-attempt — throttled so we don't hammer Open-Meteo on every appear.
///
/// AppStorage-free (§6): the caller persists `lastFailureAt` and injects it here.
enum WeatherRetryPolicy {

    /// Minimum gap between automatic retries after a failure. Short enough that a transient
    /// blip clears on the next dashboard visit, long enough to avoid a refresh storm.
    static let retryCooldown: TimeInterval = 5 * 60   // 5 minutes

    /// True when a new automatic fetch should be attempted. With no prior failure (`nil`) the
    /// answer is always yes (normal first/expired fetch); after a failure it waits out the cooldown.
    static func shouldRetry(lastFailureAt: Date?, now: Date = Date()) -> Bool {
        guard let last = lastFailureAt else { return true }
        return now.timeIntervalSince(last) >= retryCooldown
    }

    /// Seconds until the next retry is allowed (0 when retry is allowed now). For a subtle
    /// "weather temporarily unavailable, retrying" hint without a blocking error.
    static func secondsUntilRetry(lastFailureAt: Date?, now: Date = Date()) -> TimeInterval {
        guard let last = lastFailureAt else { return 0 }
        return max(0, retryCooldown - now.timeIntervalSince(last))
    }
}
