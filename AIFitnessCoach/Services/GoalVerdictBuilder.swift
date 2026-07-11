import Foundation

// Epic #72 story 72.1: deterministic "will I make it?" verdict for the Goals hero card.
// Pure Swift, AppStorage-free (CLAUDE.md §6): the caller (GoalsListView) maps BlueprintGap /
// PhaseTimeline / GoalRiskStatus values into `GoalVerdictInput`; this type never reads
// UserDefaults, @AppStorage, SwiftData or the clock.

enum GoalVerdictTone: Equatable {
    case onTrack
    case slightlyBehind
    case atRisk
}

/// Pace of one cumulative metric vs. where it should be today. Also used by the
/// per-metric status pills in the "Progress this phase" card (story 72.3), so the
/// pill and the verdict can never disagree.
enum MetricPaceStatus: Equatable {
    case ahead
    case onPace
    case behind
}

struct GoalVerdictInput: Equatable {
    var phaseWeekNumber: Int
    var phaseTotalWeeks: Int
    var trimpActual: Double
    var trimpExpectedToDate: Double
    var trimpPhaseTarget: Double        // <= 0 means: no TRIMP target known
    var kmActual: Double
    var kmExpectedToDate: Double
    var kmPhaseTarget: Double           // <= 0 means: no distance target for this goal
    var achievedTargetLabels: [String]  // Dutch prompt-term labels of already-met targets in the current phase
    var isAtRisk: Bool                  // a DashboardView.GoalRiskStatus exists for this goal
    var isTaperingOverload: Bool
    var riskCurrentWeeklyRate: Double?  // TRIMP/week, only meaningful when isAtRisk
    var riskRequiredWeeklyRate: Double?
}

struct GoalVerdict: Equatable {
    enum Fact: Equatable {
        case weekContext(week: Int, totalWeeks: Int)
        case milestoneAchieved(label: String)
        case loadAhead
        case loadOnPace
        case loadBehind(deltaTRIMP: Int)
        case distanceAhead
        case distanceOnPace
        case distanceSlightlyBehind(deltaKm: Int)
        case offTrack(currentWeekly: Int, requiredWeekly: Int)
        case taperingOverload
    }
    let tone: GoalVerdictTone
    let facts: [Fact]
}

enum GoalVerdictBuilder {
    /// Threshold mirroring `BlueprintGap.isBehindOnTRIMP` / `isBehindOnKm` in ProgressService.swift:
    /// a gap of more than 10% of what's expected to date counts as off-pace.
    private static let paceTolerance: Double = 0.10

    static func build(_ input: GoalVerdictInput) -> GoalVerdict? {
        guard input.trimpPhaseTarget > 0 || input.kmPhaseTarget > 0 || input.isAtRisk else {
            return nil
        }

        var facts: [GoalVerdict.Fact] = []

        if input.phaseTotalWeeks > 0 {
            let clampedWeek = min(max(input.phaseWeekNumber, 1), input.phaseTotalWeeks)
            facts.append(.weekContext(week: clampedWeek, totalWeeks: input.phaseTotalWeeks))
        }

        if let firstAchieved = input.achievedTargetLabels.first {
            facts.append(.milestoneAchieved(label: firstAchieved))
        }

        var anyMetricBehind = false

        if input.trimpPhaseTarget > 0 {
            let status = paceStatus(actual: input.trimpActual, expectedToDate: input.trimpExpectedToDate)
            switch status {
            case .ahead:
                facts.append(.loadAhead)
            case .onPace:
                facts.append(.loadOnPace)
            case .behind:
                anyMetricBehind = true
                let delta = Int((input.trimpExpectedToDate - input.trimpActual).rounded())
                facts.append(.loadBehind(deltaTRIMP: delta))
            }
        }

        if input.kmPhaseTarget > 0 {
            let status = paceStatus(actual: input.kmActual, expectedToDate: input.kmExpectedToDate)
            switch status {
            case .ahead:
                facts.append(.distanceAhead)
            case .onPace:
                facts.append(.distanceOnPace)
            case .behind:
                anyMetricBehind = true
                let delta = Int((input.kmExpectedToDate - input.kmActual).rounded())
                facts.append(.distanceSlightlyBehind(deltaKm: delta))
            }
        }

        if input.isAtRisk {
            if input.isTaperingOverload {
                facts.append(.taperingOverload)
            } else {
                let current = Int((input.riskCurrentWeeklyRate ?? 0).rounded())
                let required = Int((input.riskRequiredWeeklyRate ?? 0).rounded())
                facts.append(.offTrack(currentWeekly: current, requiredWeekly: required))
            }
        }

        let tone: GoalVerdictTone
        if input.isAtRisk {
            tone = .atRisk
        } else if anyMetricBehind {
            tone = .slightlyBehind
        } else {
            tone = .onTrack
        }

        return GoalVerdict(tone: tone, facts: facts)
    }

    static func paceStatus(actual: Double, expectedToDate: Double) -> MetricPaceStatus {
        guard expectedToDate > 0 else { return .onPace }

        let tolerance = expectedToDate * paceTolerance
        if (expectedToDate - actual) > tolerance {
            return .behind
        }
        if (actual - expectedToDate) > tolerance {
            return .ahead
        }
        return .onPace
    }
}
