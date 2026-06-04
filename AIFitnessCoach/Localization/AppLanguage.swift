import Foundation

// MARK: - Epic #37 story 37.5: AppLanguage

/// The app's language preference and the single source of truth for resolving the
/// active `Locale`.
///
/// Two readers need the active locale:
/// - **SwiftUI views** get it via `.environment(\.locale, …)` injected at the app root.
/// - **Pure-Swift services** (formatters in `Services/`, prompt builders) can't read the
///   SwiftUI environment, so they read `AppLanguage.currentLocale` — which resolves from
///   the same `@AppStorage` key. Keeping both paths backed by one key avoids drift.
///
/// Default is `.system`: existing users keep following their device locale, so there is
/// no forced language switch on upgrade (story 37.5 requirement). Picking a specific
/// language overrides the device locale app-wide.
///
/// Note (Epic #37): this PR wires the *preference + locale resolution + picker*. The
/// actual UI-string translation lives in the String Catalog (`Localizable.xcstrings`,
/// a follow-up PR); until that lands, switching language affects locale-aware date/number
/// formatting, not yet the hardcoded UI literals.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case dutch
    case english
    case german
    case spanish

    var id: String { rawValue }

    /// UserDefaults key shared by the `@AppStorage` property wrapper (SwiftUI) and the
    /// static `current` reader (services). Must match the `@AppStorage` declarations.
    static let storageKey = "vibecoach_appLanguage"

    /// The languages the app ships translations for. `.system` is the default and is
    /// listed first in the picker.
    static var selectableCases: [AppLanguage] { allCases }

    // MARK: - Resolution

    /// The currently selected language, read from `UserDefaults`. Falls back to `.system`
    /// when unset or unrecognised. Used by non-SwiftUI call sites.
    static var current: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = AppLanguage(rawValue: raw) else {
            return .system
        }
        return value
    }

    /// The active `Locale` for the whole app. `.system` resolves to the device locale;
    /// a specific language resolves to that language's locale.
    static var currentLocale: Locale { current.resolvedLocale }

    /// The `Locale` this case represents. `.system` mirrors `Locale.current` (the device),
    /// so date/number formatting keeps following the device for users who never pick a language.
    var resolvedLocale: Locale {
        switch self {
        case .system:  return Locale.current
        case .dutch:   return Locale(identifier: "nl_NL")
        case .english: return Locale(identifier: "en_US")
        case .german:  return Locale(identifier: "de_DE")
        case .spanish: return Locale(identifier: "es_ES")
        }
    }

    /// The base language code (`nl`/`en`/`de`/`es`) for a specific case, or `nil` for
    /// `.system`. Used by the String Catalog / `AppleLanguages` override.
    var languageCode: String? {
        switch self {
        case .system:  return nil
        case .dutch:   return "nl"
        case .english: return "en"
        case .german:  return "de"
        case .spanish: return "es"
        }
    }

    // MARK: - Runtime bundle override

    /// `UserDefaults` key that overrides the app's localization at launch. SwiftUI loads the
    /// matching `.lproj` from `Localizable.xcstrings` based on this, so `Text("…")` resolves to
    /// the chosen language. iOS reads it once at launch — hence the picker shows a relaunch note.
    static let appleLanguagesKey = "AppleLanguages"

    /// Writes (or clears for `.system`) the `AppleLanguages` override so the next launch loads
    /// the chosen language's strings. `.system` removes the override and restores device behaviour.
    func applyToBundleOverride(_ defaults: UserDefaults = .standard) {
        if let code = languageCode {
            defaults.set([code], forKey: Self.appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        }
    }

    // MARK: - Display

    /// The picker label, shown in the language's own name (endonym) so each option is
    /// recognisable regardless of the current UI language. `.system` is labelled in Dutch
    /// for now (the current base language); it becomes a localized key with the catalog.
    var displayName: String {
        switch self {
        case .system:  return "Systeemtaal"
        case .dutch:   return "Nederlands"
        case .english: return "English"
        case .german:  return "Deutsch"
        case .spanish: return "Español"
        }
    }
}
