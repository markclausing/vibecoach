import XCTest
import SwiftData
@testable import AIFitnessCoach

/// End-to-end test van de SwiftData V1 → V2 migratie via een file-backed store.
///
/// Dit verifieert drie kritieke paden zonder een echt device te raken:
///   1. `Symptom.bodyAreaRaw: String` (V1) → `Symptom.bodyArea: BodyArea` (V2) blijft
///      semantisch hetzelfde (de string-rawValue koppelt op de enum-case).
///   2. `DailyReadiness` met duplicaten op dezelfde `startOfDay(date)` wordt gededupeerd
///      tot één record (hoogste `readinessScore` wint).
///   3. `WorkoutSample` met duplicaten op `(workoutUUID, timestamp)` wordt gededupeerd
///      tot één record (rijkste record — meeste niet-nil meetvelden — wint).
///
/// In-memory stores werken hier niet: SwiftData laat een fresh in-memory container
/// niet via `SchemaMigrationPlan` lopen omdat er geen V1-store-bestand bestaat. We
/// gebruiken daarom een tijdelijk file-store-pad in `FileManager.default.temporaryDirectory`.
@MainActor
final class SchemaMigrationV1ToV2Tests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        // Unique pad per test-run zodat parallelle tests of stale state niet kruisen.
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibecoach-migration-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        // Ruim het tijdelijke store-bestand op (en bijbehorende SQLite WAL/SHM).
        let parent = storeURL.deletingLastPathComponent()
        let stem   = storeURL.lastPathComponent
        let candidates = ["", "-wal", "-shm"].map { parent.appendingPathComponent(stem + $0) }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        storeURL = nil
    }

    // MARK: - V1 seed helpers

    /// Bouwt een V1-container (zonder migratie-plan) en seeded de testdata.
    private func seedV1Store(seed: (ModelContext) throws -> Void) throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: config)
        try seed(container.mainContext)
        try container.mainContext.save()
    }

    /// Opent dezelfde store met V2 schema + migratie-plan.
    private func openV2Store() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: config
        )
    }

    // MARK: - Symptom: bodyAreaRaw → bodyArea

    func test_migration_symptomBodyAreaString_mapsToBodyAreaEnum() throws {
        try seedV1Store { ctx in
            ctx.insert(SchemaV1.Symptom(bodyAreaRaw: "Kuit", severity: 6, date: Date()))
            ctx.insert(SchemaV1.Symptom(bodyAreaRaw: "Knie", severity: 3, date: Date()))
        }

        let container = try openV2Store()
        let all = try container.mainContext.fetch(FetchDescriptor<Symptom>())
        XCTAssertEqual(all.count, 2)

        let areas = Set(all.map(\.bodyArea))
        XCTAssertTrue(areas.contains(.calf))
        XCTAssertTrue(areas.contains(.knee))
    }

    // MARK: - DailyReadiness: dedupe op date

    func test_migration_dailyReadinessDuplicatesForSameDay_keepHighestScore() throws {
        let day = Calendar.current.startOfDay(for: Date())

        try seedV1Store { ctx in
            // Drie records voor dezelfde dag met verschillende scores
            ctx.insert(SchemaV1.DailyReadiness(date: day, sleepHours: 7.0, hrv: 50, readinessScore: 60))
            ctx.insert(SchemaV1.DailyReadiness(date: day, sleepHours: 7.5, hrv: 55, readinessScore: 85))
            ctx.insert(SchemaV1.DailyReadiness(date: day, sleepHours: 6.5, hrv: 45, readinessScore: 40))
            // En een record voor een andere dag — moet onaangeroerd blijven
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: day)!
            ctx.insert(SchemaV1.DailyReadiness(date: yesterday, sleepHours: 8.0, hrv: 60, readinessScore: 90))
        }

        let container = try openV2Store()
        let all = try container.mainContext.fetch(FetchDescriptor<DailyReadiness>())

        XCTAssertEqual(all.count, 2, "Drie duplicates moeten gededupeerd worden tot één per dag.")

        // Het record voor `day` moet de hoogste score hebben (85).
        let todayRecord = all.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
        XCTAssertEqual(todayRecord?.readinessScore, 85)
    }

    // MARK: - WorkoutSample: dedupe op (workoutUUID, timestamp)

    func test_migration_workoutSampleDuplicates_keepRichestRecord() throws {
        let workoutUUID = UUID()
        let ts = Date()

        try seedV1Store { ctx in
            // Drie samples voor dezelfde (uuid, ts), met verschillende rijkdom
            ctx.insert(SchemaV1.WorkoutSample(workoutUUID: workoutUUID, timestamp: ts,
                                              heartRate: 140))                          // 1 niet-nil
            ctx.insert(SchemaV1.WorkoutSample(workoutUUID: workoutUUID, timestamp: ts,
                                              heartRate: 142, power: 220, cadence: 88)) // 3 niet-nil
            ctx.insert(SchemaV1.WorkoutSample(workoutUUID: workoutUUID, timestamp: ts,
                                              heartRate: 141, power: 215))              // 2 niet-nil
            // En een unieke sample (andere timestamp) — blijft staan
            let later = ts.addingTimeInterval(5)
            ctx.insert(SchemaV1.WorkoutSample(workoutUUID: workoutUUID, timestamp: later,
                                              heartRate: 145))
        }

        let container = try openV2Store()
        let all = try container.mainContext.fetch(FetchDescriptor<WorkoutSample>())

        XCTAssertEqual(all.count, 2, "3 duplicates moeten gededupeerd worden tot 1; de unieke sample blijft.")

        let kept = all.first { abs($0.timestamp.timeIntervalSince(ts)) < 0.5 }
        XCTAssertNotNil(kept)
        XCTAssertEqual(kept?.heartRate, 142)
        XCTAssertEqual(kept?.power, 220)
        XCTAssertEqual(kept?.cadence, 88)
    }

    // MARK: - Smoke: lege V1-store opent zonder fouten in V2

    func test_migration_emptyV1Store_opensInV2WithoutError() throws {
        try seedV1Store { _ in /* no seed */ }

        XCTAssertNoThrow(try openV2Store(), "Lege V1-store moet zonder migratie-fouten naar V2 kunnen.")
    }

    // MARK: - Hard-constraint check: V2 weigert een nieuwe duplicate na migratie

    func test_v2_rejectsDuplicateDailyReadinessOnSameDay() throws {
        let day = Calendar.current.startOfDay(for: Date())
        try seedV1Store { ctx in
            ctx.insert(SchemaV1.DailyReadiness(date: day, sleepHours: 7, hrv: 50, readinessScore: 70))
        }

        let container = try openV2Store()
        let ctx = container.mainContext

        // Probeer een tweede record voor dezelfde dag toe te voegen — `@Attribute(.unique)` op `date`
        // moet de tweede insert blokkeren via upsert (SwiftData behandelt unique-constraint
        // collisions als upsert-on-id, dus we verwachten er nog steeds 1 record).
        ctx.insert(DailyReadiness(date: day, sleepHours: 7.5, hrv: 60, readinessScore: 80))
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<DailyReadiness>())
        XCTAssertEqual(all.count, 1, "Unique-constraint op `date` moet één record per dag afdwingen.")
    }
}
