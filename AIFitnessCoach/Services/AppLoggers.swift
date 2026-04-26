import os

// MARK: - Epic 39 Story 39.1: Centrale Logger-namespace
//
// `Logger` is intern thread-safe, dus actor-isolation eromheen voegt niets toe en
// bewaart alleen Swift 6-warnings ("main actor-isolated static property cannot be
// accessed from outside of the actor"). Door alle loggers in een plain `enum` te
// houden zijn ze nonisolated en vrij toegankelijk vanuit `actor`-, `@MainActor`-
// en `@Sendable`-contexten.
//
// Voor nu één entry. Bij volgende migraties (Epic #39 follow-up of nieuwe services)
// is dit het centrale punt om aan toe te voegen.

enum AppLoggers {
    private static let subsystem = "com.markclausing.aifitnesscoach"

    /// HRV-, slaap- en profiel-queries. `.private` voor sample-waardes.
    static let athleticProfileManager = Logger(subsystem: subsystem, category: "AthleticProfileManager")
}
