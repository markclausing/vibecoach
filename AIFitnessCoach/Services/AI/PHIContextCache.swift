import Foundation
import SwiftData

// MARK: - Story 61.3 / 61.7 (security-review follow-up): central PHI context-cache purge
//
// The coach prompt is assembled from a corpus of *derived* health context —
// Vibe Score (HRV/sleep), per-body-area symptom scores, 14-day workout history
// (TRIMP/HR/power), nutrition, at-risk goal titles, etc.
//
// Story 61.3: introduced this helper so all prompt-context caches are cleared
//   in one place on data-source disconnect / logout / app reset.
//
// Story 61.7: the 17 core PHI context caches (ChatViewModel prompt-context
//   strings) were moved from cleartext UserDefaults into the file-protected
//   SwiftData store (`CoachContextCache`).  The keys below are those that still
//   live in UserDefaults.  `purgeSwiftData(from:)` covers the SwiftData side.
//
// Pure helper: the caller injects `UserDefaults` (§6), so it stays free of
// `@AppStorage` and is unit-testable.
enum PHIContextCache {

    /// UserDefaults keys that still hold (derived) PHI health data.
    /// The 17 ChatViewModel context strings are no longer here — they moved
    /// to `CoachContextCache` (SwiftData) in Story 61.7.
    static let keys: [String] = [
        // Training-plan + coach-insight caches (binary plist / plain string).
        "latestSuggestedPlanData",
        "latestCoachInsight",
        // ProactiveNotificationService risk cache — at-risk goal titles are PHI.
        "vibecoach_atRiskGoalTitles"
    ]

    /// Removes the remaining cleartext PHI caches from UserDefaults plus the
    /// per-workout AI insight cache (`WorkoutInsightCache`).
    /// Call on data-source disconnect, logout, or app reset.
    /// Safe to call repeatedly; the caches rebuild on the next refresh.
    static func purge(_ defaults: UserDefaults = .standard) {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        WorkoutInsightCache(defaults: defaults).clearAll()
    }

    /// Clears the SwiftData PHI context cache (Story 61.7).
    /// Call alongside `purge(_:)` on data-source disconnect or logout so the
    /// `CoachContextCache` singleton is wiped from the protected store too.
    static func purgeSwiftData(from context: ModelContext) {
        CoachContextCache.purge(in: context)
    }
}
