import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Epic #70 story 70.1: file-backed test of the SwiftData V6 → V7 migration.
///
/// V7 is a pure addition: `WorkoutChatEntry` (per-workout chat thread) and
/// `WorkoutChatFact` (distilled facts) are added to the schema. The migration
/// stage is `.lightweight` — SwiftData creates the new tables and touches no
/// existing records.
///
/// Safety-net role (per CLAUDE.md §2.1): verifies that a populated V6 store migrates
/// cleanly to V7 without the fallback in `AIFitnessCoachApp.makeModelContainer` kicking
/// in (= local-only data loss for `FitnessGoal` + `UserPreference` — and from V7 on,
/// the workout chat itself).
@MainActor
final class SchemaMigrationV6ToV7Tests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibecoach-migration-v6v7-\(UUID().uuidString).store")
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

    /// Builds a V6 container (no migration plan) and seeds test data.
    private func seedV6Store(seed: (ModelContext) throws -> Void) throws {
        let schema = Schema(versionedSchema: SchemaV6.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: config)
        try seed(container.mainContext)
        try container.mainContext.save()
    }

    /// Opens the same store with the V7 schema + AppMigrationPlan.
    private func openV7Store() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV7.self)
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

        try seedV6Store { ctx in
            ctx.insert(FitnessGoal(title: "Triatlon Almere", targetDate: goalDate, sportCategory: .running))
            ctx.insert(UserPreference(preferenceText: "Voorkeur voor avondtraining"))
            ctx.insert(ActivityRecord(id: "9876543210",
                                      name: "Zondagrit",
                                      distance: 42_000,
                                      movingTime: 5_400,
                                      averageHeartrate: 145,
                                      sportCategory: .cycling,
                                      startDate: Date()))
        }

        let container = try openV7Store()
        let goals      = try container.mainContext.fetch(FetchDescriptor<FitnessGoal>())
        let prefs      = try container.mainContext.fetch(FetchDescriptor<UserPreference>())
        let activities = try container.mainContext.fetch(FetchDescriptor<ActivityRecord>())

        XCTAssertEqual(goals.count, 1, "FitnessGoal must survive V6→V7 migration")
        XCTAssertEqual(prefs.count, 1, "UserPreference must survive V6→V7 migration")
        XCTAssertEqual(activities.count, 1, "ActivityRecord must survive V6→V7 migration")
        XCTAssertEqual(goals.first?.title, "Triatlon Almere")
    }

    func test_migration_canInsertAndReadWorkoutChatModelsAfterMigration() throws {
        try seedV6Store { ctx in
            ctx.insert(FitnessGoal(title: "Control goal", targetDate: Date().addingTimeInterval(86_400 * 30)))
        }

        let container = try openV7Store()

        // Simulate a first chat exchange + a distilled fact on one workout.
        let entryUser = WorkoutChatEntry(activityID: "9876543210",
                                         role: .user,
                                         text: "Voelde zwaar vandaag, slecht geslapen.")
        let entryAI = WorkoutChatEntry(activityID: "9876543210",
                                       role: .ai,
                                       text: "Logisch dat de benen dan zwaar aanvoelen.")
        let fact = WorkoutChatFact(activityID: "9876543210",
                                   factText: "Slecht geslapen voor deze rit",
                                   category: .dayCondition)
        container.mainContext.insert(entryUser)
        container.mainContext.insert(entryAI)
        container.mainContext.insert(fact)
        try container.mainContext.save()

        // Reopen and verify the records persisted with their typed fields intact.
        let reopened = try openV7Store()
        // Sorted in memory: a SortDescriptor key path triggers a Sendable warning
        // under strict concurrency, and two records don't need a store-side sort.
        let entries = try reopened.mainContext.fetch(FetchDescriptor<WorkoutChatEntry>())
            .sorted { $0.timestamp < $1.timestamp }
        let facts = try reopened.mainContext.fetch(FetchDescriptor<WorkoutChatFact>())

        XCTAssertEqual(entries.count, 2, "Both chat entries should persist across reopen")
        XCTAssertEqual(entries.first?.role, .user)
        XCTAssertEqual(entries.last?.role, .ai)
        XCTAssertEqual(entries.first?.activityID, "9876543210")
        XCTAssertEqual(facts.count, 1, "The distilled fact should persist across reopen")
        XCTAssertEqual(facts.first?.category, .dayCondition)
        XCTAssertEqual(facts.first?.factText, "Slecht geslapen voor deze rit")
    }

    func test_migration_emptyV6Store_opensCleanly() throws {
        try seedV6Store { _ in }

        let container = try openV7Store()
        let entries = try container.mainContext.fetch(FetchDescriptor<WorkoutChatEntry>())
        let facts   = try container.mainContext.fetch(FetchDescriptor<WorkoutChatFact>())

        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(facts.isEmpty)
    }
}
