import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Unit tests for `WorkoutSampleStore.pruneSamplesOlderThanRetention` (Epic #65 story 65.2).
///
/// An in-memory container is fine here — no schema migration is involved. Guarantees:
///  • prunes only samples beyond the 6-month horizon;
///  • never touches samples inside the newest N months;
///  • idempotent on a second run;
///  • a sample exactly on the boundary is kept.
@MainActor
final class WorkoutSampleRetentionTests: XCTestCase {

    private var container: ModelContainer!
    private var store: WorkoutSampleStore!
    // Fixed reference so month-math is deterministic across runs.
    private let now = Date(timeIntervalSince1970: 1_750_000_000) // 2025-06-15
    private let calendar = Calendar.current

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: WorkoutSample.self, configurations: config)
        store = WorkoutSampleStore(modelContainer: container)
    }

    override func tearDownWithError() throws {
        container = nil
        store = nil
    }

    // MARK: Helpers

    /// Seeds `count` samples for a workout whose bucket timestamps start `monthsAgo` before `now`.
    @discardableResult
    private func seedWorkout(monthsAgo: Int, count: Int = 3) async throws -> UUID {
        let base = calendar.date(byAdding: .month, value: -monthsAgo, to: now)!
        return try await seedWorkout(startingAt: base, count: count)
    }

    @discardableResult
    private func seedWorkout(startingAt base: Date, count: Int = 3) async throws -> UUID {
        let uuid = UUID()
        let samples = (0..<count).map { i in
            WorkoutSample(
                workoutUUID: uuid,
                timestamp: base.addingTimeInterval(Double(i) * 5),
                heartRate: 140
            )
        }
        try await store.replaceSamples(samples, forWorkoutUUID: uuid)
        return uuid
    }

    // MARK: Tests

    func testPrunesOnlySamplesBeyondTheWindow() async throws {
        let oldUUID = try await seedWorkout(monthsAgo: 8, count: 4)   // beyond 6 months → pruned
        let newUUID = try await seedWorkout(monthsAgo: 2, count: 5)   // inside → kept

        let deleted = try await store.pruneSamplesOlderThanRetention(now: now, calendar: calendar)

        XCTAssertEqual(deleted, 4, "Only the 8-month-old workout's samples should be pruned")
        let oldCount = try await store.sampleCount(forWorkoutUUID: oldUUID)
        let newCount = try await store.sampleCount(forWorkoutUUID: newUUID)
        XCTAssertEqual(oldCount, 0)
        XCTAssertEqual(newCount, 5)
    }

    func testNeverTouchesNewestMonths() async throws {
        // Three workouts, all inside the 6-month window.
        let a = try await seedWorkout(monthsAgo: 1, count: 3)
        let b = try await seedWorkout(monthsAgo: 3, count: 3)
        let c = try await seedWorkout(monthsAgo: 5, count: 3)

        let deleted = try await store.pruneSamplesOlderThanRetention(now: now, calendar: calendar)

        XCTAssertEqual(deleted, 0, "Nothing within the window should be pruned")
        for uuid in [a, b, c] {
            let count = try await store.sampleCount(forWorkoutUUID: uuid)
            XCTAssertEqual(count, 3)
        }
    }

    func testIdempotentOnSecondRun() async throws {
        try await seedWorkout(monthsAgo: 9, count: 3)
        let survivor = try await seedWorkout(monthsAgo: 1, count: 2)

        let firstRun = try await store.pruneSamplesOlderThanRetention(now: now, calendar: calendar)
        let secondRun = try await store.pruneSamplesOlderThanRetention(now: now, calendar: calendar)

        XCTAssertEqual(firstRun, 3)
        XCTAssertEqual(secondRun, 0, "A warm store has nothing left to prune")
        let survivorCount = try await store.sampleCount(forWorkoutUUID: survivor)
        XCTAssertEqual(survivorCount, 2)
    }

    func testSampleExactlyOnBoundaryIsKept() async throws {
        let cutoff = calendar.date(
            byAdding: .month,
            value: -WorkoutSampleStore.retentionMonths,
            to: now
        )!
        // One workout whose first sample sits exactly on the cutoff (kept),
        // and one whose sole sample is one second before the cutoff (pruned).
        let boundaryUUID = try await seedWorkout(startingAt: cutoff, count: 1)
        let justBeforeUUID = try await seedWorkout(startingAt: cutoff.addingTimeInterval(-1), count: 1)

        let deleted = try await store.pruneSamplesOlderThanRetention(now: now, calendar: calendar)

        XCTAssertEqual(deleted, 1, "Only the sample strictly before the cutoff is pruned")
        let boundaryCount = try await store.sampleCount(forWorkoutUUID: boundaryUUID)
        let justBeforeCount = try await store.sampleCount(forWorkoutUUID: justBeforeUUID)
        XCTAssertEqual(boundaryCount, 1, "timestamp == cutoff is kept (\"more than N months ago\")")
        XCTAssertEqual(justBeforeCount, 0)
    }
}
