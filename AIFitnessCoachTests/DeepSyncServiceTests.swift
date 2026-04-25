import XCTest
import HealthKit
import SwiftData
@testable import AIFitnessCoach

/// Unit tests voor `DeepSyncService` — orchestrator van de eenmalige 30-daagse historische sync.
/// HealthKit wordt niet aangeraakt: workouts worden via `workoutsProvider` geïnjecteerd,
/// en de ingest-laag via een `WorkoutSampleIngesting`-mock.
@MainActor
final class DeepSyncServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var container: ModelContainer!
    private var store: WorkoutSampleStore!
    private var mockIngest: MockIngestService!

    override func setUpWithError() throws {
        defaultsSuiteName = "test.deepsync.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: WorkoutSample.self, configurations: config)
        store = WorkoutSampleStore(modelContainer: container)
        mockIngest = MockIngestService()
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        container = nil
        store = nil
        mockIngest = nil
    }

    // MARK: Helpers

    private func makeWorkout(secondsAgo: TimeInterval = 60) -> HKWorkout {
        let end = Date().addingTimeInterval(-secondsAgo)
        let start = end.addingTimeInterval(-1800)
        return HKWorkout(activityType: .running, start: start, end: end)
    }

    private func makeService(workouts: [HKWorkout]) -> DeepSyncService {
        DeepSyncService(
            ingestService: mockIngest,
            store: store,
            userDefaults: defaults,
            daysBack: 30,
            workoutsProvider: { _, _ in workouts }
        )
    }

    // MARK: Tests

    func testSkipsWhenAlreadyCompleted() async {
        defaults.set(true, forKey: DeepSyncService.completedFlagKey)
        let service = makeService(workouts: [makeWorkout()])

        await service.runIfNeeded()

        XCTAssertEqual(mockIngest.ingestCalls.count, 0,
                       "Met de completed-flag aan mag ingest niet meer worden aangeroepen")
        XCTAssertEqual(service.status, .idle)
    }

    func testProcessesAllWorkoutsAndSetsFlag() async {
        let workouts = [makeWorkout(secondsAgo: 60),
                        makeWorkout(secondsAgo: 120),
                        makeWorkout(secondsAgo: 180)]
        let service = makeService(workouts: workouts)

        await service.runIfNeeded()

        XCTAssertEqual(mockIngest.ingestCalls.count, 3)
        XCTAssertEqual(Set(mockIngest.ingestCalls), Set(workouts.map(\.uuid)))
        XCTAssertTrue(service.hasCompletedInitialDeepSync,
                      "Na een schone run moet de flag op true staan")
        XCTAssertEqual(service.status, .completed)
        // Cleanup-stap: processed-set is gewist nu de flag de waarheid is.
        XCTAssertNil(defaults.data(forKey: DeepSyncService.processedUUIDsKey))
    }

    func testResumesSkippingAlreadyProcessedWorkouts() async {
        let workouts = (0..<5).map { makeWorkout(secondsAgo: TimeInterval(60 + $0 * 60)) }
        // Markeer de eerste twee als al-verwerkt.
        let alreadyProcessed: Set<UUID> = [workouts[0].uuid, workouts[1].uuid]
        if let data = try? JSONEncoder().encode(Array(alreadyProcessed)) {
            defaults.set(data, forKey: DeepSyncService.processedUUIDsKey)
        }

        let service = makeService(workouts: workouts)
        await service.runIfNeeded()

        XCTAssertEqual(mockIngest.ingestCalls.count, 3,
                       "Slechts 3 nieuwe workouts moeten worden geïngest")
        XCTAssertEqual(Set(mockIngest.ingestCalls),
                       Set(workouts.suffix(3).map(\.uuid)))
        XCTAssertTrue(service.hasCompletedInitialDeepSync)
    }

    func testFailingWorkoutDoesNotBlockRest() async {
        let workouts = [makeWorkout(secondsAgo: 60),
                        makeWorkout(secondsAgo: 120),
                        makeWorkout(secondsAgo: 180)]
        // Workout #2 faalt — de andere twee moeten alsnog verwerkt worden.
        mockIngest.failOnUUIDs = [workouts[1].uuid]

        let service = makeService(workouts: workouts)
        await service.runIfNeeded()

        XCTAssertEqual(mockIngest.ingestCalls.count, 3,
                       "Alle drie moeten geprobeerd zijn — falen zonder skip-logica is een regressie")
        XCTAssertFalse(service.hasCompletedInitialDeepSync,
                       "Met één falende workout mag de flag NIET op true gaan — anders raakt die workout voor altijd kwijt")

        // De geslaagde twee staan in de processed-set zodat de volgende run alleen #2 hoeft te retryen.
        let savedData = defaults.data(forKey: DeepSyncService.processedUUIDsKey)
        XCTAssertNotNil(savedData)
        let savedUUIDs = (try? JSONDecoder().decode([UUID].self, from: savedData!)) ?? []
        XCTAssertEqual(Set(savedUUIDs),
                       Set([workouts[0].uuid, workouts[2].uuid]))
    }

    func testEmptyWorkoutListMarksCompleted() async {
        let service = makeService(workouts: [])

        await service.runIfNeeded()

        XCTAssertEqual(mockIngest.ingestCalls.count, 0)
        XCTAssertTrue(service.hasCompletedInitialDeepSync,
                      "Geen workouts = niets te doen = sync afgerond")
        XCTAssertEqual(service.status, .completed)
    }

    func testPersistsProgressAfterEachWorkout() async {
        // Simuleer een sync waar #2 faalt; check dat #1's UUID gepersisteerd is direct na succes.
        let workouts = [makeWorkout(secondsAgo: 60),
                        makeWorkout(secondsAgo: 120)]
        mockIngest.failOnUUIDs = [workouts[1].uuid]

        let service = makeService(workouts: workouts)
        await service.runIfNeeded()

        let saved = defaults.data(forKey: DeepSyncService.processedUUIDsKey)
            .flatMap { try? JSONDecoder().decode([UUID].self, from: $0) }
        XCTAssertEqual(Set(saved ?? []), [workouts[0].uuid],
                       "Workout #1 moet meteen na success persisten — anders gaat partial-progress verloren bij een crash")
    }
}

// MARK: - Mocks

/// Minimale stub van `WorkoutSampleIngesting` — telt aanroepen en kan selectief falen.
final class MockIngestService: WorkoutSampleIngesting, @unchecked Sendable {
    private(set) var ingestCalls: [UUID] = []
    var failOnUUIDs: Set<UUID> = []

    func ingestSamples(for workout: HKWorkout, into store: WorkoutSampleStore) async throws {
        ingestCalls.append(workout.uuid)
        if failOnUUIDs.contains(workout.uuid) {
            throw NSError(domain: "MockIngestError", code: 1, userInfo: nil)
        }
    }
}
