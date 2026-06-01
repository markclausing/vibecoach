import Foundation

// MARK: - Epic 32 Story 32.2: WorkoutAnalysisHelpers
//
// Pure-Swift helpers that keep `WorkoutAnalysisView` testable without pulling in SwiftUI/Charts.

/// Which metric is shown in the bottom chart.
/// Cyclists mostly look at power; runners at speed.
enum SecondarySeries: Equatable {
    case speed
    case power
    case none
}

enum WorkoutAnalysisHelpers {

    /// Finds the sample with the timestamp closest to `targetDate`.
    /// `samples` may be supplied in any order — we do an O(n) linear scan
    /// (for ~720 samples per workout that is well within one frame at 60fps).
    static func nearestSample<S>(at targetDate: Date,
                                 in samples: [S],
                                 timestamp: (S) -> Date) -> S? {
        guard let first = samples.first else { return nil }

        var best = first
        var bestDelta = abs(timestamp(first).timeIntervalSince(targetDate))

        for sample in samples.dropFirst() {
            let delta = abs(timestamp(sample).timeIntervalSince(targetDate))
            if delta < bestDelta {
                bestDelta = delta
                best = sample
            }
        }
        return best
    }

    /// Determines which metric the secondary chart shows based on sport category and
    /// the measurement data actually available. Preference:
    ///   • Cycling + power data → power
    ///   • Otherwise with speed data → speed
    ///   • Otherwise with power data → power
    ///   • Otherwise → none (chart is hidden)
    static func chooseSecondarySeries(sportCategory: String?,
                                      hasSpeed: Bool,
                                      hasPower: Bool) -> SecondarySeries {
        if sportCategory == "cycling", hasPower {
            return .power
        }
        if hasSpeed {
            return .speed
        }
        if hasPower {
            return .power
        }
        return .none
    }
}
