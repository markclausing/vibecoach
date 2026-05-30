import Foundation
import SwiftData

// MARK: - SchemaV4: Epic #52 — GPS start coordinates on ActivityRecord
//
// Difference from SchemaV3: `ActivityRecord` gets two new optional fields,
// `startLatitude: Double?` and `startLongitude: Double?`. A pure addition, so
// `MigrationStage.lightweight(fromVersion: V3, toVersion: V4)` is sufficient.
// Existing records get `nil` on both fields — for records without coords
// the Coach analysis keeps falling back to the snapshot in `temperatureCelsius`/
// `humidityPercent`.
//
// **Why the bump?** Epic #52 adds the hourly weather range (peak temp, avg humidity)
// over [start, end] to the Coach prompt. For the range fetch we need GPS;
// previously lat/lng only lived on `StravaActivity` (not @Model) and was therefore
// only available during ingest. By persisting the coords on `ActivityRecord` we can
// reuse them later — at a Coach call on an arbitrary workout — without querying the
// source API.
//
// Per CLAUDE.md §2.1: every `@Model` change requires a schema bump, including
// pure additions. SwiftData's lightweight inference behaves differently with an
// explicit `migrationPlan` — without a version bump the container sees a hash
// mismatch on V3 and falls back to a fresh DB (data loss).
//
// Like V3, this references the live runtime types directly — no separate
// V4 class definitions needed for a pure addition.

enum SchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

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
