import Foundation

// MARK: - Epic #60: Per-phase milestone timeline
//
// Computed value types (no @Model, no schema migration — §2.1) that describe, for one goal,
// every training phase with its date window, targets and milestones. The view layer renders
// these as a collapsible per-phase list. Pure Swift, AppStorage-free (§6) so it's unit-testable.

/// Status of a phase relative to "now".
enum PhaseStatus {
    case past      // the whole phase window lies in the past
    case current   // today falls within the phase window
    case future    // the phase hasn't started yet
}

/// The date window of one training phase. Single source of truth shared by the segmented
/// phase bar and the per-phase milestone list (see `PhaseWindowCalculator`), so the two can
/// never disagree.
struct PhaseWindow: Equatable {
    let phase: TrainingPhase
    let start: Date
    let end: Date
    let weekCount: Int
}

/// One concrete target for a phase (e.g. "longest run ≥ 25 km" or "weekly load ≥ 280 TRIMP").
/// `current` is nil for future phases — there's nothing achieved yet to show.
struct PhaseTarget: Identifiable {
    let id: String
    /// Dutch prompt-style label; localise at the view site via `LocalizedStringKey` (§13).
    let label: String
    let current: Double?
    let required: Double
    let unit: String
    /// Taper inversion: lower is better (mirrors `PeriodizationResult.MilestoneItem.isInverted`).
    let isInverted: Bool

    /// Progress 0.0–1.0. For inverted (taper) targets, being under the cap reads as full.
    var progress: Double {
        guard required > 0, let current else { return 0 }
        let ratio = current / required
        return isInverted ? min(1.0, max(0.0, 2.0 - ratio)) : min(1.0, ratio)
    }

    var isMet: Bool {
        guard let current else { return false }
        return isInverted ? current <= required : current >= required
    }
}

/// One milestone (essential workout) bucketed under the phase whose window contains its deadline.
struct PhaseMilestone: Identifiable {
    let id: String
    let description: String
    let targetDate: Date
    let isSatisfied: Bool
    let satisfiedByDate: Date?
}

/// Everything the UI needs to render one collapsible phase section.
struct PhaseSummary: Identifiable {
    var id: String { phase.rawValue }
    let phase: TrainingPhase
    let start: Date
    let end: Date
    let weekCount: Int
    let status: PhaseStatus
    let targets: [PhaseTarget]
    let milestones: [PhaseMilestone]
}

/// The full per-phase plan for one goal.
struct PhaseTimeline {
    let goalID: UUID
    let phases: [PhaseSummary]
}

// MARK: - PhaseWindowCalculator

/// Single source of truth for training-phase windows. Both the segmented phase bar
/// (`GoalsListView.phaseSegments`) and the per-phase milestone list use this so they never
/// diverge — previously the bar used a week budget while `ProgressService.phaseDateRange`
/// used fixed -12/-4/-2 week offsets, which disagreed for short goals.
///
/// The week budget (taper 2 / peak 2 / build ≤8 / base = rest) compresses short goals instead
/// of placing phases before the goal even started. Pure Swift, AppStorage-free (§6).
enum PhaseWindowCalculator {

    /// Computes the date window of every present phase, anchored to `targetDate` and walking
    /// backwards. A phase with zero budget weeks (base/build on a very short goal) is omitted.
    static func windows(targetDate: Date, createdAt: Date, calendar: Calendar = .current) -> [PhaseWindow] {
        let totalDays = calendar.fractionalDays(from: createdAt, to: targetDate)
        // Mirrors GoalsListView.phaseSegments so the bar and the list agree.
        let totalWeeks = max(6, Int(totalDays / 7.0))

        let taperW = 2
        let peakW  = 2
        let buildW = min(8, max(0, totalWeeks - taperW - peakW))
        let baseW  = max(0, totalWeeks - buildW - peakW - taperW)

        let taperEnd   = targetDate
        let taperStart = calendar.date(byAdding: .weekOfYear, value: -taperW, to: taperEnd) ?? taperEnd
        let peakStart  = calendar.date(byAdding: .weekOfYear, value: -peakW, to: taperStart) ?? taperStart
        let buildStart = calendar.date(byAdding: .weekOfYear, value: -buildW, to: peakStart) ?? peakStart
        let baseStart  = calendar.date(byAdding: .weekOfYear, value: -baseW, to: buildStart) ?? buildStart

        var windows: [PhaseWindow] = []
        if baseW > 0 {
            // Clamp the base start to the goal's creation date — never show weeks from before
            // the goal existed — but keep it ≤ buildStart so the range stays valid.
            let clampedStart = min(max(baseStart, createdAt), buildStart)
            windows.append(PhaseWindow(phase: .baseBuilding, start: clampedStart, end: buildStart, weekCount: baseW))
        }
        if buildW > 0 {
            windows.append(PhaseWindow(phase: .buildPhase, start: buildStart, end: peakStart, weekCount: buildW))
        }
        windows.append(PhaseWindow(phase: .peakPhase, start: peakStart, end: taperStart, weekCount: peakW))
        windows.append(PhaseWindow(phase: .tapering, start: taperStart, end: taperEnd, weekCount: taperW))

        // Epic #72 fix: the whole-week walk-back can land the first window's start up to a
        // week AFTER the goal was created (floor rounding of totalWeeks). In that dead gap
        // every phase read as `.future` on day one: no "Nu" pill, no met checkmarks, and a
        // same-day workout didn't count toward phase 1. Snap the first window's start back to
        // the beginning of the creation day so the plan starts the moment the goal exists
        // (start-of-day so a run logged earlier that same day counts too). Only ever widen —
        // a first window that already starts before the creation day is left alone.
        if let first = windows.first {
            let creationDay = calendar.startOfDay(for: createdAt)
            if first.start > creationDay {
                windows[0] = PhaseWindow(phase: first.phase, start: creationDay,
                                         end: first.end, weekCount: first.weekCount)
            }
        }
        return windows
    }

    static func windows(for goal: FitnessGoal, calendar: Calendar = .current) -> [PhaseWindow] {
        windows(targetDate: goal.targetDate, createdAt: goal.createdAt, calendar: calendar)
    }
}
