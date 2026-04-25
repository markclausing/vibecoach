import Foundation
import HealthKit
import SwiftData
import os.log

// MARK: - Epic 32 Story 32.1: 30-daagse Deep Sync Orchestrator
//
// Eenmalige historische sync: alle HKWorkouts uit de afgelopen 30 dagen worden door de
// `WorkoutSampleIngestService` gehaald zodat de `WorkoutSample`-store gevuld is voor
// fysiologische analyses (Story 32.2 + 32.3).
//
// Idempotentie & hervatting:
//   • `processedWorkoutUUIDs` (UserDefaults, JSON-encoded UUID-set) wordt per succesvol
//     verwerkte workout direct weggeschreven. Een crash midden in de sync betekent dat
//     de volgende run alleen de overgebleven workouts oppakt.
//   • `hasCompletedInitialDeepSync` (Bool) gaat pas op true wanneer ALLE workouts in
//     het venster verwerkt zijn — anders draait de sync de volgende keer gewoon door.
//   • Faalt één workout? Loggen en doorgaan met de rest. Niet-gemarkeerde UUIDs worden
//     bij de volgende run vanzelf opnieuw geprobeerd.

private let log = Logger(subsystem: "com.markclausing.aifitnesscoach", category: "DeepSync")

/// Abstractie boven `WorkoutSampleIngestService` zodat de orchestrator unit-testbaar is
/// zonder een echte HealthKit te raken.
protocol WorkoutSampleIngesting {
    func ingestSamples(for workout: HKWorkout, into store: WorkoutSampleStore) async throws
}

extension WorkoutSampleIngestService: WorkoutSampleIngesting {}

@MainActor
final class DeepSyncService: ObservableObject {

    /// Status voor toekomstige UI-binding (Story 32.2). Voor nu fire-and-forget.
    enum Status: Equatable {
        case idle
        case syncing(processed: Int, total: Int)
        case completed
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    // MARK: Dependencies

    private let ingestService: WorkoutSampleIngesting
    private let store: WorkoutSampleStore
    private let userDefaults: UserDefaults
    private let daysBack: Int
    private let workoutsProvider: (Date, Date) async throws -> [HKWorkout]

    // MARK: UserDefaults keys

    static let completedFlagKey   = "DeepSync.hasCompletedInitialDeepSync"
    static let processedUUIDsKey  = "DeepSync.processedWorkoutUUIDs"

    /// Productie-init — gebruikt `HKHealthStore` voor het workout-fetchen.
    convenience init(ingestService: WorkoutSampleIngesting,
                     store: WorkoutSampleStore,
                     userDefaults: UserDefaults = .standard,
                     daysBack: Int = 30,
                     healthStore: HKHealthStore = HKHealthStore()) {
        self.init(
            ingestService: ingestService,
            store: store,
            userDefaults: userDefaults,
            daysBack: daysBack,
            workoutsProvider: { start, end in
                try await DeepSyncService.fetchWorkouts(healthStore: healthStore, start: start, end: end)
            }
        )
    }

    /// Test-init — laat de caller een synthetische workout-lijst injecteren.
    init(ingestService: WorkoutSampleIngesting,
         store: WorkoutSampleStore,
         userDefaults: UserDefaults,
         daysBack: Int,
         workoutsProvider: @escaping (Date, Date) async throws -> [HKWorkout]) {
        self.ingestService    = ingestService
        self.store            = store
        self.userDefaults     = userDefaults
        self.daysBack         = daysBack
        self.workoutsProvider = workoutsProvider
    }

    // MARK: Public API

    /// True wanneer de eenmalige historische sync volledig is afgerond.
    var hasCompletedInitialDeepSync: Bool {
        userDefaults.bool(forKey: Self.completedFlagKey)
    }

    /// Idempotent — meerdere keren oproepen heeft geen effect zolang de sync al volledig liep.
    /// Geschikt om vanuit `DashboardView.task` te triggeren.
    func runIfNeeded() async {
        guard !hasCompletedInitialDeepSync else { return }

        // Voorkom dubbel-trigger als de view meerdere keren onAppear schiet.
        if case .syncing = status { return }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: endDate) else {
            status = .failed("Kon startdatum niet berekenen")
            return
        }

        do {
            let allWorkouts = try await workoutsProvider(startDate, endDate)
            var processed = loadProcessedUUIDs()
            let pending = allWorkouts.filter { !processed.contains($0.uuid) }

            guard !pending.isEmpty else {
                finalizeIfComplete(processed: processed, allWorkoutUUIDs: Set(allWorkouts.map(\.uuid)))
                return
            }

            status = .syncing(processed: 0, total: pending.count)
            log.info("Starting deep sync — \(pending.count, privacy: .public) pending workout(s) of \(allWorkouts.count, privacy: .public) total")

            // Serieel verwerken — parallel zou HealthKit overbelasten (5 quantity types × N workouts).
            for (i, workout) in pending.enumerated() {
                do {
                    try await ingestService.ingestSamples(for: workout, into: store)
                    processed.insert(workout.uuid)
                    saveProcessedUUIDs(processed)
                } catch {
                    // Eén falende workout mag de rest niet blokkeren — niet-gemarkeerde
                    // UUIDs worden bij de volgende run vanzelf opnieuw geprobeerd.
                    log.error("Skipping workout \(workout.uuid, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                status = .syncing(processed: i + 1, total: pending.count)
            }

            finalizeIfComplete(processed: processed, allWorkoutUUIDs: Set(allWorkouts.map(\.uuid)))
        } catch {
            status = .failed(error.localizedDescription)
            log.error("Deep sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Private

    private func finalizeIfComplete(processed: Set<UUID>, allWorkoutUUIDs: Set<UUID>) {
        if processed.isSuperset(of: allWorkoutUUIDs) {
            // Alles verwerkt — flag aan, processed-set wegruimen (de flag is nu de waarheid).
            userDefaults.set(true, forKey: Self.completedFlagKey)
            userDefaults.removeObject(forKey: Self.processedUUIDsKey)
            status = .completed
            log.info("Deep sync completed — flag set, processed-set cleared")
        } else {
            // Sommige workouts zijn gefaald. Status = completed (run is af),
            // maar flag blijft false zodat next-run ze opnieuw probeert.
            let missing = allWorkoutUUIDs.subtracting(processed).count
            status = .completed
            log.notice("Deep sync round done — \(missing, privacy: .public) workout(s) zullen volgende run opnieuw worden geprobeerd")
        }
    }

    private func loadProcessedUUIDs() -> Set<UUID> {
        guard let data = userDefaults.data(forKey: Self.processedUUIDsKey) else { return [] }
        guard let array = try? JSONDecoder().decode([UUID].self, from: data) else { return [] }
        return Set(array)
    }

    private func saveProcessedUUIDs(_ uuids: Set<UUID>) {
        if let data = try? JSONEncoder().encode(Array(uuids)) {
            userDefaults.set(data, forKey: Self.processedUUIDsKey)
        }
    }

    // MARK: HealthKit fetch (productie)

    private static func fetchWorkouts(healthStore: HKHealthStore, start: Date, end: Date) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(),
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }
}
