import Foundation

// MARK: - Epic 44 Story 44.2: PhysiologicalThresholdEstimator
//
// Pure-Swift derivation of physiological thresholds (max HR, resting HR, LTHR)
// from a collection of HK samples. Deliberately no HK query in this layer — the
// caller does the fetch and passes the samples in. That keeps the estimation
// fully unit-testable and compatible with both HK and future sources (e.g. CSV
// ingest).
//
// Premise: six months of workout-HR samples + daily `restingHeartRate` samples
// together give enough signal for a reliable first estimate. We are conservative
// — stray outliers from sensor errors are filtered, and we require a minimum
// number of samples before we dare to claim anything at all.

enum PhysiologicalThresholdEstimator {

    // MARK: Thresholds & filters

    /// Workouts shorter than 20 minutes are unreliable for max-HR detection:
    /// a short sprint can reach a true max, but most short HK records are
    /// run-walks or cooldowns with spikes from sensor dropout.
    static let minimumWorkoutDurationForMaxHR: TimeInterval = 20 * 60

    /// Sample counts: fewer than 30 data points in a workout = unreliable.
    static let minimumSamplesPerWorkout: Int = 30

    /// HR samples outside this absolute range are sensor errors or jitter.
    /// 200+ is possible, but without context (e.g. a sudden 220 BPM) it's rarely right.
    static let plausibleMaxHRRange: ClosedRange<Double> = 80...220

    /// For resting HR we require at least 14 daily samples; fewer = still too
    /// early to claim a baseline.
    static let minimumRestingHRSamples: Int = 14

    /// LTHR detection requires a high-intensity workout — we look at the highest
    /// 30-minute rolling-average HR. Below this threshold the estimate is just
    /// the average HR of an easy workout, not LTHR.
    static let minimumLTHRWindowSamples: Int = 30
    static let lthrWindowSize: Int = 30  // 30 buckets of 60s = 30 min at 1-minute resolution

    // MARK: Input types

    /// One workout session abstracted for the estimator. The caller maps HK data
    /// or test data to this struct.
    struct WorkoutHRSample {
        /// Start of the workout.
        let startDate: Date
        /// Duration in seconds.
        let durationSeconds: TimeInterval
        /// HR samples in BPM, in chronological order.
        let heartRates: [Double]
    }

    /// Result of an estimation. Any of the values may be nil if there was
    /// insufficient data. The UI shows this as "We still have too little
    /// data — log X more workouts and try again."
    struct Result: Equatable {
        let maxHeartRate: Double?
        let restingHeartRate: Double?
        let lactateThresholdHR: Double?
    }

    // MARK: Estimators

    /// Estimates all three thresholds from the given datasets. Pure function.
    /// - Parameters:
    ///   - workouts: Workout records from the past ~6 months, in arbitrary order.
    ///   - dailyRestingHR: Daily resting-HR samples from HK (average rest per day).
    static func estimate(workouts: [WorkoutHRSample],
                         dailyRestingHR: [Double]) -> Result {
        Result(
            maxHeartRate: estimateMaxHeartRate(workouts: workouts),
            restingHeartRate: estimateRestingHeartRate(samples: dailyRestingHR),
            lactateThresholdHR: estimateLactateThresholdHR(workouts: workouts)
        )
    }

    /// Highest plausible HR peak across all eligible workouts. We don't blindly
    /// take the absolute max — first we filter per workout on duration and
    /// sample count, then we look at the 95th percentile to exclude stray spikes.
    static func estimateMaxHeartRate(workouts: [WorkoutHRSample]) -> Double? {
        var topPercentilePerWorkout: [Double] = []
        for workout in workouts {
            guard workout.durationSeconds >= minimumWorkoutDurationForMaxHR,
                  workout.heartRates.count >= minimumSamplesPerWorkout else { continue }
            let plausible = workout.heartRates.filter { plausibleMaxHRRange.contains($0) }
            guard !plausible.isEmpty else { continue }
            // The 95th percentile within the workout excludes stray jitter spikes.
            let sorted = plausible.sorted()
            let idx = min(sorted.count - 1, Int(Double(sorted.count) * 0.95))
            topPercentilePerWorkout.append(sorted[idx])
        }
        guard !topPercentilePerWorkout.isEmpty else { return nil }
        // At the workout level we do take the true max — this is an athlete who
        // sporadically goes to their peak, so the highest "stable" peak across all
        // workouts is the best estimate of their actual max HR.
        return topPercentilePerWorkout.max()
    }

    /// Median resting HR from the daily samples of the recent period.
    /// Median is more robust than mean — one day with a sensor error from an
    /// Apple Watch on the nightstand doesn't derail a normal baseline.
    static func estimateRestingHeartRate(samples: [Double]) -> Double? {
        let plausible = samples.filter { $0 >= 30 && $0 <= 100 }
        guard plausible.count >= minimumRestingHRSamples else { return nil }
        let sorted = plausible.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    /// LTHR via Friel's protocol equivalent: highest 30-min rolling avg HR from
    /// the hardest workout. Not exact lab LTHR (that requires a 30-min time
    /// trial), but more than sufficient for use in zone calibration.
    /// The caller preferably resamples to 60s buckets before passing the samples —
    /// 30 buckets then neatly covers the 30-min window.
    static func estimateLactateThresholdHR(workouts: [WorkoutHRSample]) -> Double? {
        var perWorkoutHighest: [Double] = []
        for workout in workouts {
            guard workout.heartRates.count >= minimumLTHRWindowSamples else { continue }
            let filtered = workout.heartRates.filter { plausibleMaxHRRange.contains($0) }
            guard filtered.count >= lthrWindowSize else { continue }
            // Rolling 30-window average — take the highest.
            var highest: Double = 0
            for start in 0...(filtered.count - lthrWindowSize) {
                let window = filtered[start..<(start + lthrWindowSize)]
                let avg = window.reduce(0, +) / Double(lthrWindowSize)
                if avg > highest { highest = avg }
            }
            if highest > 0 { perWorkoutHighest.append(highest) }
        }
        guard !perWorkoutHighest.isEmpty else { return nil }
        // Highest across all workouts — corresponding to the hardest 30-min block
        // of the past 6 months, a reasonable proxy for LTHR.
        return perWorkoutHighest.max()
    }
}
