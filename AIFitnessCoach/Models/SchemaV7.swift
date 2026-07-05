import Foundation
import SwiftData

// MARK: - SchemaV7: Epic #70 — per-workout chat with local memory

// Difference from SchemaV6: adds `WorkoutChatEntry` (the persisted per-workout chat
// thread) and `WorkoutChatFact` (durable facts the coach distils from that chat).
// Two new @Models are a pure addition — `MigrationStage.lightweight` from V6 to V7
// is sufficient (SwiftData creates the new tables; no existing rows are touched).
//
// Per CLAUDE.md §2.1: every @Model change requires a schema bump, including pure
// additions (the May 2026 incident proves lightweight inference is not enough).

enum SchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)

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
