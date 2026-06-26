import Foundation
import SwiftData

// MARK: - SchemaV6: Story 61.7 — CoachContextCache added
//
// Difference from SchemaV5: adds `CoachContextCache`, a new @Model that stores the
// 17 PHI prompt-context strings that previously lived as cleartext in UserDefaults
// (@AppStorage).  A new model is a pure addition — `MigrationStage.lightweight`
// from V5 to V6 is sufficient (SwiftData creates the new table; no existing rows
// are touched).
//
// Per CLAUDE.md §2.1: every @Model change requires a schema bump, including pure
// additions (the May 2026 incident proves lightweight inference is not enough).

enum SchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Symptom.self,
         DailyReadiness.self,
         WorkoutSample.self,
         FitnessGoal.self,
         ActivityRecord.self,
         UserPreference.self,
         UserConfiguration.self,
         CoachContextCache.self]
    }
}
