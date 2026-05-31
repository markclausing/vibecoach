import Foundation
import HealthKit
import SwiftData
import os.log

// MARK: - Epic 32 Story 32.1: 30-day Deep Sync Orchestrator
//
// Continuous historical sync: all HKWorkouts from the past 30 days are run through the
// `WorkoutSampleIngestService` so the `WorkoutSample` store is populated for
// physiological analyses (Story 32.2 + 32.3).
//
// Idempotency & resumption:
//   • `processedWorkoutUUIDs` (UserDefaults, JSON-encoded UUID set) is permanent —
//     written immediately per successfully processed workout, and persists across runs
//     so already-fetched samples aren't fetched again.
//   • A workout fails? Log it and continue with the rest. Unmarked UUIDs are
//     automatically retried on the next run.
//   • No more one-shot guard: `runIfNeeded()` runs on every trigger. A new workout
//     from auto-sync is thus picked up within one view refresh instead of forever
//     hanging on the "Deep Sync running" placeholder
//     (#fix-workout-samples-loading — previously the legacy completion flag blocked
//     every run after the first backfill).

private let log = Logger(subsystem: "com.markclausing.aifitnesscoach", category: "DeepSync")

/// Abstraction over `WorkoutSampleIngestService` so the orchestrator is unit-testable
/// without touching a real HealthKit.
protocol WorkoutSampleIngesting {
    func ingestSamples(for workout: HKWorkout, into store: WorkoutSampleStore) async throws
}

extension WorkoutSampleIngestService: WorkoutSampleIngesting {}

@MainActor
final class DeepSyncService: ObservableObject {

    /// Status for future UI binding (Story 32.2). For now fire-and-forget.
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
    /// Epic #52: ingest revision — bump it as soon as `WorkoutSampleService.ingestSamples`
    /// starts fetching a new signal that makes existing samples in the store
    /// incomplete. At launch with a lower or missing revision, `runIfNeeded()` clears
    /// the processed set so all workouts in the 30-day window are re-ingested —
    /// once, in the background.
    static let ingestRevisionKey  = "DeepSync.ingestRevision"

    /// Current ingest revision. Bump this on every change in `WorkoutSampleService`
    /// that fetches new samples for existing workouts.
    /// - 1 (implicit for nil): Epic #32 — HR, power, cadence (cycling), speed, distance
    /// - 2: Epic #52 — running cadence via `stepCount`
    static let currentIngestRevision = 2

    /// Production init — uses `HKHealthStore` for fetching workouts.
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

    /// Test init — lets the caller inject a synthetic workout list.
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

    /// Legacy flag from the original "one-time backfill" design. No longer written;
    /// kept only so old installs don't leave it as stale data and existing
    /// tests/migrations can keep reading it.
    /// For production decisions: look at `status` or the processed set.
    var hasCompletedInitialDeepSync: Bool {
        userDefaults.bool(forKey: Self.completedFlagKey)
    }

    /// Idempotent — can be triggered fairly often (on every DashboardView.task and
    /// from auto-sync after new HK imports). The `processed` UUID set ensures
    /// already-fetched samples aren't fetched again.
    func runIfNeeded() async {
        // Prevent a double trigger if the view fires onAppear multiple times or
        // auto-sync and .task fire at the same time.
        if case .syncing = status { return }

        // Epic #52: an ingest-revision bump triggers a one-time re-ingest of all
        // workouts in the window, so new signals (running cadence from stepCount)
        // also become available for already-existing HK workouts.
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

            // Process serially — parallel would overload HealthKit (5 quantity types × N workouts).
            for (i, workout) in pending.enumerated() {
                do {
                    try await ingestService.ingestSamples(for: workout, into: store)
                    processed.insert(workout.uuid)
                    saveProcessedUUIDs(processed)
                } catch {
                    // One failing workout must not block the rest — unmarked
                    // UUIDs are automatically retried on the next run.
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
        // The processed set is never cleared again: it's the single source of truth for
        // dedupe across runs. New workouts from auto-sync get samples because their
        // UUID isn't in the set — runIfNeeded() picks them up on the next trigger
        // without a legacy completion flag blocking everything.
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

    /// Epic #52: one-time migration on an ingest-revision bump. Clears the processed
    /// set so all workouts in the 30-day window are re-ingested.
    /// `replaceSamples` in `WorkoutSampleStore` is idempotent — existing samples per
    /// workout UUID are wiped and replaced by the new richer series (including
    /// running cadence). No data loss; only temporary extra HK quantity fetches on
    /// the next run.
    private func applyIngestRevisionMigrationIfNeeded() {
        let stored = userDefaults.integer(forKey: Self.ingestRevisionKey)
        guard stored < Self.currentIngestRevision else { return }

        log.info("Ingest-revisie-bump van \(stored, privacy: .public) → \(Self.currentIngestRevision, privacy: .public): processed-set wissen voor re-ingest")
        userDefaults.removeObject(forKey: Self.processedUUIDsKey)
        userDefaults.removeObject(forKey: Self.completedFlagKey)
        userDefaults.set(Self.currentIngestRevision, forKey: Self.ingestRevisionKey)
    }

    // MARK: HealthKit fetch (production)

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
