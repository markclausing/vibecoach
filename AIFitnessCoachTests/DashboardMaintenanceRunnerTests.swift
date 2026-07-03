import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Light orchestration/wiring tests for `DashboardMaintenanceRunner` (Epic #65 story
/// 65.4). The individual jobs keep their own dedicated service tests
/// (`ActivityDeduplicatorTests`, `SessionReclassifierTests`, `WorkoutPatternDetector…`);
/// here we only assert that the runner correctly drives them through a real in-memory
/// SwiftData context — that dedupe removes a duplicate, that the context-cache refresh
/// clears caches on an empty window, and that the full post-sync sequence completes.
@MainActor
final class DashboardMaintenanceRunnerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var runner: DashboardMaintenanceRunner!
    private let baseDate = Date(timeIntervalSince1970: 1_745_625_600) // 2025-04-26

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ActivityRecord.self, WorkoutSample.self, configurations: config)
        context = container.mainContext
        runner = DashboardMaintenanceRunner(modelContext: context)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        runner = nil
    }

    @discardableResult
    private func makeRecord(id: String,
                            startOffset: TimeInterval = 0,
                            sportCategory: SportCategory = .cycling,
                            trimp: Double? = nil) -> ActivityRecord {
        let record = ActivityRecord(
            id: id,
            name: "Test \(id)",
            distance: 10_000,
            movingTime: 3_600,
            averageHeartrate: nil,
            sportCategory: sportCategory,
            startDate: baseDate.addingTimeInterval(startOffset),
            trimp: trimp
        )
        context.insert(record)
        return record
    }

    private func recordCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<ActivityRecord>())
    }

    // MARK: - Dedupe wiring

    func testRunAutoDedupeRemovesDuplicatePair() async throws {
        // Two cycling records 3s apart → one duplicate group; the higher-TRIMP one wins.
        makeRecord(id: "winner", startOffset: 0, trimp: 100)
        makeRecord(id: "loser", startOffset: 3, trimp: nil)
        try context.save()
        XCTAssertEqual(try recordCount(), 2)

        await runner.runAutoDedupe()

        XCTAssertEqual(try recordCount(), 1, "The runner must drive ActivityDeduplicator to remove the duplicate")
        let survivor = try XCTUnwrap(try context.fetch(FetchDescriptor<ActivityRecord>()).first)
        XCTAssertEqual(survivor.id, "winner")
    }

    func testRunAutoDedupeOnCleanDBIsIdempotent() async throws {
        makeRecord(id: "a", startOffset: 0)
        makeRecord(id: "b", startOffset: 10_000, sportCategory: .running)
        try context.save()

        await runner.runAutoDedupe()
        XCTAssertEqual(try recordCount(), 2, "Distinct records must not be touched")
    }

    // MARK: - Context-cache refresh wiring

    func testRefreshChatContextCachesEmptiesCachesOnEmptyWindow() async throws {
        let store = CoachContextStore()
        // Pre-seed so we can prove the refresh clears them.
        store.workoutPatternsContext = "stale"
        store.workoutHistoryContext = "stale-history"

        await runner.refreshChatContextCaches(into: store)

        XCTAssertEqual(store.workoutPatternsContext, "", "No workouts in window → pattern cache cleared")
        XCTAssertEqual(store.workoutHistoryContext, "", "No workouts in window → history cache cleared")
    }

    // MARK: - Strava backfill wiring

    func testBackfillStravaStreamsWithNoStravaRecordsIsNoOp() async throws {
        // Only a HealthKit record (UUID id) present → no Strava candidates, so no
        // network call is made and the DB is untouched.
        makeRecord(id: UUID().uuidString, startOffset: 0)
        try context.save()

        await runner.backfillStravaStreams()

        XCTAssertEqual(try recordCount(), 1)
    }

    // MARK: - Full sequence

    func testRunPostSyncMaintenanceCompletesOnEmptyDB() async throws {
        let store = CoachContextStore()
        // Should complete without throwing and leave the caches empty.
        await runner.runPostSyncMaintenance(context: store)
        XCTAssertEqual(store.workoutPatternsContext, "")
        XCTAssertEqual(store.workoutHistoryContext, "")
        XCTAssertEqual(try recordCount(), 0)
    }
}
