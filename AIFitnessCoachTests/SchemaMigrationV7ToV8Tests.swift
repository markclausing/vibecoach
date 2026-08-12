import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Epic #73 story 73.2: file-backed test of the SwiftData V7 → V8 migration.
///
/// V8 is a pure addition: `FitnessGoal` gets `racePriority: RacePriority?` (A/B/C priority for the
/// unified macrocycle). The migration stage is `.lightweight` — SwiftData adds the column and
/// existing records get `nil` (= unset → MacrocyclePlanner derives priority from dates).
///
/// Safety-net role (per CLAUDE.md §2.1): verifies that a populated V7 store migrates cleanly to V8
/// without the fallback in `AIFitnessCoachApp.makeModelContainer` kicking in (= local-only data
/// loss for `FitnessGoal` + `UserPreference`), and that the new field is writable after migration.
@MainActor
final class SchemaMigrationV7ToV8Tests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibecoach-migration-v7v8-\(UUID().uuidString).store")
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

    /// Builds a V7 container (no migration plan) and seeds test data.
    private func seedV7Store(seed: (ModelContext) throws -> Void) throws {
        let schema = Schema(versionedSchema: SchemaV7.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: config)
        try seed(container.mainContext)
        try container.mainContext.save()
    }

    /// Opens the same store with the V8 schema + AppMigrationPlan.
    private func openV8Store() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV8.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: config
        )
    }

    // MARK: - Tests

    func test_migration_preservesGoalsPreferencesAndActivities() throws {
        let goalDate = Date().addingTimeInterval(60 * 60 * 24 * 90)

        try seedV7Store { ctx in
            ctx.insert(FitnessGoal(title: "Marathon Amsterdam", targetDate: goalDate, sportCategory: .running))
            ctx.insert(UserPreference(preferenceText: "Voorkeur voor avondtraining"))
            ctx.insert(ActivityRecord(id: "9876543210",
                                      name: "Zondagrit",
                                      distance: 42_000,
                                      movingTime: 5_400,
                                      averageHeartrate: 145,
                                      sportCategory: .cycling,
                                      startDate: Date()))
        }

        let container = try openV8Store()
        let goals      = try container.mainContext.fetch(FetchDescriptor<FitnessGoal>())
        let prefs      = try container.mainContext.fetch(FetchDescriptor<UserPreference>())
        let activities = try container.mainContext.fetch(FetchDescriptor<ActivityRecord>())

        XCTAssertEqual(goals.count, 1, "FitnessGoal must survive V7→V8 migration")
        XCTAssertEqual(prefs.count, 1, "UserPreference must survive V7→V8 migration")
        XCTAssertEqual(activities.count, 1, "ActivityRecord must survive V7→V8 migration")
        XCTAssertEqual(goals.first?.title, "Marathon Amsterdam")
        // A pre-existing goal has no priority after the pure-addition migration.
        XCTAssertNil(goals.first?.racePriority, "Existing goals get nil racePriority after migration")
    }

    func test_migration_racePriorityIsWritableAndPersistsAfterMigration() throws {
        try seedV7Store { ctx in
            ctx.insert(FitnessGoal(title: "Halve marathon Haarlem",
                                   targetDate: Date().addingTimeInterval(86_400 * 60)))
        }

        // After migration the new column exists — set it on the existing record.
        let container = try openV8Store()
        let goal = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<FitnessGoal>()).first)
        goal.racePriority = .b
        try container.mainContext.save()

        // Reopen and verify the value persisted with its typed enum intact.
        let reopened = try openV8Store()
        let reloaded = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<FitnessGoal>()).first)
        XCTAssertEqual(reloaded.racePriority, .b, "racePriority must persist across a reopen")
    }

    func test_migration_emptyV7Store_opensCleanly() throws {
        try seedV7Store { _ in }

        let container = try openV8Store()
        let goals = try container.mainContext.fetch(FetchDescriptor<FitnessGoal>())
        XCTAssertTrue(goals.isEmpty)
    }
}
