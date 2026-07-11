import Foundation

/// Epic #72 story 72.6: linear weekly-volume ramp from the athlete's actual volume at plan
/// start toward the blueprint's peak weekly volume, reached at taper start; during taper the
/// weekly target is peak × taperFactor. Replaces the static blueprint-weekly × phase-weeks
/// arithmetic in the gap analysis, so the cumulative targets (and the expected-today marker)
/// start where the athlete actually is. Pure Swift; the caller injects all dates and volumes.
enum WeeklyVolumeRamp {

    struct Model: Equatable {
        let planStart: Date      // goal.createdAt
        let taperStart: Date     // start of the taper window (PhaseWindowCalculator)
        let startWeekly: Double  // athlete's trailing 4-week weekly average at plan start
        let peakWeekly: Double   // blueprint's weekly target (reached at taper start)
        let taperFactor: Double  // TrainingPhase.tapering.multiplier (0.60)
    }

    /// Weekly target at `date`:
    ///  - on/after `taperStart` → `peakWeekly * taperFactor`
    ///  - before: linear interpolation from `startWeekly` (at planStart) to `peakWeekly`
    ///    (at taperStart), fraction computed with `calendar.fractionalDays` (§3, never raw
    ///    TimeInterval division) and clamped to 0...1
    ///  - if `startWeekly >= peakWeekly`: flat `peakWeekly` before taper (never ramp DOWN)
    ///  - degenerate window (taperStart <= planStart): flat `peakWeekly` before taper
    static func weeklyTarget(at date: Date, model: Model, calendar: Calendar = .current) -> Double {
        if date >= model.taperStart {
            return model.peakWeekly * model.taperFactor
        }
        return rampValue(at: date, model: model, calendar: calendar)
    }

    /// Exact cumulative volume between two dates under the model, in weekly-units × weeks:
    /// piecewise — trapezoid over the linear segment (average of the two endpoint weekly
    /// targets × elapsed weeks) + constant taper segment. Returns 0 for from >= to.
    static func cumulativeTarget(from: Date, to: Date, model: Model, calendar: Calendar = .current) -> Double {
        guard from < to else { return 0 }
        var total = 0.0

        // Linear (or flat/degenerate) segment before taperStart. Uses `rampValue` — not the
        // public `weeklyTarget` — at the segment end so the trapezoid integrates the ramp's own
        // continuous formula up to taperStart (which reaches exactly `peakWeekly`), rather than
        // the taper-regime value the discontinuity at taperStart would otherwise introduce.
        if from < model.taperStart {
            let segEnd = min(to, model.taperStart)
            let days = calendar.fractionalDays(from: from, to: segEnd)
            if days > 0 {
                let weeks = days / 7.0
                let avg = (rampValue(at: from, model: model, calendar: calendar)
                    + rampValue(at: segEnd, model: model, calendar: calendar)) / 2.0
                total += avg * weeks
            }
        }

        // Constant taper segment from taperStart (or `from`, whichever is later) to `to`.
        if to > model.taperStart {
            let segStart = max(from, model.taperStart)
            let days = calendar.fractionalDays(from: segStart, to: to)
            if days > 0 {
                let weeks = days / 7.0
                total += model.peakWeekly * model.taperFactor * weeks
            }
        }

        return total
    }

    /// Trailing 4-week weekly average of `values` strictly BEFORE `reference`
    /// (window [reference - 4 weeks, reference)); total / 4. Returns 0 when nothing in window.
    static func trailingWeeklyAverage(values: [(date: Date, value: Double)],
                                      reference: Date,
                                      calendar: Calendar = .current) -> Double {
        guard let windowStart = calendar.date(byAdding: .weekOfYear, value: -4, to: reference) else {
            return 0
        }
        let total = values
            .filter { $0.date >= windowStart && $0.date < reference }
            .map { $0.value }
            .reduce(0, +)
        return total / 4.0
    }

    // MARK: - Internal

    /// The pre-taper ramp value (linear interpolation, or flat when it degenerates), WITHOUT
    /// the taperStart cutover to `peakWeekly * taperFactor`. Shared by `weeklyTarget` (for dates
    /// before taperStart) and `cumulativeTarget`'s trapezoid endpoints, so the linear segment's
    /// integral is exact even when one endpoint sits exactly on taperStart.
    private static func rampValue(at date: Date, model: Model, calendar: Calendar) -> Double {
        guard model.taperStart > model.planStart else { return model.peakWeekly }
        guard model.startWeekly < model.peakWeekly else { return model.peakWeekly }

        let totalDays = calendar.fractionalDays(from: model.planStart, to: model.taperStart)
        guard totalDays > 0 else { return model.peakWeekly }

        let elapsedDays = calendar.fractionalDays(from: model.planStart, to: date)
        let fraction = min(1.0, max(0.0, elapsedDays / totalDays))
        return model.startWeekly + (model.peakWeekly - model.startWeekly) * fraction
    }
}
