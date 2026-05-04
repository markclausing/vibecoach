import Foundation
import HealthKit
import os

// MARK: - Epic 44 Story 44.4: PhysiologicalThresholdService
//
// HK-adapter rond `PhysiologicalThresholdEstimator`. Vraagt 6 maanden aan
// workouts + dagelijkse rust-HR-samples op uit HealthKit, mapt ze naar de
// `WorkoutHRSample`-input van de pure-Swift estimator, en kickt vervolgens
// `UserProfileService.storeAutoDetectedThresholds` af zodat de drempels in
// UserDefaults landen (handmatige waarden blijven beschermd).
//
// Caller (`Settings`-detect-knop) hoeft alleen `runAutoDetect()` aan te roepen
// en het `Result` weer te geven. Geen UI-state, geen MainActor — service is
// AppStorage-vrij en injecteerbaar voor toekomstige tests.

@MainActor
final class PhysiologicalThresholdService {

    // Logger leeft centraal in `AppLoggers.physiologicalThreshold`.

    /// Periode waarover we HK-data ophalen voor de detectie.
    private static let lookbackDays: Int = 180

    /// 60s-bucket-grootte voor LTHR-rolling-window. Past bij de 30-sample-window
    /// (= 30 minuten) in `PhysiologicalThresholdEstimator`.
    private static let lthrBucketSeconds: TimeInterval = 60

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    /// Resultaat van een detection-run: de afgeleide drempels + hoeveel data
    /// erachter zat zodat de UI kan tonen "we hebben N workouts en M dagen
    /// rust-HR gebruikt".
    struct DetectionRun: Equatable {
        let result: PhysiologicalThresholdEstimator.Result
        let workoutsAnalyzed: Int
        let restingDaysAnalyzed: Int
    }

    /// Voert een volledige auto-detectie uit en bewaart de gevonden waardes via
    /// `UserProfileService.storeAutoDetectedThresholds` (respecteert standaard
    /// handmatige invoer). Returnt het ruwe resultaat zodat de UI direct kan
    /// reflecteren wat er gedetecteerd werd.
    /// - Parameter persist: Bewaar het resultaat ook direct (default true). Tests
    ///   zetten dit op false zodat ze de persistence-flow apart kunnen valideren.
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

    /// Haalt alle workouts in het venster op en mapt ze naar `WorkoutHRSample`.
    /// Per workout wordt een eigen HR-query gedaan om de samples te krijgen;
    /// deze kunnen ~720 samples per workout zijn maar over 6 maanden valt het
    /// totaal ruim binnen wat HK ons in één run kan teruggeven.
    private func fetchWorkoutHRSamples(from start: Date, to end: Date) async -> [PhysiologicalThresholdEstimator.WorkoutHRSample] {
        let workouts = await fetchWorkouts(from: start, to: end)
        var results: [PhysiologicalThresholdEstimator.WorkoutHRSample] = []
        for workout in workouts {
            let hrSamples = await fetchHeartRateSamples(for: workout)
            // Resampling naar 60s-buckets voor LTHR; bucket-gemiddeldes dempen
            // sensorruis en houden de input voor de estimator klein.
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

    /// HK levert dagelijks een `restingHeartRate`-sample. We gebruiken die als
    /// directe input voor de mediaan-berekening — geen filter nodig op duur of
    /// activiteit, want HK heeft dat zelf al gedaan.
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

    /// Bucket-gemiddelde resampler: deelt het tijdsvenster in fixed-size buckets
    /// en levert per bucket het gemiddelde van de samples die in dat bucket
    /// vallen. Lege buckets worden als 0 weggelaten — de estimator filtert die
    /// alsnog via z'n plausibility-range. Conservatief en pure-Swift.
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
        for i in 0..<bucketCount {
            if counts[i] > 0 {
                output.append(sums[i] / Double(counts[i]))
            }
        }
        return output
    }
}
