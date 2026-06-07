import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Epic #55: file-backed test of the SwiftData V4 → V5 migration.
///
/// V5 is a pure addition: `FitnessGoal` gets `eventDurationDays: Int?`. The stage
/// is `.lightweight` — SwiftData adds the column and existing records get `nil`.
///
/// Same safety-net role as the earlier migration tests: guarantees a populated V4
/// store migrates cleanly to V5 without the fallback in
/// `AIFitnessCoachApp.makeModelContainer` kicking in (= data-loss of local-only
/// `FitnessGoal` + `UserPreference`).
@MainActor
final class SchemaMigrationV4ToV5Tests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibecoach-migration-v4v5-\(UUID().uuidString).store")
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

    /// Builds a V4 container (no migration plan) and seeds test data. SwiftData stamps
    /// version 4.0.0 on the store file so the V5 init can trigger the lightweight stage.
    private func seedV4Store(seed: (ModelContext) throws -> Void) throws {
        let schema = Schema(versionedSchema: SchemaV4.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: config)
        try seed(container.mainContext)
        try container.mainContext.save()
    }

    /// Opens the same store with the V5 schema + AppMigrationPlan.
    private func openV5Store() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV5.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: config
        )
    }

    // MARK: - Tests

    func test_migration_preservesGoalsAndPreferences() throws {
        let goalDate = Date().addingTimeInterval(60 * 60 * 24 * 90)

        try seedV4Store { ctx in
            ctx.insert(FitnessGoal(title: "Marathon Rotterdam", targetDate: goalDate, sportCategory: .running))
            ctx.insert(UserPreference(preferenceText: "Voorkeur voor ochtendlopen"))
        }

        let container = try openV5Store()
        let goals = try container.mainContext.fetch(FetchDescriptor<FitnessGoal>())
        let prefs = try container.mainContext.fetch(FetchDescriptor<UserPreference>())

        XCTAssertEqual(goals.count, 1, "FitnessGoal must survive the migration")
        XCTAssertEqual(prefs.count, 1, "UserPreference must survive the migration")
        XCTAssertEqual(goals.first?.title, "Marathon Rotterdam")
    }

    func test_migration_existingGoal_getsNilEventDuration() throws {
        let id = UUID()
        try seedV4Store { ctx in
            ctx.insert(FitnessGoal(id: id, title: "Pre-Epic-55 doel",
                                   targetDate: Date().addingTimeInterval(86_400 * 30)))
        }

        let container = try openV5Store()
        let all = try container.mainContext.fetch(FetchDescriptor<FitnessGoal>())
        guard let goal = all.first(where: { $0.id == id }) else {
            return XCTFail("Seeded goal not found after migration")
        }
        XCTAssertNil(goal.eventDurationDays, "Pure-addition field must be nil for pre-V5 records")
        XCTAssertEqual(goal.resolvedEventDurationDays, 1, "nil duration behaves as single-day")
    }

    func test_migration_canWriteEventDurationAfterMigration() throws {
        try seedV4Store { ctx in
            ctx.insert(FitnessGoal(title: "Arnhem → Karlsruhe",
                                   targetDate: Date().addingTimeInterval(86_400 * 14),
                                   format: .multiDayStage, intent: .completion))
        }

        let container = try openV5Store()
        let all = try container.mainContext.fetch(FetchDescriptor<FitnessGoal>())
        guard let goal = all.first else { return XCTFail("Expected a goal") }

        goal.eventDurationDays = 5
        try container.mainContext.save()

        let reopened = try openV5Store()
        let reloaded = try reopened.mainContext.fetch(FetchDescriptor<FitnessGoal>())
        XCTAssertEqual(reloaded.first?.eventDurationDays, 5)
        XCTAssertEqual(reloaded.first?.resolvedEventDurationDays, 5)
    }
}
