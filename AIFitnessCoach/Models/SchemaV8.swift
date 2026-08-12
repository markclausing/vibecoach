import Foundation
import SwiftData

// MARK: - SchemaV8: Epic #73 — race priority on FitnessGoal

// Difference from SchemaV7: `FitnessGoal` gets one new optional field,
// `racePriority: RacePriority?` (A/B/C priority within a multi-goal macrocycle; nil = unset,
// MacrocyclePlanner then derives it from dates). A pure addition, so
// `MigrationStage.lightweight(fromVersion: V7, toVersion: V8)` is sufficient — SwiftData adds
// the column, existing records get `nil`.
//
// This references the **live** runtime types: `FitnessGoal.self` now IS the V8 shape (with
// `racePriority`), and every other model is unchanged since V7, so they stay live references.
// SchemaV7 keeps its own `FitnessGoal` snapshot (pre-`racePriority`) so the V7 checksum stays
// distinct from V8's — see SchemaV7.swift + CLAUDE.md §2.1.

enum SchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Symptom.self,
         DailyReadiness.self,
         WorkoutSample.self,
         FitnessGoal.self,
         ActivityRecord.self,
         UserPreference.self,
         UserConfiguration.self,
         CoachContextCache.self,
         WorkoutChatEntry.self,
         WorkoutChatFact.self]
    }
}
