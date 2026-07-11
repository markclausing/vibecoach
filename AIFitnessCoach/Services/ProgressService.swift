import Foundation

// MARK: - Epic 23: TRIMPTranslator — from abstract number to concrete activity

/// Translates a TRIMP amount into an understandable time or distance indication.
///
/// Background: the Banister TRIMP formula yields values that depend on heart-rate zone.
/// Rule of thumb based on an average athlete (resting HR 60, max 190):
///   Zone 2 (65–75% HRmax, ~145 bpm) ≈ 2.0 TRIMP/min
///   Zone 3 (75–85% HRmax, ~160 bpm) ≈ 3.0 TRIMP/min
///   Zone 4 (85–95% HRmax, ~170 bpm) ≈ 4.0 TRIMP/min
enum TRIMPTranslator {

    /// TRIMP per minute per zone (average Banister approximation).
    static let zone2PerMin: Double = 2.0
    static let zone4PerMin: Double = 4.0

    // MARK: - Public API

    /// Returns a short, readable translation of a TRIMP value into a practical duration.
    /// - Parameters:
    ///   - trimp: The TRIMP amount to translate (e.g. a weekly deficit).
    ///   - blueprintType: Determines the sport-specific labels (cycling vs. running).
    /// - Returns: e.g. "+5 min rustige rit of +3 min tempo-rit"
    static func translate(_ trimp: Double, for blueprintType: GoalBlueprintType) -> String {
        let zone2Min = Int((trimp / zone2PerMin).rounded(.up))
        let zone4Min = Int((trimp / zone4PerMin).rounded(.up))

        let (lightLabel, hardLabel): (String, String)
        switch blueprintType {
        case .cyclingTour:
            lightLabel = "rustige rit"
            hardLabel  = "tempo-rit"
        case .marathon, .halfMarathon:
            lightLabel = "duurloop (Z2)"
            hardLabel  = "intervaltraining (Z4)"
        }

        // Show only the zone2 version when both are equal (for small TRIMP values)
        if zone2Min == zone4Min {
            return "+\(zone2Min) min \(lightLabel)"
        }
        return "+\(zone2Min) min \(lightLabel) of +\(zone4Min) min \(hardLabel)"
    }

    /// Full sentence for use in the UI banner:
    /// "Circa 8 TRIMP/week nodig (bijv. +4 min rustige rit of +2 min tempo-rit)."
    static func bannerText(_ trimp: Double, for blueprintType: GoalBlueprintType) -> String {
        let trimpStr = Int(trimp.rounded())
        let hint = translate(trimp, for: blueprintType)
        return "Circa \(trimpStr) extra TRIMP/week (bijv. \(hint))."
    }

    /// Compact hint for the coach prompt:
    /// "8 TRIMP ≈ +4 min rustige rit of +2 min tempo-rit"
    static func coachHint(_ trimp: Double, for blueprintType: GoalBlueprintType) -> String {
        let trimpStr = Int(trimp.rounded())
        let hint = translate(trimp, for: blueprintType)
        return "\(trimpStr) TRIMP ≈ \(hint)"
    }
}

// MARK: - Epic 23: Blueprint Analysis & Future Projections — Sprint 1: Gap Analysis

/// Extension of GoalBlueprint with a sports-science weekly km target.
extension GoalBlueprint {
    /// Weekly km target in the build phase (not corrected for the periodization phase).
    var weeklyKmTarget: Double {
        switch goalType {
        case .marathon:     return 55.0   // Pfitzinger 18/55
        case .halfMarathon: return 40.0
        case .cyclingTour:  return 180.0  // Arnhem–Karlsruhe ~400 km / 4 days
        }
    }
}

/// The cumulative training deficit (or surplus) within the current training phase.
///
/// The calculation does NOT look at the weekly reset, but accumulates the total deficit
/// from the start of the current phase (e.g. Build Phase week 1) up to today.
/// If you did 20 km too little last week, week 2 already starts 20 km in the red.
struct BlueprintGap {
    let goal: FitnessGoal
    let blueprintType: GoalBlueprintType
    let blueprint: GoalBlueprint

    // MARK: - Phase context

    /// The current training phase (Base / Build / Peak / Taper).
    let currentPhase: TrainingPhase

    /// Date on which the current phase started (max of phase start and goal.createdAt).
    let phaseStartDate: Date

    /// Date on which the current phase ends (transition to the next phase).
    let phaseEndDate: Date

    /// Current week number within the phase (1-based).
    let phaseWeekNumber: Int

    /// Total number of weeks in the current phase.
    let phaseTotalWeeks: Int

    // MARK: - TRIMP (cumulative within the phase)

    /// Expected cumulative TRIMP from phase start until today (linearly interpolated).
    let requiredTRIMPToDate: Double

    /// Actually achieved cumulative TRIMP from phase start until today.
    let actualTRIMPToDate: Double

    /// Total TRIMP target for the entire phase (= reference for the full bar).
    let totalPhaseTRIMPTarget: Double

    // MARK: - Km (cumulative within the phase)

    /// Expected cumulative km from phase start until today (linearly interpolated).
    let requiredKmToDate: Double

    /// Actual cumulative km from phase start until today.
    let actualKmToDate: Double

    /// Total km target for the entire phase.
    let totalPhaseKmTarget: Double

    // MARK: - Derived values

    /// TRIMP difference: positive = behind, negative = ahead.
    var trimpGap: Double { requiredTRIMPToDate - actualTRIMPToDate }

    /// Km difference: positive = behind, negative = ahead.
    var kmGap: Double { requiredKmToDate - actualKmToDate }

    /// Weeks remaining until the target date (DST-safe).
    var weeksRemaining: Double { goal.weeksRemaining }

    // MARK: - Progress percentages (relative to the FULL phase, not the daily goal)
    // This way the bar sits at 0% at the start of the phase and at 100% at the end,
    // regardless of how much time has already elapsed.

    /// How much of the total phase TRIMP you've already achieved (0.0 – 1.0).
    var trimpProgressPct: Double {
        guard totalPhaseTRIMPTarget > 0 else { return 0 }
        return min(1.0, actualTRIMPToDate / totalPhaseTRIMPTarget)
    }

    /// Where you should be on the bar today — the "ghost" position (0.0 – 1.0).
    var trimpReferencePct: Double {
        guard totalPhaseTRIMPTarget > 0 else { return 0 }
        return min(1.0, requiredTRIMPToDate / totalPhaseTRIMPTarget)
    }

    /// How much of the total phase km you've already achieved (0.0 – 1.0).
    var kmProgressPct: Double {
        guard totalPhaseKmTarget > 0 else { return 0 }
        return min(1.0, actualKmToDate / totalPhaseKmTarget)
    }

    /// Where you should be on the km bar today — the "ghost" position (0.0 – 1.0).
    var kmReferencePct: Double {
        guard totalPhaseKmTarget > 0 else { return 0 }
        return min(1.0, requiredKmToDate / totalPhaseKmTarget)
    }

    // MARK: - Thresholds

    var isBehindOnTRIMP: Bool { trimpGap > requiredTRIMPToDate * 0.10 }
    var isBehindOnKm: Bool { kmGap > requiredKmToDate * 0.10 }

    // MARK: - TRIMPTranslator: catch-up hints

    /// Extra TRIMP/week needed to make up the phase deficit (0 if not behind).
    var extraTRIMPPerWeek: Double {
        guard isBehindOnTRIMP, weeksRemaining > 0 else { return 0 }
        return trimpGap / weeksRemaining
    }

    /// Readable catch-up text for the UI banner, including a practical time indication.
    /// Example: "Circa 8 extra TRIMP/week (bijv. +4 min rustige rit of +2 min tempo-rit)."
    var catchUpHint: String? {
        guard isBehindOnTRIMP, extraTRIMPPerWeek > 0.5 else { return nil }
        return TRIMPTranslator.bannerText(extraTRIMPPerWeek, for: blueprintType)
    }

    // MARK: - UI texts

    /// Label above the progress bar: "Voortgang Build Phase (Week 3/8)"
    var phaseProgressLabel: String {
        "\(currentPhase.displayName) (Week \(phaseWeekNumber)/\(phaseTotalWeeks))"
    }

    /// Status text TRIMP — cumulative in the phase.
    var trimpStatusLine: String {
        let gapStr = String(format: "%.0f", abs(trimpGap))
        if trimpGap > 5 {
            return "Je ligt in deze fase \(gapStr) TRIMP achter op het ideale pad."
        } else if trimpGap < -5 {
            return "Je ligt \(gapStr) TRIMP voor in deze fase — goed bezig!"
        } else {
            return "Je zit precies op het ideale pad."
        }
    }

    /// Status text km — cumulative in the phase.
    var kmStatusLine: String? {
        guard totalPhaseKmTarget > 0 else { return nil }
        let gapKm = String(format: "%.0f", abs(kmGap))
        if kmGap > 1 {
            return "Je ligt in deze fase \(gapKm) km achter op het ideale pad."
        } else if kmGap < -1 {
            return "Je hebt \(gapKm) km méér gedaan dan gepland in deze fase."
        } else {
            return "Qua afstand zit je precies op het ideale pad."
        }
    }

    // MARK: - Coach context (AI-prompt injection)

    var coachContext: String {
        let weeksLeftStr = String(format: "%.1f", weeksRemaining)
        let pctStr       = String(format: "%.0f%%", trimpProgressPct * 100)
        var lines = [
            "Doel: '\(goal.title)' — \(weeksLeftStr) weken resterend",
            "Blueprint: \(blueprintType.displayName) | Fase: \(phaseProgressLabel)",
            "Fase TRIMP-voortgang: \(String(format: "%.0f", actualTRIMPToDate)) / \(String(format: "%.0f", totalPhaseTRIMPTarget)) (\(pctStr)) — verwacht: \(String(format: "%.0f", requiredTRIMPToDate))",
            trimpStatusLine
        ]
        if let kmLine = kmStatusLine {
            lines.append(kmLine)
        }
        if isBehindOnTRIMP, extraTRIMPPerWeek > 0.5 {
            // Translate the abstract TRIMP number into a concrete time indication for the coach.
            // The coach MUST use the translation — never a bare TRIMP number without explanation.
            let hint = TRIMPTranslator.coachHint(extraTRIMPPerWeek, for: blueprintType)
            lines.append("📈 VOLUME ADJUSTMENT: To make up the phase shortfall, \(hint) extra per week is needed. Always translate this into a concrete change to an existing session: e.g. 'extend your Saturday ride by X minutes' or 'add an extra endurance run on Tuesday'.")
        }
        if isBehindOnKm, totalPhaseKmTarget > 0 {
            let extraKmPerWeek = weeksRemaining > 0 ? (kmGap / weeksRemaining) : 0
            lines.append("🚴 KM-BIJSTURING: \(String(format: "%.0f", extraKmPerWeek)) extra km/week nodig. Koppel dit aan een specifieke dag in het huidige schema.")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - ProgressService

struct ProgressService {

    static func analyzeGaps(for goals: [FitnessGoal], activities: [ActivityRecord]) -> [BlueprintGap] {
        let now = Date()
        return goals
            .filter { !$0.isCompleted && now < $0.targetDate }
            .compactMap { analyzeGap(for: $0, activities: activities) }
            .sorted { $0.trimpGap > $1.trimpGap }
    }

    // MARK: - Internal calculation

    private static func analyzeGap(for goal: FitnessGoal, activities: [ActivityRecord]) -> BlueprintGap? {
        guard let blueprintType = BlueprintChecker.detectBlueprintType(for: goal) else { return nil }
        let blueprint = BlueprintChecker.blueprint(for: blueprintType)

        let now = Date()
        let weeksRemaining = goal.weeksRemaining(from: now)
        let phase = TrainingPhase.calculate(weeksRemaining: weeksRemaining)

        // Sport type for the distance calculation
        let targetSport: SportCategory
        switch blueprintType {
        case .marathon, .halfMarathon: targetSport = .running
        case .cyclingTour:             targetSport = .cycling
        }

        // Epic #72 fix: take the current phase's window from `PhaseWindowCalculator` — the same
        // single source of truth the segmented bar and the per-phase milestone list use — so the
        // hero's "week N van M" can never disagree with the "BASE 2w" bar label or the milestone
        // date ranges (previously this used the fixed -12/-4/-2 offsets of `phaseDateRange` and a
        // ceil() week count, which showed "week 1 van 3" next to a 2-week bar segment).
        // `phaseDateRange` stays as fallback for the boundary case where `TrainingPhase.calculate`
        // names a phase the compressed week budget didn't give a window (e.g. exactly 12 weeks out).
        let calendar = Calendar.current
        let window = PhaseWindowCalculator.windows(for: goal, calendar: calendar)
            .first { $0.phase == phase }
        let (phaseStartDate, phaseEndDate) = window.map { ($0.start, $0.end) }
            ?? phaseDateRange(phase: phase, targetDate: goal.targetDate,
                              goalCreatedAt: goal.createdAt, calendar: calendar)

        let phaseDurationDays = max(1.0, calendar.fractionalDays(from: phaseStartDate, to: phaseEndDate))
        let elapsedDaysInPhase = max(0.0, min(phaseDurationDays, calendar.fractionalDays(from: phaseStartDate, to: now)))

        let phaseTotalWeeks   = phaseDurationDays / 7.0
        let elapsedWeeksInPhase = elapsedDaysInPhase / 7.0

        // Week number within the phase (1-based, clamped to the displayed total)
        let phaseTotalWeeksInt = window?.weekCount ?? max(1, Int(ceil(phaseTotalWeeks)))
        let phaseWeekNumber   = max(1, min(phaseTotalWeeksInt, Int(ceil(elapsedWeeksInPhase))))

        // Phase-corrected weekly TRIMP target (blueprint × phase multiplier)
        let adjustedWeeklyTRIMP = blueprint.weeklyTrimpTarget * phase.multiplier

        // Total TRIMP target for the whole phase
        let totalPhaseTRIMP = adjustedWeeklyTRIMP * phaseTotalWeeks

        // Expected cumulative TRIMP today = linearly interpolated
        let requiredTRIMP = adjustedWeeklyTRIMP * elapsedWeeksInPhase

        // Actually earned TRIMP in this phase
        let phaseActivities = activities.filter {
            $0.startDate >= phaseStartDate && $0.startDate <= now
        }
        let actualTRIMP = phaseActivities.compactMap { $0.trimp }.reduce(0, +)

        // Km calculation (phase-weighted: km target × phase multiplier for cycling/running)
        let adjustedWeeklyKm = blueprint.weeklyKmTarget * phase.multiplier
        let totalPhaseKm     = adjustedWeeklyKm * phaseTotalWeeks
        let requiredKm       = adjustedWeeklyKm * elapsedWeeksInPhase
        let actualKm         = phaseActivities
            .filter { $0.sportCategory == targetSport }
            .map { $0.distance / 1000.0 }
            .reduce(0, +)

        return BlueprintGap(
            goal: goal,
            blueprintType: blueprintType,
            blueprint: blueprint,
            currentPhase: phase,
            phaseStartDate: phaseStartDate,
            phaseEndDate: phaseEndDate,
            phaseWeekNumber: phaseWeekNumber,
            phaseTotalWeeks: phaseTotalWeeksInt,
            requiredTRIMPToDate: requiredTRIMP,
            actualTRIMPToDate: actualTRIMP,
            totalPhaseTRIMPTarget: totalPhaseTRIMP,
            requiredKmToDate: requiredKm,
            actualKmToDate: actualKm,
            totalPhaseKmTarget: totalPhaseKm
        )
    }

    /// Computes the start and end date of a training phase based on the target date.
    /// The phase transitions are synchronized with TrainingPhase.calculate:
    ///   baseBuilding  → ends 12 weeks before the race
    ///   buildPhase    → ends 4 weeks before the race
    ///   peakPhase     → ends 2 weeks before the race
    ///   tapering      → ends on race day
    private static func phaseDateRange(
        phase: TrainingPhase,
        targetDate: Date,
        goalCreatedAt: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let end: Date
        let nominalStart: Date

        switch phase {
        case .baseBuilding:
            end          = calendar.date(byAdding: .weekOfYear, value: -12, to: targetDate) ?? targetDate
            nominalStart = goalCreatedAt  // Base starts when the goal is created
        case .buildPhase:
            end          = calendar.date(byAdding: .weekOfYear, value: -4, to: targetDate) ?? targetDate
            nominalStart = calendar.date(byAdding: .weekOfYear, value: -12, to: targetDate) ?? targetDate
        case .peakPhase:
            end          = calendar.date(byAdding: .weekOfYear, value: -2, to: targetDate) ?? targetDate
            nominalStart = calendar.date(byAdding: .weekOfYear, value: -4, to: targetDate) ?? targetDate
        case .tapering:
            end          = targetDate
            nominalStart = calendar.date(byAdding: .weekOfYear, value: -2, to: targetDate) ?? targetDate
        }

        // If the goal was created after the nominal phase start, use createdAt as the start.
        // This prevents activities from before the goal being counted.
        let start = max(nominalStart, goalCreatedAt)
        return (start, end)
    }
}

// MARK: - Epic #60: Per-phase milestone timeline

extension ProgressService {

    /// Builds the per-phase timeline (all four phases at once) for one goal: date windows,
    /// targets and milestones. Works with or without a blueprint — blueprint-less goals get a
    /// generic weekly-TRIMP target and no km milestones. Pure Swift (§6); `now` is injectable
    /// for tests.
    static func phaseTimeline(for goal: FitnessGoal,
                              activities: [ActivityRecord],
                              now: Date = Date(),
                              calendar: Calendar = .current) -> PhaseTimeline {
        let windows = PhaseWindowCalculator.windows(for: goal, calendar: calendar)

        let blueprintType = BlueprintChecker.detectBlueprintType(for: goal)
        let blueprint = blueprintType.map { BlueprintChecker.blueprint(for: $0) }
        let targetSport: SportCategory? = blueprintType.map {
            switch $0 {
            case .marathon, .halfMarathon: return .running
            case .cyclingTour:             return .cycling
            }
        }

        // Deadline-based milestones, bucketed below into the phase whose window contains them.
        let milestoneStatuses = BlueprintChecker.check(goal: goal, activities: activities)?.milestones ?? []

        let summaries: [PhaseSummary] = windows.map { window in
            let status: PhaseStatus = now < window.start ? .future
                                    : (now > window.end ? .past : .current)
            let windowEnd = min(now, window.end)   // only count what has happened so far
            let criteria = window.phase.successCriteria

            var targets: [PhaseTarget] = []

            if let blueprint, let targetSport {
                // 1) Longest session target (taper: a maximum, not a minimum).
                let requiredMeters = blueprint.minLongRunDistance * criteria.longestSessionPct
                let longestKm: Double? = status == .future ? nil : {
                    let longest = activities
                        .filter { $0.sportCategory == targetSport
                            && $0.startDate >= window.start && $0.startDate <= windowEnd }
                        .map { $0.distance }
                        .max() ?? 0
                    return longest / 1000.0
                }()
                targets.append(PhaseTarget(
                    id: "\(window.phase.rawValue)_session",
                    label: "Langste sessie",
                    current: longestKm,
                    required: requiredMeters / 1000.0,
                    unit: "km",
                    isInverted: window.phase == .tapering
                ))

                // 2) Weekly TRIMP target.
                let weeklyTrimpReq = blueprint.weeklyTrimpTarget * criteria.weeklyTrimpPct
                targets.append(PhaseTarget(
                    id: "\(window.phase.rawValue)_trimp",
                    label: "Wekelijkse belasting",
                    current: averageWeeklyTRIMP(activities, from: window.start, to: windowEnd, status: status, calendar: calendar),
                    required: weeklyTrimpReq,
                    unit: "TRIMP",
                    isInverted: window.phase == .tapering
                ))
            } else {
                // Fallback for goals without a blueprint: only a generic weekly-TRIMP target,
                // phase-corrected with the same multiplier the planner uses.
                let baseWeekly = goal.computedTargetTRIMP / max(1.0, goal.totalDays / 7.0)
                targets.append(PhaseTarget(
                    id: "\(window.phase.rawValue)_trimp",
                    label: "Wekelijkse belasting",
                    current: averageWeeklyTRIMP(activities, from: window.start, to: windowEnd, status: status, calendar: calendar),
                    required: baseWeekly * window.phase.multiplier,
                    unit: "TRIMP",
                    isInverted: window.phase == .tapering
                ))
            }

            let milestones = milestoneStatuses
                .filter { assignedPhase(for: $0.deadline, windows: windows) == window.phase }
                .map { PhaseMilestone(id: $0.id, description: $0.description, targetDate: $0.deadline,
                                      isSatisfied: $0.isSatisfied, satisfiedByDate: $0.satisfiedByDate) }

            return PhaseSummary(
                phase: window.phase,
                start: window.start,
                end: window.end,
                weekCount: window.weekCount,
                status: status,
                targets: targets,
                milestones: milestones
            )
        }

        return PhaseTimeline(goalID: goal.id, phases: summaries)
    }

    /// Average weekly TRIMP achieved within a phase window so far (nil for future phases).
    private static func averageWeeklyTRIMP(_ activities: [ActivityRecord],
                                           from start: Date,
                                           to end: Date,
                                           status: PhaseStatus,
                                           calendar: Calendar) -> Double? {
        guard status != .future else { return nil }
        let weeks = max(1.0, calendar.fractionalWeeks(from: start, to: end))
        let total = activities
            .filter { $0.startDate >= start && $0.startDate <= end }
            .compactMap { $0.trimp }
            .reduce(0, +)
        return total / weeks
    }

    /// Assigns a deadline to the first phase window whose end is on/after it; falls back to the
    /// last window. Keeps every milestone visible under exactly one phase.
    private static func assignedPhase(for deadline: Date, windows: [PhaseWindow]) -> TrainingPhase? {
        if let match = windows.first(where: { deadline <= $0.end }) { return match.phase }
        return windows.last?.phase
    }
}
