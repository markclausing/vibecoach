import Foundation

// MARK: - Epic #51-F2: Strava Rate-Limit Parser
//
// Pure-Swift helper that extracts the retry-after time from an HTTP 429 response
// so the sync-status banner *"Strava-limiet bereikt — hervat om HH:MM"*
// can show a concrete time and the auto-sync can respect a cooldown window.
//
// Strava supports two `Retry-After` forms per RFC 7231:
//   1. Number of seconds: `"60"` (delta-seconds)
//   2. HTTP date: `"Wed, 21 Oct 2025 07:28:00 GMT"`
//
// Fallback: 15 minutes — that is Strava's short-term rate-limit window
// (100 requests per 15 min). For the daily limit (1,000 per day) Strava
// usually provides an explicit `Retry-After` header so the fallback
// is only relevant on a missing or malformed header.
//
// AppStorage-free + side-effect-free; the caller decides when the
// resulting Date is stored in UserDefaults (cooldown storage in
// `FitnessDataService`).

enum StravaRateLimitParser {

    /// Default cooldown when the `Retry-After` header is missing or not
    /// parseable. Strava's 15-min window is a safe upper bound.
    static let defaultCooldownSeconds: TimeInterval = 15 * 60

    /// Computes the time at which the client may resume.
    /// - Parameters:
    ///   - headers: `HTTPURLResponse.allHeaderFields` — case-insensitive lookup
    ///     is done by this helper itself so callers with different
    ///     dictionary types work.
    ///   - now: current time — injectable for deterministic tests.
    /// - Returns: Absolute `Date` at which the cooldown expires.
    static func retryAfter(headers: [AnyHashable: Any],
                           now: Date = Date()) -> Date {
        guard let rawValue = caseInsensitiveValue(forKey: "Retry-After", in: headers),
              !rawValue.isEmpty else {
            return now.addingTimeInterval(defaultCooldownSeconds)
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Variant 1: delta-seconds — a pure integer.
        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }

        // Variant 2: HTTP date (RFC 7231 §7.1.1.1).
        if let date = httpDateFormatter.date(from: trimmed) {
            // Protection against clock skew: a date in the past must not let the
            // cooldown expire immediately — use the default then so we don't
            // land right back in the retry storm.
            return date > now ? date : now.addingTimeInterval(defaultCooldownSeconds)
        }

        return now.addingTimeInterval(defaultCooldownSeconds)
    }

    // MARK: Private

    private static func caseInsensitiveValue(forKey key: String,
                                             in headers: [AnyHashable: Any]) -> String? {
        for (k, v) in headers {
            if let keyString = k as? String,
               keyString.caseInsensitiveCompare(key) == .orderedSame {
                return v as? String
            }
        }
        return nil
    }

    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
}
