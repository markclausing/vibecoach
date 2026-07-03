import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Unit tests for `AutoSyncCoordinator` (Epic #65 story 65.4). The whole auto-sync
/// pipeline used to be documented-not-tested view orchestration in `AppTabHostView`;
/// with the extraction it now has an injection seam per external dependency (HK sync,
/// Strava fetch, weather fetch, DeepSync, permission retrigger) so the concurrency
/// guard, per-source status writes and per-record weather-failure isolation are
/// testable without touching HealthKit or the network.
@MainActor
final class AutoSyncCoordinatorTests: XCTestCase {

    // MARK: - Mocks

    /// `@MainActor` class → Sendable, and its `@MainActor` method satisfies the
    /// `@MainActor` requirement on `HealthKitWorkoutSyncing`.
    @MainActor
    final class MockHealthKitSync: HealthKitWorkoutSyncing {
        var result: Result<Int, Error>
        private(set) var callCount = 0
        /// When true, the first call parks on a continuation so a test can hold the
        /// pipeline "in flight" and probe the concurrency guard.
        var shouldGate = false
        var gate: CheckedContinuation<Void, Never>?

        init(_ result: Result<Int, Error> = .success(0)) { self.result = result }

        func syncHistoricalWorkouts(to context: ModelContext) async throws -> Int {
            callCount += 1
            if shouldGate {
                await withCheckedContinuation { cont in self.gate = cont }
            }
            return try result.get()
        }
    }

    /// `actor` → its async method satisfies the nonisolated async requirement on
    /// `StravaActivityFetching`.
    actor MockStravaFetch: StravaActivityFetching {
        let result: Result<[StravaActivity], Error>
        init(_ result: Result<[StravaActivity], Error>) { self.result = result }
        func fetchRecentActivities(days: Int) async throws -> [StravaActivity] {
            try result.get()
        }
    }

    struct TestError: Error {}

    /// Sendable counter so a `@Sendable` weather-fetch closure can record its calls.
    actor CallCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    // MARK: - Fixtures

    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var syncStatusStore: SyncStatusStore!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ActivityRecord.self, configurations: config)
        context = ModelContext(container)

        suiteName = "test.autosync.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        syncStatusStore = SyncStatusStore(defaults: defaults, rateLimitStore: StravaRateLimitStore(defaults: defaults))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        context = nil
        defaults = nil
        syncStatusStore = nil
    }

    // MARK: - Helpers

    private func makeCoordinator(
        hk: MockHealthKitSync = MockHealthKitSync(.success(0)),
        strava: MockStravaFetch,
        weatherConcurrency: Int = 4,
        fetchWeather: (@Sendable (Double, Double, Date) async -> WeatherFetchResult)? = nil
    ) -> AutoSyncCoordinator {
        AutoSyncCoordinator(
            modelContext: context,
            healthKitSync: hk,
            stravaFetch: strava,
            syncStatusStore: syncStatusStore,
            defaults: defaults,
            weatherConcurrency: weatherConcurrency,
            fetchWeather: fetchWeather ?? { _, _, _ in (nil, nil) },
            runDeepSync: {},                 // no-op — DeepSync is exercised by its own tests
            retriggerPermissions: {}
        )
    }

    private func activity(id: Int64, latlng: [Double]? = nil) -> StravaActivity {
        // Distinct day per id so two fixtures don't collapse into one via
        // ActivityDeduplicator's cross-source ±5s window.
        StravaActivity(
            id: id,
            name: "Ride \(id)",
            distance: 10_000,
            moving_time: 3_600,
            average_heartrate: 140,
            type: "Ride",
            start_date: String(format: "2026-06-%02dT08:00:00Z", Int(id)),
            device_watts: nil,
            start_latlng: latlng
        )
    }

    private func allRecords() throws -> [ActivityRecord] {
        try context.fetch(FetchDescriptor<ActivityRecord>())
    }

    // MARK: - (1) Concurrency guard

    func testSecondCallDuringInFlightSyncIsNoOp() async throws {
        let hk = MockHealthKitSync(.success(3))
        hk.shouldGate = true
        let coordinator = makeCoordinator(hk: hk, strava: MockStravaFetch(.success([])))

        // First run parks in the HK gate → the pipeline stays "in flight".
        async let first: Void = coordinator.runAutoSync()
        while hk.gate == nil { await Task.yield() }

        // Second run while the first is still in flight must be a no-op.
        await coordinator.runAutoSync()

        hk.gate?.resume()
        await first

        XCTAssertEqual(hk.callCount, 1, "The guarded second run must not reach the HK sync")
    }

    // MARK: - (2) Missing Strava token stays silent

    func testMissingStravaTokenRecordsNoError() async throws {
        let coordinator = makeCoordinator(strava: MockStravaFetch(.failure(FitnessDataError.missingToken)))
        await coordinator.runAutoSync()

        let snap = syncStatusStore.snapshot(isOffline: false)
        XCTAssertNil(snap.lastStravaError, "missingToken must not be recorded as a banner error")
        XCTAssertNil(snap.lastStravaSuccessAt, "A missing token is not a success either")
    }

    // MARK: - (3) HK failure isolates from a succeeding Strava sync

    func testHealthKitFailureRecordsZeroCountAndStravaStillProceeds() async throws {
        let hk = MockHealthKitSync(.failure(TestError()))
        let coordinator = makeCoordinator(hk: hk, strava: MockStravaFetch(.success([activity(id: 1)])))

        await coordinator.runAutoSync()

        XCTAssertEqual(defaults.integer(forKey: AppStorageKeys.lastHKWorkoutsCount), 0)
        let snap = syncStatusStore.snapshot(isOffline: false)
        XCTAssertNotNil(snap.lastHKError, "HK failure must be recorded")
        XCTAssertNotNil(snap.lastStravaSuccessAt, "Strava must proceed despite the HK failure")
        XCTAssertEqual(try allRecords().count, 1, "The Strava record must be inserted")
    }

    // MARK: - (4) Both sources succeed

    func testBothSourcesSucceedWriteStatusAndCounts() async throws {
        let hk = MockHealthKitSync(.success(5))
        let coordinator = makeCoordinator(
            hk: hk,
            strava: MockStravaFetch(.success([activity(id: 1), activity(id: 2)]))
        )

        await coordinator.runAutoSync()

        XCTAssertEqual(defaults.integer(forKey: AppStorageKeys.lastHKWorkoutsCount), 5)
        let snap = syncStatusStore.snapshot(isOffline: false)
        XCTAssertNotNil(snap.lastHKSuccessAt)
        XCTAssertNotNil(snap.lastStravaSuccessAt)
        XCTAssertNil(snap.lastHKError)
        XCTAssertNil(snap.lastStravaError)
        XCTAssertEqual(try allRecords().count, 2)
    }

    // MARK: - (5) Weather-enrichment failure does not fail the sync

    func testWeatherFailureLeavesRecordWithoutWeatherButSyncSucceeds() async throws {
        let weatherCalls = CallCounter()
        let coordinator = makeCoordinator(
            strava: MockStravaFetch(.success([activity(id: 1, latlng: [52.1, 5.1])])),
            fetchWeather: { _, _, _ in
                await weatherCalls.increment()
                return (nil, nil)          // simulate a swallowed transport failure
            }
        )

        await coordinator.runAutoSync()

        let calls = await weatherCalls.count
        XCTAssertEqual(calls, 1, "Weather fetch must be attempted for a record with coords")
        let records = try allRecords()
        XCTAssertEqual(records.count, 1, "A failed weather fetch must not drop the record")
        let record = try XCTUnwrap(records.first)
        XCTAssertNil(record.temperatureCelsius, "Failed enrichment leaves the record without weather")
        XCTAssertEqual(record.startLatitude, 52.1, "Coords are still persisted independently of weather")
        XCTAssertNotNil(syncStatusStore.snapshot(isOffline: false).lastStravaSuccessAt)
    }
}
