import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Story 61.7: file-backed test of the SwiftData V5 → V6 migration.
///
/// V6 is a pure addition: `CoachContextCache` (a new @Model) is added to the schema.
/// The migration stage is `.lightweight` — SwiftData creates the new table and touches
/// no existing records.
///
/// Safety-net role (per CLAUDE.md §2.1): verifies that a populated V5 store migrates
/// cleanly to V6 without the fallback in `AIFitnessCoachApp.makeModelContainer` kicking
/// in (= local-only data loss for `FitnessGoal` + `UserPreference`).
@MainActor
final class SchemaMigrationV5ToV6Tests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibecoach-migration-v5v6-\(UUID().uuidString).store")
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

    /// Builds a V5 container (no migration plan) and seeds test data.
    private func seedV5Store(seed: (ModelContext) throws -> Void) throws {
        let schema = Schema(versionedSchema: SchemaV5.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: config)
        try seed(container.mainContext)
        try container.mainContext.save()
    }

    /// Opens the same store with the V6 schema + AppMigrationPlan.
    private func openV6Store() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV6.self)
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

        try seedV5Store { ctx in
            ctx.insert(FitnessGoal(title: "Triatlon Almere", targetDate: goalDate, sportCategory: .running))
            ctx.insert(UserPreference(preferenceText: "Voorkeur voor avondtraining"))
        }

        let container = try openV6Store()
        let goals = try container.mainContext.fetch(FetchDescriptor<FitnessGoal>())
        let prefs = try container.mainContext.fetch(FetchDescriptor<UserPreference>())

        XCTAssertEqual(goals.count, 1, "FitnessGoal must survive V5→V6 migration")
        XCTAssertEqual(prefs.count, 1, "UserPreference must survive V5→V6 migration")
        XCTAssertEqual(goals.first?.title, "Triatlon Almere")
    }

    func test_migration_canInsertAndReadCoachContextCacheAfterMigration() throws {
        try seedV5Store { ctx in
            ctx.insert(FitnessGoal(title: "Control goal", targetDate: Date().addingTimeInterval(86_400 * 30)))
        }

        let container = try openV6Store()

        // Simulate the first-launch configure(with:) behaviour: insert the singleton.
        let cache = CoachContextCache()
        cache.symptomContext = "Lichte kniepijn links (score 2)"
        cache.lastAnalysisTimestamp = 1_750_000_000
        container.mainContext.insert(cache)
        try container.mainContext.save()

        // Reopen and verify the record persisted.
        let reopened = try openV6Store()
        let caches = try reopened.mainContext.fetch(FetchDescriptor<CoachContextCache>())

        XCTAssertEqual(caches.count, 1, "Exactly one CoachContextCache should exist")
        XCTAssertEqual(caches.first?.symptomContext, "Lichte kniepijn links (score 2)")
        XCTAssertEqual(caches.first?.lastAnalysisTimestamp, 1_750_000_000)
    }

    func test_migration_clearAll_resetsAllFields() throws {
        try seedV5Store { _ in }

        let container = try openV6Store()
        let cache = CoachContextCache()
        cache.todayVibeScoreContext = "Vibe: 82"
        cache.symptomContext = "Kniepijn"
        cache.workoutHistoryContext = "14-day history…"
        cache.lastAnalysisTimestamp = 1_700_000_000
        container.mainContext.insert(cache)
        try container.mainContext.save()

        cache.clearAll()
        try container.mainContext.save()

        let reopened = try openV6Store()
        let all = try reopened.mainContext.fetch(FetchDescriptor<CoachContextCache>())
        guard let reloaded = all.first else { return XCTFail("Cache record not found") }

        XCTAssertEqual(reloaded.todayVibeScoreContext, "")
        XCTAssertEqual(reloaded.symptomContext, "")
        XCTAssertEqual(reloaded.workoutHistoryContext, "")
        XCTAssertEqual(reloaded.lastAnalysisTimestamp, 0)
    }
}
