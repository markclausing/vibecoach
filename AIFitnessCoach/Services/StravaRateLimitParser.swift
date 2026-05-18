import Foundation

// MARK: - Epic #51-F2: Strava Rate-Limit Parser
//
// Pure-Swift helper die uit een HTTP 429-response de retry-after-tijd
// extraheert zodat de Sync-status-banner *"Strava-limiet bereikt — hervat om
// HH:MM"* een concreet tijdstip kan tonen en de auto-sync een cooldown-window
// kan respecteren.
//
// Strava ondersteunt twee `Retry-After`-vormen volgens RFC 7231:
//   1. Aantal seconden: `"60"` (delta-seconds)
//   2. HTTP-datum: `"Wed, 21 Oct 2025 07:28:00 GMT"`
//
// Fallback: 15 minuten — dat is Strava's korte-termijn rate-limit-window
// (100 verzoeken per 15 min). Bij dagelijkse limiet (1.000 per dag) geeft
// Strava meestal een expliciete `Retry-After`-header zodat de fallback
// alleen relevant is bij ontbrekende of misvormde header.
//
// AppStorage-vrij + side-effect-vrij; caller bepaalt zelf wanneer de
// resulterende Date wordt opgeslagen in UserDefaults (cooldown-storage in
// `FitnessDataService`).

enum StravaRateLimitParser {

    /// Default-cooldown wanneer de `Retry-After`-header ontbreekt of niet
    /// parseerbaar is. Strava's 15-min-window is een veilige bovengrens.
    static let defaultCooldownSeconds: TimeInterval = 15 * 60

    /// Berekent het tijdstip waarop de client mag hervatten.
    /// - Parameters:
    ///   - headers: `HTTPURLResponse.allHeaderFields` — case-insensitive lookup
    ///     wordt door deze helper zelf gedaan zodat callers met verschillende
    ///     dictionary-types werken.
    ///   - now: huidig tijdstip — injecteerbaar voor deterministische tests.
    /// - Returns: Absolute `Date` waarop de cooldown afloopt.
    static func retryAfter(headers: [AnyHashable: Any],
                           now: Date = Date()) -> Date {
        guard let rawValue = caseInsensitiveValue(forKey: "Retry-After", in: headers),
              !rawValue.isEmpty else {
            return now.addingTimeInterval(defaultCooldownSeconds)
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Variant 1: delta-seconds — pure integer.
        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }

        // Variant 2: HTTP-datum (RFC 7231 §7.1.1.1).
        if let date = httpDateFormatter.date(from: trimmed) {
            // Bescherming tegen klok-skew: een datum in het verleden mag de
            // cooldown niet onmiddellijk laten verlopen — gebruik dan de
            // default zodat we niet meteen weer in de retry-storm zitten.
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
