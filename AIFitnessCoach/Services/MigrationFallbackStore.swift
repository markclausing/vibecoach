import Foundation

/// Houdt bij of de SwiftData-migratie tijdens de laatste app-launch is gefaald
/// en de defensieve fresh-DB-fallback uit `AIFitnessCoachApp.makeModelContainer()`
/// is geactiveerd (CLAUDE.md §12).
///
/// De flag wordt gezet door de container-init en uitgelezen door
/// `MigrationFallbackBanner` op het Dashboard zodat de gebruiker weet dat
/// lokaal-only data (`FitnessGoal`, `UserPreference`, `Symptom`) is verloren.
/// Workouts uit HealthKit en Strava zijn niet beïnvloed — die syncen vanzelf
/// terug.
///
/// Pure-Swift, geen AppStorage — UserDefaults is via de init injecteerbaar
/// zodat unit-tests met een fresh `UserDefaults(suiteName:)` werken (CLAUDE.md §6).
struct MigrationFallbackStore {
    static let key = "vibecoach_migrationFallbackAt"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Datum waarop de fresh-DB-fallback voor het laatst is geactiveerd,
    /// of `nil` als er geen actieve melding hangt.
    var fallbackDate: Date? {
        defaults.object(forKey: Self.key) as? Date
    }

    /// Aangeroepen door de container-init bij een succesvolle fresh-DB-fallback.
    func recordFallback(at date: Date = Date()) {
        defaults.set(date, forKey: Self.key)
    }

    /// Wist de flag — wordt aangeroepen wanneer de gebruiker de banner sluit.
    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
