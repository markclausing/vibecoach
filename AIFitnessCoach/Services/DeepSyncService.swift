import Foundation
import HealthKit
import SwiftData
import os.log

// MARK: - Epic 32 Story 32.1: 30-daagse Deep Sync Orchestrator
//
// Doorlopende historische sync: alle HKWorkouts uit de afgelopen 30 dagen worden door de
// `WorkoutSampleIngestService` gehaald zodat de `WorkoutSample`-store gevuld is voor
// fysiologische analyses (Story 32.2 + 32.3).
//
// Idempotentie & hervatting:
//   • `processedWorkoutUUIDs` (UserDefaults, JSON-encoded UUID-set) is permanent — per
//     succesvol verwerkte workout direct weggeschreven, en blijft over runs heen zodat
//     reeds-binnen-gehaalde samples niet opnieuw gefetched worden.
//   • Faalt één workout? Loggen en doorgaan met de rest. Niet-gemarkeerde UUIDs worden
//     bij de volgende run vanzelf opnieuw geprobeerd.
//   • Geen one-shot guard meer: `runIfNeeded()` draait bij élke trigger door. Een
//     nieuwe workout vanuit auto-sync wordt zo binnen één view-refresh opgepakt
//     i.p.v. eeuwig op de "Deep Sync loopt"-placeholder te blijven hangen
//     (#fix-workout-samples-loading — voorheen blokkeerde de legacy completion-flag
//     elke run na de eerste backfill).

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
    /// Epic #52: ingest-revisie — bumpen zodra `WorkoutSampleService.ingestSamples`
    /// een nieuw signaal gaat fetchen waardoor bestaande samples op de store
    /// onvolledig zijn. Bij launch met een lagere of ontbrekende revisie clear
    /// `runIfNeeded()` de processed-set zodat álle workouts in het 30-daagse
    /// venster opnieuw worden geïngestred — éénmalig, in achtergrond.
    static let ingestRevisionKey  = "DeepSync.ingestRevision"

    /// Huidige ingest-revisie. Bump dit bij élke wijziging in `WorkoutSampleService`
    /// die nieuwe samples ophaalt voor bestaande workouts.
    /// - 1 (impliciet voor nil): Epic #32 — HR, power, cadence (cycling), speed, distance
    /// - 2: Epic #52 — running cadence via `stepCount`
    static let currentIngestRevision = 2

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

    /// Legacy-flag uit het oorspronkelijke "eenmalige backfill"-ontwerp. Wordt niet
    /// meer geschreven; alleen behouden zodat oude installaties hem niet als stale
    /// data laten staan en bestaande tests/migraties hem kunnen blijven lezen.
    /// Gebruik voor productiebeslissingen: kijk naar `status` of de processed-set.
    var hasCompletedInitialDeepSync: Bool {
        userDefaults.bool(forKey: Self.completedFlagKey)
    }

    /// Idempotent — kan vrij vaak getriggerd worden (bij elke DashboardView.task en
    /// vanuit auto-sync na nieuwe HK-imports). De `processed`-UUID-set zorgt dat
    /// reeds-binnen-gehaalde samples niet opnieuw worden gefetched.
    func runIfNeeded() async {
        // Voorkom dubbel-trigger als de view meerdere keren onAppear schiet of
        // auto-sync en .task tegelijk firen.
        if case .syncing = status { return }

        // Epic #52: ingest-revisie-bump triggert eenmalige re-ingest van alle
        // workouts in het venster, zodat nieuwe signalen (running cadence uit
        // stepCount) ook voor reeds-bestaande HK-workouts beschikbaar komen.
        applyIngestRevisionMigrationIfNeeded()

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
        // De processed-set wordt nooit meer gewist: hij is single-source-of-truth voor
        // dedupe over runs heen. Nieuwe workouts uit auto-sync krijgen samples
        // doordat hun UUID niet in de set staat — runIfNeeded() pikt ze op bij de
        // eerstvolgende trigger zonder dat een legacy completion-flag de boel blokkeert.
        if processed.isSuperset(of: allWorkoutUUIDs) {
            status = .completed
            log.info("Deep sync round done — alle \(allWorkoutUUIDs.count, privacy: .public) workout(s) in venster hebben samples")
        } else {
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

    /// Epic #52: éénmalige migratie bij ingest-revisie-bump. Wist de processed-set
    /// zodat álle workouts in het 30-daagse venster opnieuw worden geïngestred.
    /// `replaceSamples` in `WorkoutSampleStore` is idempotent — bestaande samples
    /// per workout-UUID worden gewist en vervangen door de nieuwe rijkere reeks
    /// (inclusief running cadence). Geen data-verlies; alleen tijdelijke extra
    /// HK-quantity-fetches bij eerstvolgende run.
    private func applyIngestRevisionMigrationIfNeeded() {
        let stored = userDefaults.integer(forKey: Self.ingestRevisionKey)
        guard stored < Self.currentIngestRevision else { return }

        log.info("Ingest-revisie-bump van \(stored, privacy: .public) → \(Self.currentIngestRevision, privacy: .public): processed-set wissen voor re-ingest")
        userDefaults.removeObject(forKey: Self.processedUUIDsKey)
        userDefaults.removeObject(forKey: Self.completedFlagKey)
        userDefaults.set(Self.currentIngestRevision, forKey: Self.ingestRevisionKey)
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
