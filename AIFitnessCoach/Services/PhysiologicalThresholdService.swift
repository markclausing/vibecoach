import Foundation
import HealthKit
import os

// MARK: - Epic 44 Story 44.4: PhysiologicalThresholdService
//
// HK adapter around `PhysiologicalThresholdEstimator`. Fetches 6 months of
// workouts + daily resting-HR samples from HealthKit, maps them to the
// `WorkoutHRSample` input of the pure-Swift estimator, and then kicks off
// `UserProfileService.storeAutoDetectedThresholds` so the thresholds land in
// UserDefaults (manual values stay protected).
//
// The caller (`Settings` detect button) only has to call `runAutoDetect()`
// and render the `Result`. No UI state, no MainActor — the service is
// AppStorage-free and injectable for future tests.

@MainActor
final class PhysiologicalThresholdService {

    // The logger lives centrally in `AppLoggers.physiologicalThreshold`.

    /// Period over which we fetch HK data for the detection.
    private static let lookbackDays: Int = 180

    /// 60s bucket size for the LTHR rolling window. Matches the 30-sample window
    /// (= 30 minutes) in `PhysiologicalThresholdEstimator`.
    private static let lthrBucketSeconds: TimeInterval = 60

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    /// Result of a detection run: the derived thresholds + how much data
    /// backed them so the UI can show "we used N workouts and M days of
    /// resting HR".
    struct DetectionRun: Equatable {
        let result: PhysiologicalThresholdEstimator.Result
        let workoutsAnalyzed: Int
        let restingDaysAnalyzed: Int
    }

    /// Runs a full auto-detection and stores the found values via
    /// `UserProfileService.storeAutoDetectedThresholds` (respects manual input
    /// by default). Returns the raw result so the UI can immediately reflect
    /// what was detected.
    /// - Parameter persist: Also store the result right away (default true). Tests
    ///   set this to false so they can validate the persistence flow separately.
    @discardableResult
    func runAutoDetect(persist: Bool = true) async -> DetectionRun {
        guard HKHealthStore.isHealthDataAvailable() else {
            return DetectionRun(result: emptyResult, workoutsAnalyzed: 0, restingDaysAnalyzed: 0)
        }

        let now = Date()
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -Self.lookbackDays, to: now) else {
            return DetectionRun(result: emptyResult, workoutsAnalyzed: 0, restingDaysAnalyzed: 0)
        }

        let workoutSamples = await fetchWorkoutHRSamples(from: cutoff, to: now)
        let restingSamples = await fetchDailyRestingHR(from: cutoff, to: now)
        let result = PhysiologicalThresholdEstimator.estimate(
            workouts: workoutSamples,
            dailyRestingHR: restingSamples
        )

        if persist {
            UserProfileService.storeAutoDetectedThresholds(result)
        }

        AppLoggers.physiologicalThreshold.info("Auto-detect klaar — \(workoutSamples.count, privacy: .public) workouts, \(restingSamples.count, privacy: .public) rust-dagen")

        return DetectionRun(
            result: result,
            workoutsAnalyzed: workoutSamples.count,
            restingDaysAnalyzed: restingSamples.count
        )
    }

    private var emptyResult: PhysiologicalThresholdEstimator.Result {
        .init(maxHeartRate: nil, restingHeartRate: nil, lactateThresholdHR: nil)
    }

    // MARK: - HK fetches

    /// Fetches all workouts in the window and maps them to `WorkoutHRSample`.
    /// A separate HR query is done per workout to get the samples; these can be
    /// ~720 samples per workout, but over 6 months the total stays well within
    /// what HK can return to us in a single run.
    private func fetchWorkoutHRSamples(from start: Date, to end: Date) async -> [PhysiologicalThresholdEstimator.WorkoutHRSample] {
        let workouts = await fetchWorkouts(from: start, to: end)
        var results: [PhysiologicalThresholdEstimator.WorkoutHRSample] = []
        for workout in workouts {
            let hrSamples = await fetchHeartRateSamples(for: workout)
            // Resample to 60s buckets for LTHR; bucket averages dampen sensor
            // noise and keep the estimator input small.
            let bucketed = bucketAverages(samples: hrSamples,
                                           start: workout.startDate,
                                           end: workout.endDate,
                                           bucketSize: Self.lthrBucketSeconds)
            results.append(.init(
                startDate: workout.startDate,
                durationSeconds: workout.duration,
                heartRates: bucketed
            ))
        }
        return results
    }

    private func fetchWorkouts(from start: Date, to end: Date) async -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func fetchHeartRateSamples(for workout: HKWorkout) async -> [HKQuantitySample] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate,
                                                     end: workout.endDate,
                                                     options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    /// HK provides a daily `restingHeartRate` sample. We use it directly as
    /// input for the median calculation — no filter on duration or activity
    /// needed, since HK has already done that itself.
    private func fetchDailyRestingHR(from start: Date, to end: Date) async -> [Double] {
        guard let restType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: restType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?
                    .map { $0.quantity.doubleValue(for: unit) }
                    .filter { $0 > 0 } ?? []
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Resampling

    /// Bucket-average resampler: splits the time window into fixed-size buckets
    /// and returns, per bucket, the average of the samples that fall in it.
    /// Empty buckets are dropped (not emitted as 0) — the estimator filters
    /// those out anyway via its plausibility range. Conservative and pure-Swift.
    private func bucketAverages(samples: [HKQuantitySample],
                                start: Date,
                                end: Date,
                                bucketSize: TimeInterval) -> [Double] {
        guard end > start, bucketSize > 0 else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let totalSeconds = end.timeIntervalSince(start)
        let bucketCount = Int((totalSeconds / bucketSize).rounded(.up))
        guard bucketCount > 0 else { return [] }

        var sums = Array(repeating: 0.0, count: bucketCount)
        var counts = Array(repeating: 0, count: bucketCount)

        for sample in samples {
            let offset = sample.startDate.timeIntervalSince(start)
            guard offset >= 0, offset < totalSeconds else { continue }
            let idx = min(bucketCount - 1, Int(offset / bucketSize))
            sums[idx] += sample.quantity.doubleValue(for: unit)
            counts[idx] += 1
        }

        var output: [Double] = []
        output.reserveCapacity(bucketCount)
        for i in 0..<bucketCount where counts[i] > 0 {
            output.append(sums[i] / Double(counts[i]))
        }
        return output
    }
}
