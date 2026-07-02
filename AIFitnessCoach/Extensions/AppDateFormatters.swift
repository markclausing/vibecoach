import Foundation

// MARK: - AppDateFormatters
//
// Centralised, cached `DateFormatter` factory. Replaces the ~40 inline
// `DateFormatter()` instantiations that repeated the same format strings
// (`"d MMM"` 6×, `"yyyy-MM-dd"` 9×, `"EEEE d MMM"` 5×, …) and set the locale
// inconsistently — some display formatters forgot `AppLanguage.currentLocale`
// (a silent i18n regression on EN/DE/ES, see CLAUDE.md §13), some fixed-format
// parsers forgot `en_US_POSIX` (a latent parse failure on exotic device locales).
//
// Three intents, matching the i18n split (CLAUDE.md §13):
//   • `display(_:)` / `displayStyle(_:)` — user-facing UI, in the current app
//     language. The cache is keyed on the active locale id, so switching language
//     at runtime yields a freshly-configured formatter (no stale cached locale).
//   • `prompt(_:)` / `promptStyle(_:)` — dates interpolated into the coach prompt.
//     Stay Dutch (`nl_NL`) as the prompt term, exactly like `SportCategory.displayName`;
//     the coach's output language is steered solely by the `respond in {language}`
//     directive, not by these dates.
//   • `fixed(_:utc:)` — machine-readable keys / interchange / API parsing.
//     `en_US_POSIX` so the produced/parsed string is stable regardless of device locale.
//
// Thread-safety: the cache dictionary is guarded by a lock, and the returned
// formatters are only ever read (`string(from:)` / `date(from:)`), which
// `DateFormatter` supports concurrently since iOS 7. Callers must not mutate the
// returned instance.
enum AppDateFormatters {

    private static let promptLocale = Locale(identifier: "nl_NL")
    private static let posixLocale  = Locale(identifier: "en_US_POSIX")
    private static let utcTimeZone  = TimeZone(identifier: "UTC")

    private static var cache: [String: DateFormatter] = [:]
    private static let cacheLock = NSLock()

    // MARK: Display (current app language)

    /// UI formatter with an explicit pattern (e.g. `"d MMM"`, `"EEEE d MMM"`), in the
    /// current app language. Rebuilds automatically when the user switches language.
    static func display(_ format: String) -> DateFormatter {
        let locale = AppLanguage.currentLocale
        return cached(key: "d|\(format)|\(locale.identifier)") {
            let f = DateFormatter()
            f.locale = locale
            f.dateFormat = format
            return f
        }
    }

    /// UI formatter using a `dateStyle` (date only, no time), in the current app language.
    static func displayStyle(_ style: DateFormatter.Style) -> DateFormatter {
        let locale = AppLanguage.currentLocale
        return cached(key: "ds|\(style.rawValue)|\(locale.identifier)") {
            let f = DateFormatter()
            f.locale = locale
            f.dateStyle = style
            f.timeStyle = .none
            return f
        }
    }

    // MARK: Prompt (Dutch coach-prompt term — CLAUDE.md §13)

    /// Coach-prompt formatter with an explicit pattern. Stays `nl_NL` on purpose:
    /// the interpolated date is a prompt term, like `SportCategory.displayName`.
    static func prompt(_ format: String) -> DateFormatter {
        cached(key: "p|\(format)") {
            let f = DateFormatter()
            f.locale = promptLocale
            f.dateFormat = format
            return f
        }
    }

    /// Coach-prompt formatter using a `dateStyle` (date only). `nl_NL`, see `prompt(_:)`.
    static func promptStyle(_ style: DateFormatter.Style) -> DateFormatter {
        cached(key: "ps|\(style.rawValue)") {
            let f = DateFormatter()
            f.locale = promptLocale
            f.dateStyle = style
            f.timeStyle = .none
            return f
        }
    }

    // MARK: Fixed (POSIX, machine-readable keys / parsing)

    /// Locale-stable formatter for machine-readable keys, interchange strings and API
    /// date parsing (e.g. `"yyyy-MM-dd"`, `"yyyy-MM-dd'T'HH:mm"`). Always `en_US_POSIX`.
    /// - Parameter utc: set for UTC-anchored API timestamps.
    static func fixed(_ format: String, utc: Bool = false) -> DateFormatter {
        cached(key: "f|\(format)|\(utc)") {
            let f = DateFormatter()
            f.locale = posixLocale
            f.dateFormat = format
            if utc { f.timeZone = utcTimeZone }
            return f
        }
    }

    // MARK: ISO-8601 (Strava / API timestamps)
    //
    // §13 exempts `ISO8601DateFormatter` from the locale rules above (different
    // API, always internet-date-time). Cached here purely to avoid re-allocating
    // a fresh formatter on every activity of every sync run. Like `DateFormatter`,
    // `ISO8601DateFormatter` is safe for concurrent read-only `date(from:)` use.

    /// ISO-8601 parser for Strava's fractional-second timestamps
    /// (e.g. `2024-01-02T12:34:56.789Z`).
    static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// ISO-8601 parser with the default internet-date-time options (no fractional
    /// seconds) — fallback for timestamps Strava returns without milliseconds.
    static let iso8601 = ISO8601DateFormatter()

    // MARK: Cache

    private static func cached(key: String, _ build: () -> DateFormatter) -> DateFormatter {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let existing = cache[key] { return existing }
        let formatter = build()
        cache[key] = formatter
        return formatter
    }
}
