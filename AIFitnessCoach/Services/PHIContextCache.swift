import Foundation

// MARK: - Story 61.3 (security-review follow-up): central PHI context-cache purge
//
// The coach prompt is assembled from a corpus of *derived* health context —
// Vibe Score (HRV/sleep), per-body-area symptom scores, 14-day workout history
// (TRIMP/HR/power), nutrition, at-risk goal titles, etc. For fast prompt
// assembly without live SwiftData access these snapshots are cached as
// cleartext in `UserDefaults`/`@AppStorage` (`Library/Preferences`), which has
// only the app container's default file protection (M-2/L-9 in the review).
//
// Every one of these caches is *re-derivable* from the (file-protected)
// SwiftData store on the next dashboard refresh, so clearing them on a
// data-source disconnect / logout / app reset removes stale PHI from
// unprotected storage at no functional cost. This is the "at minimum" bar from
// M-2 plus the retention/purge control from L-9; relocating the caches into the
// protected store entirely is a separate, larger follow-up.
//
// Pure helper: the caller injects the `UserDefaults` instance (§6), so it stays
// free of `@AppStorage` and is unit-testable.
enum PHIContextCache {

    /// Every cleartext context-cache key that holds (derived) health data.
    /// Keep in sync with the `@AppStorage` keys in `ChatViewModel` and the
    /// risk-cache key in `ProactiveNotificationService`.
    static let keys: [String] = [
        // ChatViewModel prompt-context caches (PHI: HRV/sleep, symptoms,
        // workout history, nutrition, goal blueprints, …)
        "latestSuggestedPlanData",
        "latestCoachInsight",
        "vibecoach_todayVibeScoreContext",
        "vibecoach_lastWorkoutFeedbackContext",
        "vibecoach_blueprintContext",
        "vibecoach_periodizationContext",
        "vibecoach_lastAnalysisTimestamp",
        "vibecoach_symptomContext",
        "vibecoach_weatherContext",
        "vibecoach_workoutPatternsContext",
        "vibecoach_workoutHistoryContext",
        "vibecoach_gapAnalysisContext",
        "vibecoach_intentContext",
        "vibecoach_eventWindowContext",
        "vibecoach_projectionContext",
        "vibecoach_nutritionContext",
        "vibecoach_userOverrideContext",
        "vibecoach_intentExecutionContext",
        "vibecoach_profileUpdateNote",
        // ProactiveNotificationService risk cache — at-risk goal titles are PHI.
        "vibecoach_atRiskGoalTitles"
    ]

    /// Removes every cleartext PHI context cache plus the per-workout AI insight
    /// cache (`WorkoutInsightCache`). Call on data-source disconnect, logout, or
    /// app reset. Safe to call repeatedly; the caches rebuild on the next refresh.
    static func purge(_ defaults: UserDefaults = .standard) {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        WorkoutInsightCache(defaults: defaults).clearAll()
    }
}
