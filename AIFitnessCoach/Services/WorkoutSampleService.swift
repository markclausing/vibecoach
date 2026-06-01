import Foundation
import HealthKit
import SwiftData
import os.log

// MARK: - Epic 32 Story 32.1: WorkoutSampleService
//
// Brings three responsibilities together:
//   1. `WorkoutSampleStore`: thread-safe storage layer (`@ModelActor`).
//   2. `WorkoutSampleIngestService`: HealthKit fetch via `HKQuantitySeriesSampleQuery` + resampling to 5s.
//   3. Per-workout idempotent flow: wipe + insert so re-syncs never produce duplicates.

private let log = Logger(subsystem: "com.markclausing.aifitnesscoach", category: "WorkoutSamples")

// MARK: - Storage (ModelActor)

/// `@ModelActor` ensures all SwiftData mutations run on a background context.
/// No `@MainActor` blocking during a 30-day re-sync of thousands of samples.
@ModelActor
actor WorkoutSampleStore {

    /// Idempotent replacement: existing samples for `workoutUUID` are wiped first,
    /// then the new ones are inserted. Prevents duplicates on re-syncs.
    func replaceSamples(_ samples: [WorkoutSample], forWorkoutUUID workoutUUID: UUID) throws {
        let predicate = #Predicate<WorkoutSample> { $0.workoutUUID == workoutUUID }
        let descriptor = FetchDescriptor<WorkoutSample>(predicate: predicate)
        let existing = try modelContext.fetch(descriptor)
        for sample in existing {
            modelContext.delete(sample)
        }
        for sample in samples {
            modelContext.insert(sample)
        }
        try modelContext.save()
    }

    /// Number of stored samples for a workout. Used by tests and as an idempotency check.
    func sampleCount(forWorkoutUUID workoutUUID: UUID) throws -> Int {
        let predicate = #Predicate<WorkoutSample> { $0.workoutUUID == workoutUUID }
        let descriptor = FetchDescriptor<WorkoutSample>(predicate: predicate)
        return try modelContext.fetchCount(descriptor)
    }

    /// Full sample series for a workout, sorted by timestamp. Used by
    /// `SessionReclassifier` (Epic 40 Story 40.4) and charts.
    func samples(forWorkoutUUID workoutUUID: UUID) throws -> [WorkoutSample] {
        let predicate = #Predicate<WorkoutSample> { $0.workoutUUID == workoutUUID }
        let descriptor = FetchDescriptor<WorkoutSample>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
}

// MARK: - Ingest

/// Fetches physiological time-series data from HealthKit and resamples to 5s buckets.
final class WorkoutSampleIngestService {

    private let healthStore: HKHealthStore
    private let resampler: SampleResampler

    init(healthStore: HKHealthStore = HKHealthStore(), resampler: SampleResampler = SampleResampler()) {
        self.healthStore = healthStore
        self.resampler = resampler
    }

    /// Fully fetch one workout, resample, and idempotently store via the store.
    /// Unavailable metrics (e.g. power on a running workout) silently yield `nil`
    /// instead of an error — that's correct: not every sport measures all five signals.
    func ingestSamples(for workout: HKWorkout, into store: WorkoutSampleStore) async throws {
        let start = workout.startDate
        let end   = workout.endDate

        // Fetch in parallel — all five quantity types are independent.
        async let heartRateSeries = fetchSeries(in: workout, identifier: .heartRate, unit: HKUnit(from: "count/min"))
        async let powerSeries     = fetchSeries(in: workout, identifier: .cyclingPower, unit: .watt())
        async let cadenceSeries   = fetchSeries(in: workout, identifier: cadenceIdentifier(for: workout), unit: HKUnit(from: "count/min"))
        async let speedSeries     = fetchSeries(in: workout, identifier: speedIdentifier(for: workout), unit: HKUnit.meter().unitDivided(by: .second()))
        async let distanceSeries  = fetchSeries(in: workout, identifier: distanceIdentifier(for: workout), unit: .meter())
        // Epic #52: for running there is no `HKQuantityTypeIdentifier.runningCadence`.
        // We derive cadence (steps per minute, spm) from `stepCount` via an
        // `HKStatisticsCollectionQuery` over 5s buckets. Other sports return nil
        // and this series stays empty — no pollution of cycling cadence.
        async let runningCadenceSeries = fetchRunningStepCadence(for: workout)

        let hr             = try await heartRateSeries
        let power          = try await powerSeries
        let cadenceNative  = try await cadenceSeries
        let speed          = try await speedSeries
        let distance       = try await distanceSeries
        let runningCadence = try await runningCadenceSeries
        // Cycling cadence beats the derived running cadence (source priority).
        // For running, `cadenceNative` is by definition empty (cadenceIdentifier nil),
        // so we automatically fall back to the stepCount-derived spm series.
        let cadence = cadenceNative.isEmpty ? runningCadence : cadenceNative

        // Resample each signal according to its physiologically correct strategy.
        let hrBuckets       = resampler.resample(samples: hr, from: start, to: end, strategy: .average)
        let powerBuckets    = resampler.resample(samples: power, from: start, to: end, strategy: .average)
        let cadenceBuckets  = resampler.resample(samples: cadence, from: start, to: end, strategy: .average)
        let speedBuckets    = resampler.resample(samples: speed, from: start, to: end, strategy: .linearInterpolation)
        let distanceBuckets = resampler.resample(samples: distance, from: start, to: end, strategy: .deltaAccumulation)

        // Combine per bucket timestamp into one WorkoutSample. We use the heart-rate buckets
        // as the canonical grid — all resamplers produce identical timestamps (same start/end/bucketSize).
        let workoutUUID = workout.uuid
        let combined: [WorkoutSample] = hrBuckets.indices.compactMap { i in
            let timestamp = hrBuckets[i].timestamp
            let hrValue   = hrBuckets[i].value
            let pwValue   = powerBuckets.indices.contains(i)    ? powerBuckets[i].value    : nil
            let cdValue   = cadenceBuckets.indices.contains(i)  ? cadenceBuckets[i].value  : nil
            let spValue   = speedBuckets.indices.contains(i)    ? speedBuckets[i].value    : nil
            let dsValue   = distanceBuckets.indices.contains(i) ? distanceBuckets[i].value : nil

            // Don't store buckets without any measurement — saves storage and keeps queries lean.
            if hrValue == nil && pwValue == nil && cdValue == nil && spValue == nil && dsValue == nil {
                return nil
            }
            return WorkoutSample(
                workoutUUID: workoutUUID,
                timestamp: timestamp,
                heartRate: hrValue,
                speed: spValue,
                power: pwValue,
                cadence: cdValue,
                distance: dsValue
            )
        }

        log.info("Ingested \(combined.count, privacy: .public) samples for workout \(workoutUUID, privacy: .public)")
        try await store.replaceSamples(combined, forWorkoutUUID: workoutUUID)
    }

    // MARK: Private — HealthKit fetch

    /// Fetches all (quantity, date) pairs within the workout window via `HKQuantitySeriesSampleQuery`.
    /// Works on both series samples (Apple Watch beat-to-beat HR) and individual samples.
    /// Returns an empty array for unsupported types or missing permission — no error.
    private func fetchSeries(in workout: HKWorkout,
                             identifier: HKQuantityTypeIdentifier?,
                             unit: HKUnit) async throws -> [TimedValue] {
        guard let identifier, let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate,
                                                    end: workout.endDate,
                                                    options: .strictStartDate)

        // Step 1: fetch all parent quantity samples within the workout window.
        let parentSamples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType,
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        guard !parentSamples.isEmpty else { return [] }

        // Step 2: fetch the series ticks per parent sample. For non-series samples you get one tick per call.
        var collected: [TimedValue] = []
        for parent in parentSamples {
            let ticks = try await fetchSeriesTicks(for: parent, unit: unit)
            collected.append(contentsOf: ticks)
        }
        return collected
    }

    private func fetchSeriesTicks(for sample: HKQuantitySample, unit: HKUnit) async throws -> [TimedValue] {
        // iOS 18+: `HKQuantitySeriesSampleQueryDescriptor` replaces the `init(sample:)`
        // closure API (deprecated since iOS 13). Native async iteration — no
        // `withCheckedThrowingContinuation` dance needed and no deprecation warning.
        let predicate = HKSamplePredicate.quantitySample(
            type: sample.quantityType,
            predicate: HKQuery.predicateForObject(with: sample.uuid)
        )
        let descriptor = HKQuantitySeriesSampleQueryDescriptor(predicate: predicate)
        var buffer: [TimedValue] = []
        for try await result in descriptor.results(for: healthStore) {
            buffer.append(TimedValue(
                timestamp: result.dateInterval.start,
                value: result.quantity.doubleValue(for: unit)
            ))
        }
        return buffer
    }

    // MARK: Sport-specific quantity-type choices

    /// Distance type depends on the workout: `running`, `cycling`, `swimming` or nil for types without distance.
    private func distanceIdentifier(for workout: HKWorkout) -> HKQuantityTypeIdentifier? {
        switch workout.workoutActivityType {
        case .running, .walking, .hiking:
            return .distanceWalkingRunning
        case .cycling:
            return .distanceCycling
        case .swimming:
            return .distanceSwimming
        default:
            return nil
        }
    }

    /// Speed type — only `runningSpeed` is broadly available. For other sports we derive
    /// speed in a later story from the distance delta. For now: nil → no speed samples.
    private func speedIdentifier(for workout: HKWorkout) -> HKQuantityTypeIdentifier? {
        switch workout.workoutActivityType {
        case .running:
            return .runningSpeed
        default:
            return nil
        }
    }

    /// Cadence type — `cyclingCadence` for cycling. Running has no native
    /// HK cadence identifier; for running we use `fetchRunningStepCadence`
    /// (Epic #52) which aggregates stepCount via a StatisticsCollectionQuery.
    private func cadenceIdentifier(for workout: HKWorkout) -> HKQuantityTypeIdentifier? {
        switch workout.workoutActivityType {
        case .cycling:
            return .cyclingCadence
        default:
            return nil
        }
    }

    // MARK: - Epic #52: running cadence from stepCount

    /// Aggregates HealthKit `stepCount` over 5s buckets and converts to SPM
    /// (steps per minute). Only for running/walking/hiking — other sports return
    /// an empty array so the signal doesn't sneak into cycling cadence.
    ///
    /// **Why StatisticsCollectionQuery and not the existing `fetchSeries`?**
    /// `stepCount` is a `cumulativeQuantityType`, not a rate. Per-sample ticks via
    /// `HKQuantitySeriesSampleQueryDescriptor` give varying interval lengths (Apple
    /// Watch sometimes logs per 10s, sometimes per 30s). An explicit 5s-bucket query
    /// with `cumulativeSum` statistics yields a guaranteed uniform grid that maps
    /// 1-on-1 onto the other signals. Conversion: `(steps_in_5s_bucket / 5) * 60 = spm`.
    private func fetchRunningStepCadence(for workout: HKWorkout) async throws -> [TimedValue] {
        switch workout.workoutActivityType {
        case .running, .walking, .hiking:
            break
        default:
            return []
        }
        return try await fetchStepCadence(start: workout.startDate, end: workout.endDate)
    }

    /// Cadence series (spm) for a time window — independent of a specific `HKWorkout`.
    ///
    /// **Epic #52 follow-up (cross-source fix):** the displayed `ActivityRecord` may
    /// be a Strava record that "won" dedup against an HK counterpart (Strava
    /// `device_watts` scores higher). The Apple Watch `stepCount` data then lives
    /// under the HK workout UUID, while the view queries samples under the Strava
    /// UUID — so cadence goes missing. A query on pure `[start, end]` bypasses that
    /// UUID fragmentation: HealthKit deduplicates `stepCount` itself across sources,
    /// so we get the Watch steps regardless of which record won.
    ///
    /// Callable from the view layer (`WorkoutAnalysisView`) when the stored samples
    /// contain no cadence.
    func fetchStepCadence(start: Date, end: Date) async throws -> [TimedValue] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return []
        }
        guard end > start else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let bucketSize = resampler.bucketSeconds
        let bucket = DateComponents(second: Int(bucketSize))

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[TimedValue], Error>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: bucket
            )
            query.initialResultsHandler = { _, statsCollection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let statsCollection else {
                    continuation.resume(returning: [])
                    return
                }
                var samples: [TimedValue] = []
                statsCollection.enumerateStatistics(from: start, to: end) { stats, _ in
                    guard let sum = stats.sumQuantity() else { return }
                    let steps = sum.doubleValue(for: .count())
                    // SPM = (steps / 5s) * 60. One step per 5s = 12 spm (very slow walking).
                    let spm = (steps / bucketSize) * 60.0
                    samples.append(TimedValue(timestamp: stats.startDate, value: spm))
                }
                continuation.resume(returning: samples)
            }
            healthStore.execute(query)
        }
    }
}
