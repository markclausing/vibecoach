import Foundation
import SwiftData

// MARK: - SchemaV5: Epic #55 — multi-day event duration on FitnessGoal
//
// Difference from SchemaV4: `FitnessGoal` gets one new optional field,
// `eventDurationDays: Int?` (number of consecutive event days; nil/≤1 = single-day).
// A pure addition, so `MigrationStage.lightweight(fromVersion: V4, toVersion: V5)` is
// sufficient. Existing records get `nil` — they keep behaving as single-day events.
//
// Per CLAUDE.md §2.1: every `@Model` change requires a schema bump, including pure
// additions. Without the version bump SwiftData sees a hash mismatch on V4 and the
// fallback in `makeModelContainer` wipes the store (loses local-only Symptom +
// UserPreference data). Like V3/V4, this references the live runtime types directly —
// no separate V5 class definitions needed for a pure addition.

enum SchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Symptom.self,
         DailyReadiness.self,
         WorkoutSample.self,
         FitnessGoal.self,
         ActivityRecord.self,
         UserPreference.self,
         UserConfiguration.self]
    }
}
