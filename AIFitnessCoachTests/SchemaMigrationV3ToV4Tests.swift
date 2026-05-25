import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Epic #52: file-backed test van de SwiftData V3 → V4 migratie.
///
/// V4 is een pure addition: `ActivityRecord` krijgt `startLatitude` en
/// `startLongitude` (Optional<Double>). De migratie-stage is `.lightweight`
/// — SwiftData voegt de kolommen toe en bestaande records krijgen `nil`.
///
/// Identieke vangnet-rol als de V2→V3-tests: borgt dat een populated V3-store
/// schoon migreert naar V4 zonder dat de fallback in
/// `AIFitnessCoachApp.makeModelContainer` aanslaat (= data-loss van
/// lokaal-only `FitnessGoal` + `UserPreference`).
@MainActor
final class SchemaMigrationV3ToV4Tests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibecoach-migration-v3v4-\(UUID().uuidString).store")
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

    /// Bouwt een V3-container (zonder migratie-plan vanaf eerdere versies) en
    /// seeded testdata. SwiftData stempelt versie 3.0.0 op het store-bestand
    /// zodat de V4-init de lightweight stage kan triggeren.
    private func seedV3Store(seed: (ModelContext) throws -> Void) throws {
        let schema = Schema(versionedSchema: SchemaV3.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: config)
        try seed(container.mainContext)
        try container.mainContext.save()
    }

    /// Opent dezelfde store met V4-schema + AppMigrationPlan.
    private func openV4Store() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV4.self)
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

        try seedV3Store { ctx in
            ctx.insert(FitnessGoal(
                title: "Marathon Rotterdam",
                targetDate: goalDate,
                sportCategory: .running
            ))
            ctx.insert(UserPreference(preferenceText: "Voorkeur voor ochtendlopen"))
            ctx.insert(ActivityRecord(
                id: UUID().uuidString,
                name: "Lange duurloop",
                distance: 32_000,
                movingTime: 9000,
                averageHeartrate: 152,
                sportCategory: .running,
                startDate: Date(),
                temperatureCelsius: 18,
                humidityPercent: 72
            ))
        }

        let container = try openV4Store()
        let goals = try container.mainContext.fetch(FetchDescriptor<FitnessGoal>())
        let prefs = try container.mainContext.fetch(FetchDescriptor<UserPreference>())
        let activities = try container.mainContext.fetch(FetchDescriptor<ActivityRecord>())

        XCTAssertEqual(goals.count, 1, "FitnessGoal moet de migratie overleven")
        XCTAssertEqual(prefs.count, 1, "UserPreference moet de migratie overleven")
        XCTAssertEqual(activities.count, 1, "ActivityRecord moet de migratie overleven")
        XCTAssertEqual(activities.first?.temperatureCelsius, 18, "V3-velden moeten bewaard blijven")
    }

    func test_migration_existingActivityRecord_getsNilCoordsFields() throws {
        let activityID = UUID().uuidString

        try seedV3Store { ctx in
            ctx.insert(ActivityRecord(
                id: activityID,
                name: "Pre-Epic-52 rit",
                distance: 50_000,
                movingTime: 7200,
                averageHeartrate: 145,
                sportCategory: .cycling,
                startDate: Date()
            ))
        }

        let container = try openV4Store()
        let all = try container.mainContext.fetch(FetchDescriptor<ActivityRecord>())
        guard let record = all.first(where: { $0.id == activityID }) else {
            return XCTFail("Geseedde record niet gevonden na migratie")
        }
        XCTAssertNil(record.startLatitude, "Pure-addition velden moeten nil zijn voor pre-V4-records")
        XCTAssertNil(record.startLongitude)
    }

    func test_migration_canWriteCoordsAfterMigration() throws {
        try seedV3Store { ctx in
            ctx.insert(ActivityRecord(
                id: UUID().uuidString,
                name: "Test rit",
                distance: 10_000,
                movingTime: 1800,
                averageHeartrate: 140,
                sportCategory: .cycling,
                startDate: Date()
            ))
        }

        let container = try openV4Store()
        let all = try container.mainContext.fetch(FetchDescriptor<ActivityRecord>())
        guard let record = all.first else { return XCTFail("Verwacht record") }

        record.startLatitude = 52.37
        record.startLongitude = 4.89
        try container.mainContext.save()

        let reopened = try openV4Store()
        let reloaded = try reopened.mainContext.fetch(FetchDescriptor<ActivityRecord>())
        XCTAssertEqual(reloaded.first?.startLatitude, 52.37)
        XCTAssertEqual(reloaded.first?.startLongitude, 4.89)
    }
}
