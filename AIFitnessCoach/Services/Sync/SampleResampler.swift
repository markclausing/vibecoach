import Foundation

// MARK: - Epic 32 Story 32.1: SampleResampler
//
// Pure-Swift resampling of irregular HealthKit time-series data into fixed 5s buckets.
// No HealthKit dependency so the logic is fully testable with synthetic input.

/// One measurement point — timestamp + numeric value.
/// A generic representation so we can run HR/Power/Cadence/Speed/Distance all through the same resampler.
struct TimedValue: Equatable {
    let timestamp: Date
    let value: Double
}

/// The strategy by which irregular samples are reduced to one 5s bucket.
enum ResampleStrategy {
    /// Average of all samples within the bucket window. Suitable for: HR, Power, Cadence.
    case average
    /// Linearly interpolated to the bucket start based on the two nearest samples.
    /// Suitable for signals where the instantaneous value is more meaningful than an average — e.g. speed.
    case linearInterpolation
    /// Sum of all values within the bucket window. Suitable for cumulative measurements — e.g. distance deltas.
    case deltaAccumulation
}

struct SampleResampler {
    /// Bucket size in seconds. Fixed at 5 for Story 32.1.
    let bucketSeconds: TimeInterval

    init(bucketSeconds: TimeInterval = 5) {
        self.bucketSeconds = bucketSeconds
    }

    /// Generates all bucket start timestamps from `start` up to strictly before `end`.
    /// Empty workout windows (start ≥ end) yield an empty array.
    func bucketStarts(from start: Date, to end: Date) -> [Date] {
        guard end > start, bucketSeconds > 0 else { return [] }
        var result: [Date] = []
        var t = start
        while t < end {
            result.append(t)
            t = t.addingTimeInterval(bucketSeconds)
        }
        return result
    }

    /// Resamples `samples` into 5s buckets within [`start`, `end`) according to the chosen strategy.
    /// Empty buckets are returned as `nil` — never fill with 0 (that would deceive downstream analyses).
    func resample(samples: [TimedValue],
                  from start: Date,
                  to end: Date,
                  strategy: ResampleStrategy) -> [(timestamp: Date, value: Double?)] {
        let starts = bucketStarts(from: start, to: end)
        guard !starts.isEmpty else { return [] }

        // Sort for robustness — HealthKit usually guarantees order, but tests/mocks often don't.
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }

        switch strategy {
        case .average:
            return starts.map { bucketStart in
                let bucketEnd = bucketStart.addingTimeInterval(bucketSeconds)
                let inBucket = sorted.filter { $0.timestamp >= bucketStart && $0.timestamp < bucketEnd }
                guard !inBucket.isEmpty else { return (bucketStart, nil) }
                let avg = inBucket.map(\.value).reduce(0, +) / Double(inBucket.count)
                return (bucketStart, avg)
            }

        case .linearInterpolation:
            return starts.map { bucketStart in
                (bucketStart, interpolate(at: bucketStart, in: sorted))
            }

        case .deltaAccumulation:
            return starts.map { bucketStart in
                let bucketEnd = bucketStart.addingTimeInterval(bucketSeconds)
                let inBucket = sorted.filter { $0.timestamp >= bucketStart && $0.timestamp < bucketEnd }
                guard !inBucket.isEmpty else { return (bucketStart, nil) }
                let sum = inBucket.map(\.value).reduce(0, +)
                return (bucketStart, sum)
            }
        }
    }

    // MARK: Private helpers

    /// Linear interpolation to time `t` based on a sorted sample series.
    /// Returns nil if `t` is out of range — extrapolation is unreliable across GPS gaps.
    private func interpolate(at t: Date, in sortedSamples: [TimedValue]) -> Double? {
        guard let first = sortedSamples.first, let last = sortedSamples.last else { return nil }
        if t < first.timestamp || t > last.timestamp { return nil }

        // Exact match — happens with synthetic tests and samples that fall exactly on a bucket boundary.
        if let exact = sortedSamples.first(where: { $0.timestamp == t }) {
            return exact.value
        }

        // Find the pair (previous, next) `t` lies between.
        for i in 0..<(sortedSamples.count - 1) {
            let a = sortedSamples[i]
            let b = sortedSamples[i + 1]
            if a.timestamp <= t && t <= b.timestamp {
                let span = b.timestamp.timeIntervalSince(a.timestamp)
                guard span > 0 else { return a.value }
                let progress = t.timeIntervalSince(a.timestamp) / span
                return a.value + (b.value - a.value) * progress
            }
        }
        return nil
    }
}
