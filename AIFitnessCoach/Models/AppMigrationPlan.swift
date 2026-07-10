import Foundation
import SwiftData

// MARK: - SwiftData Migration Plan (May 2026 tech-debt audit)
//
// Chained migrations: SchemaV1 → SchemaV2 → SchemaV3.
//
// V2 adds two kinds of constraints that sit on a populated DB field:
//   - `@Attribute(.unique)` on `DailyReadiness.date`
//   - `#Unique<>([\.workoutUUID, \.timestamp])` on `WorkoutSample`
// If the existing store already contains duplicates, the migration fails (a constraint
// violation on the first V2 insert). The `willMigrate` step therefore dedupes in V1 form
// before the schema centre of gravity shifts to V2.
//
// `Symptom.bodyAreaRaw: String` → `Symptom.bodyArea: BodyArea` is a rename plus a
// type conversion. SwiftData's `@Attribute(originalName:)` can handle a rename that
// preserves the type, but not the implicit String → enum mapping. We therefore capture
// the V1 strings in `willMigrate`, delete the V1 records, and re-insert them as V2 records
// in `didMigrate`. (Symptom has no foreign-key relationships — UUID regeneration is OK.)
//
// V3 adds two optional fields to `ActivityRecord` (Epic #49 — weather metadata):
// `temperatureCelsius` and `humidityPercent`. A pure addition, so `MigrationStage.lightweight`
// is sufficient. The reason to bump anyway: without a schema version SwiftData sees a
// hash mismatch on SchemaV2 and the fallback in `makeModelContainer` then wipes the whole
// store. See CLAUDE.md §2.1 — every `@Model` change requires a schema bump.
//
// V4 adds two optional fields to `ActivityRecord` (Epic #52 — GPS start coords):
// `startLatitude` and `startLongitude`. A pure addition, also `.lightweight`. Needed to be
// able to fetch the hourly weather range at the Coach call without querying the source API
// again.

enum AppMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6, migrateV6toV7]
    }

    // MARK: - V6 → V7: pure addition (WorkoutChatEntry + WorkoutChatFact — Epic #70)

    /// Epic #70: adds the per-workout chat thread (`WorkoutChatEntry`) and the distilled
    /// facts (`WorkoutChatFact`) as new tables. Existing records are untouched.
    /// `.lightweight` is sufficient for new @Models with no changes to existing tables.
    static let migrateV6toV7 = MigrationStage.lightweight(
        fromVersion: SchemaV6.self,
        toVersion: SchemaV7.self
    )

    // MARK: - V5 → V6: pure addition (CoachContextCache — PHI prompt-context in protected storage)

    /// Story 61.7: adds `CoachContextCache` (new table). Existing records are untouched.
    /// `.lightweight` is sufficient for a new @Model with no changes to existing tables.
    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: SchemaV5.self,
        toVersion: SchemaV6.self
    )

    // MARK: - V4 → V5: pure addition (multi-day event duration on FitnessGoal)

    /// Epic #55: pure addition of `FitnessGoal.eventDurationDays: Int?`. Existing
    /// records get `nil` (= single-day behaviour). `.lightweight` is sufficient.
    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: SchemaV4.self,
        toVersion: SchemaV5.self
    )

    // MARK: - V2 → V3: pure addition (weather metadata on ActivityRecord)

    /// `MigrationStage.lightweight` is sufficient for pure additions of optional
    /// fields — SwiftData adds the columns, existing records get `nil`.
    /// No `willMigrate`/`didMigrate` needed.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )

    // MARK: - V3 → V4: pure addition (GPS coords on ActivityRecord)

    /// Pure addition of `startLatitude` + `startLongitude`. Existing records
    /// get `nil` — for HK-only rides the Coach analysis falls back to the
    /// snapshot in `temperatureCelsius`/`humidityPercent`.
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SchemaV3.self,
        toVersion: SchemaV4.self
    )

    // MARK: - V1 → V2: dedupe + symptoms rebuild + schema flip

    /// Temporary buffer for Symptom data between `willMigrate` (V1) and `didMigrate` (V2).
    /// Cleared after every successful migration. SwiftData guarantees that
    /// `willMigrate` and `didMigrate` run sequentially on the same thread, so this is
    /// thread-safe within one migration run.
    private struct PendingSymptom {
        let bodyAreaRaw: String
        let severity: Int
        let date: Date
    }
    nonisolated(unsafe) private static var pendingSymptoms: [PendingSymptom] = []

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: { context in
            try captureAndDeleteV1Symptoms(in: context)
            try dedupeDailyReadiness(in: context)
            try dedupeWorkoutSamples(in: context)
            try context.save()
        },
        didMigrate: { context in
            try restoreSymptomsAsV2(in: context)
            try context.save()
            pendingSymptoms = []
        }
    )

    // MARK: - Symptom rebuild

    /// Capture V1 Symptom data in a Swift-side buffer and delete the V1 records.
    /// After the schema flip they are recreated in `didMigrate` as V2 records
    /// with the type-safe `BodyArea` enum.
    private static func captureAndDeleteV1Symptoms(in context: ModelContext) throws {
        let v1All = try context.fetch(FetchDescriptor<SchemaV1.Symptom>())
        pendingSymptoms = v1All.map {
            PendingSymptom(bodyAreaRaw: $0.bodyAreaRaw, severity: $0.severity, date: $0.date)
        }
        for v1 in v1All {
            context.delete(v1)
        }
    }

    /// Restore the captured V1 data as V2 records.
    /// Unknown rawValues fall back safely to `.calf` (consistent with the old
    /// computed-property behaviour that used the same fallback).
    private static func restoreSymptomsAsV2(in context: ModelContext) throws {
        for s in pendingSymptoms {
            let area = BodyArea(rawValue: s.bodyAreaRaw) ?? .calf
            context.insert(Symptom(bodyArea: area, severity: s.severity, date: s.date))
        }
    }

    // MARK: - Dedupe helpers (V1 types)

    /// `DailyReadiness`: groups by `startOfDay(date)`, keeps the record with the
    /// highest `readinessScore` (consistent with the ReadinessService runtime
    /// upsert strategy) and deletes the rest.
    private static func dedupeDailyReadiness(in context: ModelContext) throws {
        let fetch = FetchDescriptor<SchemaV1.DailyReadiness>()
        let all = try context.fetch(fetch)
        guard !all.isEmpty else { return }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: all) { calendar.startOfDay(for: $0.date) }

        for (_, recordsForDay) in groups where recordsForDay.count > 1 {
            // Highest score wins; tie-break on most recent write order.
            let sorted = recordsForDay.sorted { lhs, rhs in
                if lhs.readinessScore != rhs.readinessScore {
                    return lhs.readinessScore > rhs.readinessScore
                }
                return lhs.date > rhs.date
            }
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
            }
        }
    }

    /// `WorkoutSample`: groups by `(workoutUUID, timestamp)`, keeps the record
    /// with the most non-nil fields (richest record wins) and deletes the rest.
    /// Tie-break on insert order — takes the last-added record (most recent data).
    private static func dedupeWorkoutSamples(in context: ModelContext) throws {
        let fetch = FetchDescriptor<SchemaV1.WorkoutSample>()
        let all = try context.fetch(fetch)
        guard !all.isEmpty else { return }

        struct Key: Hashable {
            let uuid: UUID
            let ts: TimeInterval
        }

        let groups = Dictionary(grouping: all) {
            Key(uuid: $0.workoutUUID, ts: $0.timestamp.timeIntervalSinceReferenceDate)
        }

        for (_, samples) in groups where samples.count > 1 {
            let sorted = samples.sorted { lhs, rhs in
                let lhsRichness = nonNilCount(in: lhs)
                let rhsRichness = nonNilCount(in: rhs)
                if lhsRichness != rhsRichness { return lhsRichness > rhsRichness }
                return lhs.timestamp > rhs.timestamp
            }
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
            }
        }
    }

    /// Counts how many optional measurement fields are populated — more = "richer" record.
    private static func nonNilCount(in s: SchemaV1.WorkoutSample) -> Int {
        var n = 0
        if s.heartRate != nil { n += 1 }
        if s.speed     != nil { n += 1 }
        if s.power     != nil { n += 1 }
        if s.cadence   != nil { n += 1 }
        if s.distance  != nil { n += 1 }
        return n
    }
}
