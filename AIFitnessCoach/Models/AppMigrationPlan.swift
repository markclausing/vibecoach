import Foundation
import SwiftData

// MARK: - SwiftData Migration Plan (mei 2026 tech-debt audit)
//
// Geketende migraties: SchemaV1 → SchemaV2.
//
// V2 voegt twee soorten constraints toe die op een vol DB-veld zitten:
//   - `@Attribute(.unique)` op `DailyReadiness.date`
//   - `#Unique<>([\.workoutUUID, \.timestamp])` op `WorkoutSample`
// Als de bestaande store al duplicates bevat, faalt de migratie (constraint-violation
// op de eerste insert van V2). De `willMigrate`-stap dedupeert dáárom in V1-vorm
// vóórdat het schema-zwaartepunt naar V2 verschuift.
//
// `Symptom.bodyAreaRaw: String` → `Symptom.bodyArea: BodyArea` is een rename plus
// type-conversie. SwiftData's `@Attribute(originalName:)` kan een rename met behoud
// van type aan, maar niet de impliciete String → enum-mapping. We capturen daarom de
// V1-strings in `willMigrate`, deleten de V1-records, en re-inserten ze als V2-records
// in `didMigrate`. (Symptom heeft géén foreign-key relaties — UUID-regeneratie is OK.)

enum AppMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    // MARK: - V1 → V2: dedupe + symptoms-rebuild + schema-flip

    /// Tijdelijke buffer voor Symptom-data tussen `willMigrate` (V1) en `didMigrate` (V2).
    /// Wordt na elke geslaagde migratie weer leeggemaakt. SwiftData garandeert dat
    /// `willMigrate` en `didMigrate` sequentieel op dezelfde thread lopen, dus dit is
    /// thread-safe binnen één migratie-run.
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

    // MARK: - Symptom-rebuild

    /// Capture V1-Symptom-data in een swift-side buffer en delete de V1-records.
    /// Na de schema-flip worden ze in `didMigrate` opnieuw aangemaakt als V2-records
    /// met de type-veilige `BodyArea`-enum.
    private static func captureAndDeleteV1Symptoms(in context: ModelContext) throws {
        let v1All = try context.fetch(FetchDescriptor<SchemaV1.Symptom>())
        pendingSymptoms = v1All.map {
            PendingSymptom(bodyAreaRaw: $0.bodyAreaRaw, severity: $0.severity, date: $0.date)
        }
        for v1 in v1All {
            context.delete(v1)
        }
    }

    /// Plaats de gecaptured V1-data terug als V2-records.
    /// Onbekende rawValues vallen veilig terug op `.calf` (consistent met het oude
    /// computed-property gedrag dat hetzelfde fallback gebruikte).
    private static func restoreSymptomsAsV2(in context: ModelContext) throws {
        for s in pendingSymptoms {
            let area = BodyArea(rawValue: s.bodyAreaRaw) ?? .calf
            context.insert(Symptom(bodyArea: area, severity: s.severity, date: s.date))
        }
    }

    // MARK: - Dedupe helpers (V1-types)

    /// `DailyReadiness`: groepeert op `startOfDay(date)`, behoudt het record met de
    /// hoogste `readinessScore` (consistent met de runtime upsert-strategie van de
    /// ReadinessService) en deletet de rest.
    private static func dedupeDailyReadiness(in context: ModelContext) throws {
        let fetch = FetchDescriptor<SchemaV1.DailyReadiness>()
        let all = try context.fetch(fetch)
        guard !all.isEmpty else { return }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: all) { calendar.startOfDay(for: $0.date) }

        for (_, recordsForDay) in groups where recordsForDay.count > 1 {
            // Hoogste score wint; tie-break op meest recente schrijf-volgorde.
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

    /// `WorkoutSample`: groepeert op `(workoutUUID, timestamp)`, behoudt het record
    /// met de meeste niet-nil velden (rijkste record wint) en deletet de rest.
    /// Tie-break op insert-volgorde — neemt het laatst toegevoegde record (recentste data).
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

    /// Telt hoeveel optionele meetvelden gevuld zijn — meer = "rijker" record.
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
