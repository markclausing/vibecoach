import Foundation

/// Tracks whether the SwiftData migration failed during the last app launch
/// and the defensive fresh-DB fallback from `AIFitnessCoachApp.makeModelContainer()`
/// was activated (CLAUDE.md §12).
///
/// The flag is set by the container init and read by
/// `MigrationFallbackBanner` on the Dashboard so the user knows that
/// local-only data (`FitnessGoal`, `UserPreference`, `Symptom`) was lost.
/// Workouts from HealthKit and Strava are unaffected — those sync back
/// automatically.
///
/// Pure-Swift, no AppStorage — UserDefaults is injectable via the init
/// so unit tests work with a fresh `UserDefaults(suiteName:)` (CLAUDE.md §6).
struct MigrationFallbackStore {
    static let key = "vibecoach_migrationFallbackAt"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Date the fresh-DB fallback was last activated,
    /// or `nil` if there is no active message.
    var fallbackDate: Date? {
        defaults.object(forKey: Self.key) as? Date
    }

    /// Called by the container init on a successful fresh-DB fallback.
    func recordFallback(at date: Date = Date()) {
        defaults.set(date, forKey: Self.key)
    }

    /// Clears the flag — called when the user dismisses the banner.
    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
