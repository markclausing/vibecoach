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
        // Epic #52: tests gaan default uit van "gebruiker zit al op de laatste
        // ingest-revisie" — anders wist `applyIngestRevisionMigrationIfNeeded`
        // de geseede processed-set en interfereert het met dedupe-asserts.
        // De expliciete migration-test seed bewust géén revisie om het pad te
        // kunnen triggeren.
        defaults.set(DeepSyncService.currentIngestRevision, forKey: DeepSyncService.ingestRevisionKey)

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

    /// fix/workout-samples-loading: ook met de legacy completion-flag op true moet
    /// DeepSync nog draaien voor pending workouts — anders blijven net-binnen-
    /// gekomen workouts eeuwig op de "samples ontbreken"-placeholder hangen.
    func testRunsEvenWhenLegacyCompletedFlagIsSet() async {
        defaults.set(true, forKey: DeepSyncService.completedFlagKey)
        let workout = makeWorkout()
        let service = makeService(workouts: [workout])

        await service.runIfNeeded()

        XCTAssertEqual(mockIngest.ingestCalls.count, 1,
                       "Legacy completion-flag mag de incremental sync niet meer blokkeren")
        XCTAssertEqual(mockIngest.ingestCalls.first, workout.uuid)
        XCTAssertEqual(service.status, .completed)
    }

    func testProcessesAllWorkouts() async {
        let workouts = [makeWorkout(secondsAgo: 60),
                        makeWorkout(secondsAgo: 120),
                        makeWorkout(secondsAgo: 180)]
        let service = makeService(workouts: workouts)

        await service.runIfNeeded()

        XCTAssertEqual(mockIngest.ingestCalls.count, 3)
        XCTAssertEqual(Set(mockIngest.ingestCalls), Set(workouts.map(\.uuid)))
        XCTAssertEqual(service.status, .completed)

        // Processed-set blijft staan (single-source-of-truth voor dedupe over runs heen).
        let savedData = defaults.data(forKey: DeepSyncService.processedUUIDsKey)
        XCTAssertNotNil(savedData, "Processed-set moet permanent zijn — niet meer gewist bij completion")
        let savedUUIDs = (try? JSONDecoder().decode([UUID].self, from: savedData!)) ?? []
        XCTAssertEqual(Set(savedUUIDs), Set(workouts.map(\.uuid)))
    }

    /// fix/workout-samples-loading: nadat alle workouts samples hebben, mag een
    /// tweede run géén HK-quantity-queries triggeren — anders raakt elke
    /// view-refresh in de I/O-laag.
    func testSecondRunSkipsAlreadyProcessedWorkouts() async {
        let workouts = [makeWorkout(secondsAgo: 60),
                        makeWorkout(secondsAgo: 120)]
        let service = makeService(workouts: workouts)

        await service.runIfNeeded()
        XCTAssertEqual(mockIngest.ingestCalls.count, 2, "Eerste run verwerkt alle workouts")

        // Tweede run met dezelfde workouts moet niks meer doen.
        mockIngest.resetIngestCalls()
        await service.runIfNeeded()

        XCTAssertEqual(mockIngest.ingestCalls.count, 0,
                       "Tweede run mag geen ingest meer triggeren — alles zit al in processed-set")
        XCTAssertEqual(service.status, .completed)
    }

    /// fix/workout-samples-loading: een nieuwe workout (die niet in de processed-set
    /// zit) moet bij de volgende runIfNeeded() worden opgepakt — dit is het pad
    /// waarlangs nieuwe HK-workouts van auto-sync hun grafiek-data krijgen.
    func testIncrementalRunIngestsOnlyNewWorkouts() async {
        let existing = makeWorkout(secondsAgo: 600)
        let service1 = makeService(workouts: [existing])
        await service1.runIfNeeded()
        XCTAssertEqual(mockIngest.ingestCalls.count, 1)

        // Nieuwe workout komt erbij — service moet alleen deze nieuwe pakken.
        mockIngest.resetIngestCalls()
        let newWorkout = makeWorkout(secondsAgo: 60)
        let service2 = makeService(workouts: [existing, newWorkout])
        await service2.runIfNeeded()

        XCTAssertEqual(mockIngest.ingestCalls.count, 1,
                       "Alleen de nieuwe workout mag worden geïngest, niet de al-verwerkte")
        XCTAssertEqual(mockIngest.ingestCalls.first, newWorkout.uuid)
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
        XCTAssertEqual(service.status, .completed)
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
        XCTAssertEqual(service.status, .completed)
    }

    // MARK: Epic #52 — ingest-revisie-migratie

    /// Bij een ingest-revisie-bump moet de processed-set worden gewist zodat
    /// álle workouts in het venster opnieuw worden geïngest (om running cadens
    /// uit `stepCount` ook voor bestaande HK-workouts beschikbaar te maken).
    func testIngestRevisionBumpClearsProcessedSetAndReIngestsAll() async {
        // Simuleer een oudere installatie: revisie ontbreekt (= 0) en de
        // processed-set is gevuld met al-verwerkte workout-UUIDs van vóór
        // Epic #52.
        defaults.removeObject(forKey: DeepSyncService.ingestRevisionKey)
        let workouts = (0..<3).map { makeWorkout(secondsAgo: TimeInterval(60 + $0 * 60)) }
        let preExistingProcessed = Set(workouts.map(\.uuid))
        if let data = try? JSONEncoder().encode(Array(preExistingProcessed)) {
            defaults.set(data, forKey: DeepSyncService.processedUUIDsKey)
        }

        let service = makeService(workouts: workouts)
        await service.runIfNeeded()

        XCTAssertEqual(mockIngest.ingestCalls.count, 3,
                       "Alle workouts moeten opnieuw worden geïngest na revisie-bump")
        XCTAssertEqual(defaults.integer(forKey: DeepSyncService.ingestRevisionKey),
                       DeepSyncService.currentIngestRevision,
                       "Nieuwe revisie moet zijn opgeslagen zodat de migratie niet opnieuw triggert")
    }

    /// Sanity check op de happy path: gebruiker zit al op de laatste revisie,
    /// migratie is no-op en de processed-set blijft intact tussen runs.
    func testNoIngestRevisionBumpKeepsProcessedSet() async {
        // setUp heeft `currentIngestRevision` al gezet — geen migratie verwacht.
        let workouts = [makeWorkout(secondsAgo: 60), makeWorkout(secondsAgo: 120)]
        let processedBefore: Set<UUID> = [workouts[0].uuid]
        if let data = try? JSONEncoder().encode(Array(processedBefore)) {
            defaults.set(data, forKey: DeepSyncService.processedUUIDsKey)
        }

        let service = makeService(workouts: workouts)
        await service.runIfNeeded()

        XCTAssertEqual(mockIngest.ingestCalls.count, 1,
                       "Alleen de niet-geprocesste workout moet worden geïngest")
        XCTAssertEqual(mockIngest.ingestCalls.first, workouts[1].uuid)
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

    /// fix/workout-samples-loading: gebruikt door tests die twee opeenvolgende runs
    /// op dezelfde service simuleren. Mock zelf blijft `private(set)` zodat ingest
    /// alleen via de protocol-call kan worden geregistreerd.
    func resetIngestCalls() {
        ingestCalls.removeAll()
    }
}
