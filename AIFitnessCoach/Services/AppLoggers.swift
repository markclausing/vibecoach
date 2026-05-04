import os

// MARK: - Centrale Logger-namespace (Epic 39 Story 39.1 + tech-debt audit mei 2026)
//
// `Logger` is intern thread-safe, dus actor-isolation eromheen voegt niets toe en
// bewaart alleen Swift 6-warnings ("main actor-isolated static property cannot be
// accessed from outside of the actor"). Door alle loggers in een plain `enum` te
// houden zijn ze nonisolated en vrij toegankelijk vanuit `actor`-, `@MainActor`-
// en `@Sendable`-contexten.
//
// Migratiebeleid (uit audit): alle `print(...)` in `Services/` is vervangen door
// een logger-call mét `privacy:`-modifier op PII (HRV, slaap, TRIMP, tokens,
// notificatie-titels). Public-modifier alleen voor framework-foutcodes en
// niet-identificerende status-flags. Standaard `.private`-default treedt in
// werking als je niets opgeeft.

enum AppLoggers {
    private static let subsystem = "com.markclausing.aifitnesscoach"

    /// HRV-, slaap- en profiel-queries. `.private` voor sample-waardes.
    static let athleticProfileManager = Logger(subsystem: subsystem, category: "AthleticProfileManager")

    /// Strava-koppeling, token-refresh en workout-sync via `FitnessDataService`.
    static let fitnessDataService = Logger(subsystem: subsystem, category: "FitnessDataService")

    /// Dual Engine proactieve notificaties (`HKObserverQuery` + `BGAppRefreshTask`).
    static let proactiveNotification = Logger(subsystem: subsystem, category: "ProactiveNotificationService")

    /// Auto-detect HR/FTP-drempels op basis van workout-statistiek.
    static let physiologicalThreshold = Logger(subsystem: subsystem, category: "PhysiologicalThresholdService")

    /// Leeftijd, gewicht en geslacht-flow via HealthKit + UserProfile.
    static let userProfile = Logger(subsystem: subsystem, category: "UserProfileService")

    /// Open-Meteo weersvoorspelling + CoreLocation.
    static let weather = Logger(subsystem: subsystem, category: "WeatherManager")

    /// Keychain-opslag voor BYOK API-keys + UserDefaults-migratie.
    static let userAPIKey = Logger(subsystem: subsystem, category: "UserAPIKeyStore")

    /// XCUITest mock-omgeving (alleen DEBUG).
    static let uiTestMock = Logger(subsystem: subsystem, category: "UITestMockEnvironment")

    /// `WorkoutInsightService` AI-call faulures.
    static let workoutInsight = Logger(subsystem: subsystem, category: "WorkoutInsightService")
}
