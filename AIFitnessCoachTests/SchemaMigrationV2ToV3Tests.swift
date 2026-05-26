import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Epic #49: file-backed test van de SwiftData V2 → V3 migratie.
///
/// V3 is een pure addition: `ActivityRecord` krijgt `temperatureCelsius` en
/// `humidityPercent` (Optional<Double>). De migratie-stage is `.lightweight`
/// — SwiftData voegt de kolommen toe en bestaande records krijgen `nil`.
///
/// Dit test was niet zozeer voor de **data**-conversie (er is geen) maar voor
/// de **container-init-stabiliteit**: zonder schema-bump faalde de init op een
/// bestaande V2-store, met catastrofale data-loss als gevolg (mei 2026 incident,
/// `FitnessGoal` + `UserPreference` werden gewist door de fallback in
/// `AIFitnessCoachApp.makeModelContainer`). Deze test borgt dat een populated
/// V2-store schoon migreert naar V3 zonder dat de fallback aanslaat.
@MainActor
final class SchemaMigrationV2ToV3Tests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibecoach-migration-v2v3-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        let parent = storeURL.deletingLastPathComponent()
        let stem   = storeURL.lastPathComponent
        let candidates = ["", "-wal", "-shm"].map { parent.appendingPathComponent(stem + $0) }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        storeURL = nil
    }

    /// Bouwt een V2-container (zonder migratie-plan) en seeded testdata. SwiftData
    /// stempelt de versie-identifier 2.0.0 op het store-bestand zodat de V3-init
    /// de migratie-stage kan triggeren.
    private func seedV2Store(seed: (ModelContext) throws -> Void) throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: config)
        try seed(container.mainContext)
        try container.mainContext.save()
    }

    /// Opent dezelfde store met V3-schema + AppMigrationPlan (lightweight V2→V3 stage).
    private func openV3Store() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV3.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: config
        )
    }

    // MARK: - Tests

    func test_migration_preservesAllRecordsAcrossModels() throws {
        let goalDate = Date().addingTimeInterval(60 * 60 * 24 * 90)

        try seedV2Store { ctx in
            // Eén goal — dit was het kritieke verlies-pad in het mei-2026 incident.
            ctx.insert(FitnessGoal(
                title: "Marathon Rotterdam",
                targetDate: goalDate,
                sportCategory: .running
            ))

            // UserPreference — lokaal-only, wordt gewist als de store-init faalt.
            ctx.insert(UserPreference(preferenceText: "Voorkeur voor ochtendlopen"))

            // Epic #52: V2-snapshot van ActivityRecord — sinds V3 ook een snapshot
            // heeft (Epic #52, GPS-coords als pure addition op V4), kan de live
            // class niet meer als shorthand worden gebruikt in seed/fetch van een
            // V2- of V3-schema-store. Gebruik altijd het schema-specifieke type.
            ctx.insert(SchemaV2.ActivityRecord(
                id: UUID().uuidString,
                name: "Lange duurloop",
                distance: 32_000,
                movingTime: 9000,
                averageHeartrate: 152,
                sportCategory: .running,
                startDate: Date()
            ))
        }

        let container = try openV3Store()
        let goals = try container.mainContext.fetch(FetchDescriptor<FitnessGoal>())
        let prefs = try container.mainContext.fetch(FetchDescriptor<UserPreference>())
        let activities = try container.mainContext.fetch(FetchDescriptor<SchemaV3.ActivityRecord>())

        XCTAssertEqual(goals.count, 1, "FitnessGoal moet de migratie overleven")
        XCTAssertEqual(prefs.count, 1, "UserPreference moet de migratie overleven")
        XCTAssertEqual(activities.count, 1, "ActivityRecord moet de migratie overleven")
        XCTAssertEqual(goals.first?.title, "Marathon Rotterdam")
    }

    func test_migration_existingActivityRecord_getsNilWeatherFields() throws {
        let activityID = UUID().uuidString

        try seedV2Store { ctx in
            ctx.insert(SchemaV2.ActivityRecord(
                id: activityID,
                name: "Pre-Epic-49 rit",
                distance: 50_000,
                movingTime: 7200,
                averageHeartrate: 145,
                sportCategory: .cycling,
                startDate: Date()
            ))
        }

        let container = try openV3Store()
        let all = try container.mainContext.fetch(FetchDescriptor<SchemaV3.ActivityRecord>())
        guard let record = all.first(where: { $0.id == activityID }) else {
            return XCTFail("Geseedde record niet gevonden na migratie")
        }
        XCTAssertNil(record.temperatureCelsius, "Pure-addition velden moeten nil zijn voor pre-V3-records")
        XCTAssertNil(record.humidityPercent)
    }

    func test_migration_canWriteWeatherFieldsAfterMigration() throws {
        try seedV2Store { ctx in
            ctx.insert(SchemaV2.ActivityRecord(
                id: UUID().uuidString,
                name: "Test rit",
                distance: 10_000,
                movingTime: 1800,
                averageHeartrate: 140,
                sportCategory: .cycling,
                startDate: Date()
            ))
        }

        let container = try openV3Store()
        let all = try container.mainContext.fetch(FetchDescriptor<SchemaV3.ActivityRecord>())
        guard let record = all.first else { return XCTFail("Verwacht record") }

        // Schrijf naar de nieuwe velden — bewijst dat de kolommen daadwerkelijk
        // zijn toegevoegd door de lightweight migratie.
        record.temperatureCelsius = 28.0
        record.humidityPercent = 65.0
        try container.mainContext.save()

        let reopened = try openV3Store()
        let reloaded = try reopened.mainContext.fetch(FetchDescriptor<SchemaV3.ActivityRecord>())
        XCTAssertEqual(reloaded.first?.temperatureCelsius, 28.0)
        XCTAssertEqual(reloaded.first?.humidityPercent, 65.0)
    }
}
