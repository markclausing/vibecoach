import Foundation

// MARK: - AppStorageKeys
//
// Central namespace for the plain `UserDefaults` / `@AppStorage` key literals
// that were repeated across multiple files (Epic 65.1). Referencing a constant
// removes the silent-typo risk between writers and readers of the same key.
//
// Scope: only keys that had *no* existing home. Keys that already own a proper
// constant are referenced there, never duplicated here:
//   • `AIProvider.appStorageKey`         (AI provider selection)
//   • `AIModelAppStorageKey.*`           (per-provider model choice, Epic #35/#53)
//   • `AppLanguage.storageKey`           (app language, Epic #37)
//   • `MigrationFallbackStore.key`       (migration-fallback marker, §12)
//   • `StravaRateLimitStore.key`         (Strava rate-limit backoff)
//   • `PHIContextCache.keys`             (PHI prompt-context caches, Story 61.7)
//
// The raw values below are byte-identical to the literals they replace — these
// keys back persisted state, so their string values must never change.
enum AppStorageKeys {

    /// Onboarding gatekeeper flag (Epic #31 V2.0 flow). `true` once the user has
    /// completed onboarding; gates the background engines and root view.
    static let hasCompletedOnboarding = "hasCompletedOnboarding"

    /// Number of workouts the last HealthKit sync returned in its window. Read by
    /// the Dashboard's "silent sync" banner evaluator (Epic #38 Story 38.2).
    static let lastHKWorkoutsCount = "vibecoach_lastHKWorkoutsCount"

    /// User's display name, shown in the Dashboard header and Settings.
    static let userName = "vibecoach_userName"

    /// Preferred data source (`DataSource` raw value) — label/tiebreaker since
    /// Epic #42; HealthKit and Strava sync independently regardless of this.
    static let selectedDataSource = "selectedDataSource"

    /// Preferred colour scheme override (`"auto"` / `"light"` / `"dark"`).
    static let colorScheme = "vibecoach_colorScheme"
}
