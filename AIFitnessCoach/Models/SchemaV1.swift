import Foundation
import SwiftData

// MARK: - SchemaV1: pre-tech-debt-audit baseline (May 2026)
//
// This is a SNAPSHOT of the old schema. The nested types `Symptom`,
// `DailyReadiness` and `WorkoutSample` are deliberately named the same as the
// live (V2) global types — SwiftData uses the UNQUALIFIED type name
// as the entity name. Two `@Model class Symptom` in different
// namespaces are fine for Swift itself (own namespace) and for
// SwiftData the entity name stays "Symptom" — distinguished via
// `versionIdentifier`.
//
// The live types live in `Models/Symptom.swift` etc. (V2 shape).
// SchemaV1 is only read by `AppMigrationPlan.migrateV1toV2`
// to be able to read existing V1 stores during the migration.
//
// V1 → V2 changes this migration covers:
//   1. `Symptom.bodyAreaRaw: String` → `Symptom.bodyArea: BodyArea` (rename + more type-safe;
//      `@Attribute(originalName:)` on the live class links the old column).
//   2. `DailyReadiness.date` gets `@Attribute(.unique)`. Existing duplicates are deduped in
//      `willMigrate` on the highest `readinessScore`.
//   3. `WorkoutSample` gets `#Unique<>([\.workoutUUID, \.timestamp])` and `#Index` on
//      `workoutUUID`. Existing duplicates are deduped in `willMigrate`, keeping
//      the record with the most non-nil fields (richest record wins).

enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Self.Symptom.self,
         Self.DailyReadiness.self,
         Self.WorkoutSample.self,
         SchemaV4.FitnessGoal.self,
         SchemaV2.ActivityRecord.self,
         UserPreference.self,
         UserConfiguration.self]
    }

    /// V1: `bodyAreaRaw: String` (no enum mapping at the DB level).
    @Model
    final class Symptom {
        @Attribute(.unique) var id: UUID
        var bodyAreaRaw: String
        var severity: Int
        var date: Date

        init(id: UUID = UUID(), bodyAreaRaw: String, severity: Int, date: Date) {
            self.id = id
            self.bodyAreaRaw = bodyAreaRaw
            self.severity = severity
            self.date = date
        }
    }

    /// V1: `date` without `@Attribute(.unique)`. Race conditions between Engine A and B could
    /// create duplicate records; the `willMigrate` step dedupes on `startOfDay(date)`.
    @Model
    final class DailyReadiness {
        var date: Date
        var sleepHours: Double
        var hrv: Double
        var readinessScore: Int

        var deepSleepMinutes: Int = 0
        var remSleepMinutes: Int  = 0
        var coreSleepMinutes: Int = 0
        var restingHeartRate: Double?

        init(date: Date, sleepHours: Double, hrv: Double, readinessScore: Int,
             deepSleepMinutes: Int = 0, remSleepMinutes: Int = 0, coreSleepMinutes: Int = 0,
             restingHeartRate: Double? = nil) {
            self.date              = date
            self.sleepHours        = sleepHours
            self.hrv               = hrv
            self.readinessScore    = readinessScore
            self.deepSleepMinutes  = deepSleepMinutes
            self.remSleepMinutes   = remSleepMinutes
            self.coreSleepMinutes  = coreSleepMinutes
            self.restingHeartRate  = restingHeartRate
        }
    }

    /// V1: no `#Unique`, no `#Index`. The idempotent upsert was service-side (Epic 32),
    /// but without a DB-side guarantee parallel ingest paths could create duplicates.
    @Model
    final class WorkoutSample {
        var workoutUUID: UUID
        var timestamp: Date
        var heartRate: Double?
        var speed: Double?
        var power: Double?
        var cadence: Double?
        var distance: Double?

        init(workoutUUID: UUID, timestamp: Date,
             heartRate: Double? = nil, speed: Double? = nil, power: Double? = nil,
             cadence: Double? = nil, distance: Double? = nil) {
            self.workoutUUID = workoutUUID
            self.timestamp = timestamp
            self.heartRate = heartRate
            self.speed = speed
            self.power = power
            self.cadence = cadence
            self.distance = distance
        }
    }
}
