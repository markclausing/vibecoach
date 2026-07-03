import os

// MARK: - Central Logger namespace (Epic 39 Story 39.1 + tech-debt audit May 2026)
//
// `Logger` is internally thread-safe, so actor isolation around it adds nothing and
// only produces Swift 6 warnings ("main actor-isolated static property cannot be
// accessed from outside of the actor"). By keeping all loggers in a plain `enum`
// they are nonisolated and freely accessible from `actor`, `@MainActor`
// and `@Sendable` contexts.
//
// Migration policy (from the audit): all `print(...)` in `Services/` has been replaced by
// a logger call with a `privacy:` modifier on PII (HRV, sleep, TRIMP, tokens,
// notification titles). The public modifier is only for framework error codes and
// non-identifying status flags. The default `.private` applies
// when you specify nothing.

enum AppLoggers {
    private static let subsystem = "com.markclausing.aifitnesscoach"

    /// HRV, sleep and profile queries. `.private` for sample values.
    static let athleticProfileManager = Logger(subsystem: subsystem, category: "AthleticProfileManager")

    /// Strava connection, token refresh and workout sync via `FitnessDataService`.
    static let fitnessDataService = Logger(subsystem: subsystem, category: "FitnessDataService")

    /// Dual Engine proactive notifications (`HKObserverQuery` + `BGAppRefreshTask`).
    static let proactiveNotification = Logger(subsystem: subsystem, category: "ProactiveNotificationService")

    /// Auto-detect HR/FTP thresholds based on workout statistics.
    static let physiologicalThreshold = Logger(subsystem: subsystem, category: "PhysiologicalThresholdService")

    /// Age, weight and sex flow via HealthKit + UserProfile.
    static let userProfile = Logger(subsystem: subsystem, category: "UserProfileService")

    /// Open-Meteo weather forecast + CoreLocation.
    static let weather = Logger(subsystem: subsystem, category: "WeatherManager")

    /// Keychain storage for BYOK API keys + UserDefaults migration.
    static let userAPIKey = Logger(subsystem: subsystem, category: "UserAPIKeyStore")

    /// XCUITest mock environment (DEBUG only).
    static let uiTestMock = Logger(subsystem: subsystem, category: "UITestMockEnvironment")

    /// `WorkoutInsightService` AI-call failures.
    static let workoutInsight = Logger(subsystem: subsystem, category: "WorkoutInsightService")

    /// Coach chat / prompt assembly (`ChatViewModel`). Assembled prompt + raw
    /// model response are the entire PHI corpus → always `.private`; only
    /// framework error codes and non-identifying status flags are `.public`.
    static let coach = Logger(subsystem: subsystem, category: "ChatViewModel")

    /// Active training-plan mutations (`TrainingPlanManager`).
    static let trainingPlan = Logger(subsystem: subsystem, category: "TrainingPlanManager")

    /// Local proactive-notification delivery callbacks (`AppDelegate`).
    /// Notification titles/payloads can carry goal titles → `.private`.
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")

    /// 30-day Deep Sync orchestrator (`DeepSyncService`). Workout UUIDs → `.private`.
    static let deepSync = Logger(subsystem: subsystem, category: "DeepSync")

    /// Per-workout sample ingest (`WorkoutSampleService`). Workout UUIDs → `.private`.
    static let workoutSamples = Logger(subsystem: subsystem, category: "WorkoutSamples")

    /// Dashboard-level orchestration diagnostics: auto-sync, dedupe, session
    /// reclassification, Vibe Score calculation. Sample values (HRV/sleep) and
    /// activity ids → `.private`; counters and framework errors → `.public`.
    static let dashboard = Logger(subsystem: subsystem, category: "Dashboard")
}
