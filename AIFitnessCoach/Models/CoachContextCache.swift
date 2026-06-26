import Foundation
import SwiftData

// MARK: - Story 61.7 (security-review follow-up): PHI context caches in protected storage
//
// The coach prompt is assembled from ~17 derived health-context strings — Vibe Score,
// per-body-area symptom scores, 14-day workout history (TRIMP/HR/power), nutrition,
// goal blueprints, etc.  Before this story those snapshots lived as cleartext in
// `UserDefaults`/`@AppStorage` (`Library/Preferences`), which has only the default
// app-container file protection (M-2 in the June 2026 security review).
//
// Moving them here gives them the same `NSFileProtectionCompleteUnlessOpen` that all
// other SwiftData models received in Story 61.3 — so PHI no longer sits in an
// unprotected plist between dashboard refreshes.
//
// Singleton pattern: exactly one record is maintained in the store.
// `ChatViewModel.configure(with:)` fetches it on first access and creates it if absent.

@Model
final class CoachContextCache {

    // MARK: - Recovery / readiness context
    var todayVibeScoreContext: String = ""
    var lastWorkoutFeedbackContext: String = ""

    // MARK: - Goal coaching context
    var blueprintContext: String = ""
    var periodizationContext: String = ""
    var gapAnalysisContext: String = ""
    var intentContext: String = ""
    var eventWindowContext: String = ""
    var projectionContext: String = ""
    var userOverrideContext: String = ""
    var intentExecutionContext: String = ""

    // MARK: - Physiological / environmental context
    var symptomContext: String = ""
    var weatherContext: String = ""
    var workoutPatternsContext: String = ""
    var workoutHistoryContext: String = ""
    var nutritionContext: String = ""

    // MARK: - Profile / one-shot notices
    var profileUpdateNote: String = ""

    // MARK: - Timing
    /// Unix timestamp of the last successful coach-context analysis.
    /// Used by ChatViewModel to skip redundant re-builds on the same day.
    var lastAnalysisTimestamp: Double = 0

    init() {}

    // MARK: - Purge

    /// Resets every context field to its default — called on Strava disconnect / app reset.
    /// The singleton record is kept so `ChatViewModel` does not need to re-fetch on next launch;
    /// fields re-populate on the next dashboard refresh.
    func clearAll() {
        todayVibeScoreContext = ""
        lastWorkoutFeedbackContext = ""
        blueprintContext = ""
        periodizationContext = ""
        gapAnalysisContext = ""
        intentContext = ""
        eventWindowContext = ""
        projectionContext = ""
        userOverrideContext = ""
        intentExecutionContext = ""
        symptomContext = ""
        weatherContext = ""
        workoutPatternsContext = ""
        workoutHistoryContext = ""
        nutritionContext = ""
        profileUpdateNote = ""
        lastAnalysisTimestamp = 0
    }

    /// Clears all `CoachContextCache` records in the given context.
    /// Safe to call even if no record exists yet (no-op in that case).
    static func purge(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<CoachContextCache>())) ?? []
        all.forEach { $0.clearAll() }
        try? context.save()
    }
}
