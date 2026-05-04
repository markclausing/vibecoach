import Foundation
import SwiftData

// MARK: - SchemaV1: Pre-tech-debt-audit baseline (mei 2026)
//
// Dit is een SNAPSHOT van het oude schema. De nested types `Symptom`,
// `DailyReadiness` en `WorkoutSample` heten doelbewust hetzelfde als de
// live (V2) global types — SwiftData gebruikt de UNQUALIFIED type-naam
// als entity-naam. Twee `@Model class Symptom` in verschillende
// namespaces zijn voor Swift zelf prima (eigen namespace) en voor
// SwiftData blijft het entity-naam "Symptom" — onderscheiden via
// `versionIdentifier`.
//
// De live types staan in `Models/Symptom.swift` etc. (V2-vorm).
// SchemaV1 wordt alleen door `AppMigrationPlan.migrateV1toV2` gelezen
// om bestaande V1-stores te kunnen inlezen tijdens de migratie.
//
// V1 → V2 wijzigingen die deze migratie afdekt:
//   1. `Symptom.bodyAreaRaw: String` → `Symptom.bodyArea: BodyArea` (rename + type-veiliger;
//      `@Attribute(originalName:)` op de live class koppelt de oude kolom).
//   2. `DailyReadiness.date` krijgt `@Attribute(.unique)`. Bestaande duplicates worden in
//      `willMigrate` gededupeerd op de hoogste `readinessScore`.
//   3. `WorkoutSample` krijgt `#Unique<>([\.workoutUUID, \.timestamp])` en `#Index` op
//      `workoutUUID`. Bestaande duplicates worden in `willMigrate` gededupeerd op behoud
//      van het record met de meeste niet-nil velden (rijkste record wint).

enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Self.Symptom.self,
         Self.DailyReadiness.self,
         Self.WorkoutSample.self,
         FitnessGoal.self,
         ActivityRecord.self,
         UserPreference.self,
         UserConfiguration.self]
    }

    /// V1: `bodyAreaRaw: String` (geen enum-mapping op DB-niveau).
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

    /// V1: `date` zonder `@Attribute(.unique)`. Race-conditions tussen Engine A en B konden
    /// dubbele records aanmaken; de `willMigrate`-stap dedupeert op `startOfDay(date)`.
    @Model
    final class DailyReadiness {
        var date: Date
        var sleepHours: Double
        var hrv: Double
        var readinessScore: Int

        var deepSleepMinutes: Int = 0
        var remSleepMinutes: Int  = 0
        var coreSleepMinutes: Int = 0
        var restingHeartRate: Double? = nil

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

    /// V1: geen `#Unique`, geen `#Index`. Idempotente upsert was service-zijdig (Epic 32),
    /// maar zonder DB-zijdige garantie konden parallelle ingest-paden duplicates creëren.
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
