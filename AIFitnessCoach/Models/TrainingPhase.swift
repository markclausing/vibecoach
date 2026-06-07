import Foundation

// MARK: - Epic 16: Dynamic Periodisation

/// The four classic training periods of a macrocycle.
/// Determines which AI instructions the coach uses when planning workouts.
enum TrainingPhase: String, CaseIterable {
    case baseBuilding = "Base Building"
    case buildPhase   = "Build Phase"
    case peakPhase    = "Peak Phase"
    case tapering     = "Tapering"

    /// Short description shown as a badge in the UI.
    var displayName: String { rawValue }

    /// Colour for the UI badge
    var color: String {
        switch self {
        case .baseBuilding: return "blue"
        case .buildPhase:   return "orange"
        case .peakPhase:    return "red"
        case .tapering:     return "purple"
        }
    }

    /// Sprint 16.2: phase multiplier for the weekly TRIMP target.
    /// The linear baseline (remaining TRIMP / remaining weeks) is corrected with this
    /// so the training intensity matches the physiological phase.
    var multiplier: Double {
        switch self {
        case .baseBuilding: return 1.00  // Plain linear baseline
        case .buildPhase:   return 1.15  // Build up 15% more load
        case .peakPhase:    return 1.30  // 30% more — maximum adaptation phase
        case .tapering:     return 0.60  // 40% less — rest is the training
        }
    }

    /// Hard AI instruction the coach receives for this phase.
    /// Short focus description for the status badge on the dashboard.
    /// Epic #37 story 37.1c: shown in the phase badge (phaseBadgeText) in the UI, not used in
    /// prompts, so resolved via the String Catalog. The big prompt instructions below stay Dutch.
    var focusDescription: String {
        switch self {
        case .baseBuilding: return String(localized: "Aerobe basis leggen")
        case .buildPhase:   return String(localized: "Uithoudingsvermogen opbouwen")
        case .peakPhase:    return String(localized: "Race-intensiteit bereiken")
        case .tapering:     return String(localized: "Herstellen en scherp worden")
        }
    }

    var aiInstruction: String {
        switch self {
        case .baseBuilding:
            return "Current phase: Base Building (>12 weeks to event). Instruction: Focus exclusively on low-intensity volume (Zone 1-2). No interval training. Build weekly TRIMP gradually by max. 10% per week. Lay the aerobic foundation."
        case .buildPhase:
            return "Current phase: Build Phase (4-12 weeks to event). Instruction: Increase both volume and intensity. Introduce controlled interval training (Zone 3-4). Weekly TRIMP increase max. 12%. Alternate between load weeks and recovery days."
        case .peakPhase:
            return "Current phase: Peak Phase (2-4 weeks to event). Instruction: Maximum training load. Race-specific sessions: tempos at race intensity. High TRIMP, but still schedule controlled recovery days. This is the last chance for adaptation."
        case .tapering:
            return "Current phase: Tapering (<2 weeks to event). CRITICAL INSTRUCTION: Reduce the weekly TRIMP volume by at least 40%. No more long, heavy sessions. Only short, light sessions (max. 45 min) to keep the legs sharp. The athlete is ready — rest is now the training."
        }
    }

    /// Computes the phase based on the number of weeks until the target date.
    static func calculate(weeksRemaining: Double) -> TrainingPhase {
        switch weeksRemaining {
        case ..<2:    return .tapering
        case 2..<4:   return .peakPhase
        case 4..<12:  return .buildPhase
        default:      return .baseBuilding
        }
    }

    // MARK: Epic 17.1 — Success Criteria per phase

    /// Returns the sports-science success criteria for this phase,
    /// expressed as fractions of the blueprint target values.
    var successCriteria: PhaseSuccessCriteria {
        switch self {
        case .baseBuilding:
            // Laying the foundation: 40% of the peak long run suffices, 60% of the TRIMP target.
            return PhaseSuccessCriteria(
                longestSessionPct: 0.40,
                weeklyTrimpPct: 0.60,
                sessionWindowWeeks: 4,
                coaching: "We're in the **Base Building** phase. Focus on low-intensity volume and laying the aerobic foundation. No interval training — not yet."
            )
        case .buildPhase:
            // Build-up: 60% of the peak long run, 80% of the TRIMP target.
            return PhaseSuccessCriteria(
                longestSessionPct: 0.60,
                weeklyTrimpPct: 0.80,
                sessionWindowWeeks: 3,
                coaching: "We're in the **Build** phase — it's time to ramp up the intensity. Add controlled interval sessions and build the longest session gradually."
            )
        case .peakPhase:
            // Peak: 80% of the peak long run is required, hit the full TRIMP target.
            return PhaseSuccessCriteria(
                longestSessionPct: 0.80,
                weeklyTrimpPct: 1.00,
                sessionWindowWeeks: 3,
                coaching: "We're in the **Peak** phase — maximum training load. Race-specific sessions at race intensity. Then the taper follows."
            )
        case .tapering:
            // Taper: longest session AT MOST 50% of the peak long run (not too heavy!), TRIMP back to 60%.
            // A 2-week window: gives a reliable picture of whether the athlete is really tapering
            // (race week may still be empty — looking back just 1 week is too short then).
            return PhaseSuccessCriteria(
                longestSessionPct: 0.50,
                weeklyTrimpPct: 0.60,
                sessionWindowWeeks: 2,
                coaching: "We're in the **Taper** phase. Less is more — keep sessions short and light. The legs get sharp through rest, not extra kilometres."
            )
        }
    }
}

// MARK: - Epic 17.1: PeriodizationEngine — Data Types

// MARK: Epic Goal Intents: IntentModifier

/// Training modifier based on the user's goal intent, event format and VibeScore.
/// Generated by PeriodizationEngine and passed to the AI coach via coachingContext.
struct IntentModifier {
    /// Multiplication factor on the weekly TRIMP target (1.0 = unchanged, 0.90 = ease-off mode).
    let weeklyTrimpMultiplier: Double
    /// Whether high intensity (lactate/tempo intervals) is allowed this week.
    let allowHighIntensity: Bool
    /// Whether back-to-back heavy sessions are emphasised (true for .multiDayStage).
    let backToBackEmphasis: Bool
    /// Whether stretch-pace workouts may be planned (only for .peakPerformance + VibeScore > 65).
    let stretchPaceAllowed: Bool
    /// AI instruction for the coach — generated based on intent + format + VibeScore.
    let coachingInstruction: String
}

/// Sports-science success criteria for one training phase.
/// Expressed as a fraction (0.0–1.0) of the blueprint target values so the
/// same criteria apply to marathon, half marathon and cycling tours.
struct PhaseSuccessCriteria {
    /// Minimum longest session as a fraction of `GoalBlueprint.minLongRunDistance`.
    /// Example: 0.80 in the Peak phase = longest session must be ≥80% of 32 km = ≥25.6 km.
    let longestSessionPct: Double
    /// Minimum weekly TRIMP as a fraction of `GoalBlueprint.weeklyTrimpTarget`.
    /// In the Taper phase this is a MAXIMUM (the athlete should do less).
    let weeklyTrimpPct: Double
    /// Number of weeks to look back to determine the longest session (shorter in Peak/Taper).
    let sessionWindowWeeks: Int
    /// Coaching message passed to the coach for this phase.
    let coaching: String
}

/// Result of a full PeriodizationEngine evaluation for one goal.
struct PeriodizationResult {
    let goal: FitnessGoal
    let blueprint: GoalBlueprint
    let phase: TrainingPhase
    let criteria: PhaseSuccessCriteria

    /// Longest session (in metres) of the sport type matching the blueprint,
    /// within the `criteria.sessionWindowWeeks` look-back window.
    let longestRecentSessionMeters: Double

    /// Minimum required session length = `blueprint.minLongRunDistance × criteria.longestSessionPct`.
    var requiredSessionMeters: Double {
        blueprint.minLongRunDistance * criteria.longestSessionPct
    }

    /// True if the longest session meets the phase requirement.
    /// In the Tapering phase the logic is inverted: the session must be SHORTER.
    var meetsLongestSessionCriteria: Bool {
        if phase == .tapering {
            return longestRecentSessionMeters <= requiredSessionMeters
        }
        return longestRecentSessionMeters >= requiredSessionMeters
    }

    /// Weekly TRIMP target for this phase = `blueprint.weeklyTrimpTarget × criteria.weeklyTrimpPct`.
    var targetWeeklyTrimp: Double {
        blueprint.weeklyTrimpTarget * criteria.weeklyTrimpPct
    }

    /// True if the athlete is at the right TRIMP level for this phase.
    /// In the Tapering phase the inverted logic applies here too.
    var meetsWeeklyTrimpCriteria: Bool {
        if phase == .tapering {
            return currentWeeklyTrimp <= targetWeeklyTrimp
        }
        return currentWeeklyTrimp >= targetWeeklyTrimp
    }

    /// Current average weekly TRIMP over the past 4 weeks (regardless of phase).
    let currentWeeklyTrimp: Double

    /// Modifier based on intent, format and VibeScore — generated by PeriodizationEngine.
    let intentModifier: IntentModifier

    /// Adjusted weekly TRIMP target after applying the intent multiplier.
    var adjustedWeeklyTrimpTarget: Double { targetWeeklyTrimp * intentModifier.weeklyTrimpMultiplier }

    /// True if the athlete meets BOTH criteria.
    var isOnTrack: Bool { meetsLongestSessionCriteria && meetsWeeklyTrimpCriteria }

    /// Phase + focus for the status badge above the schedule.
    var phaseBadgeText: String { "\(phase.displayName) — \(phase.focusDescription)" }

    /// Progress items for the MilestoneProgressCard.
    /// Each item has a label, current value, required value and whether it is met.
    struct MilestoneItem {
        let label: String
        let detail: String          // e.g. "60 km longest ride in the past 3 weeks"
        let current: Double
        let required: Double
        let isMet: Bool
        let isInverted: Bool        // true for tapering: lower is better
        var progress: Double {
            guard required > 0 else { return 0 }
            let ratio = current / required
            return isInverted ? min(1.0, 2.0 - ratio) : min(1.0, ratio)
        }
    }

    var milestoneItems: [MilestoneItem] {
        let sessionUnit = blueprint.goalType == .cyclingTour ? "km rit" : "km loop"
        let sessionItem = MilestoneItem(
            label: "Langste sessie",
            detail: "\(String(format: "%.0f", requiredSessionMeters / 1000)) \(sessionUnit) \(phase == .tapering ? "(max)" : "(min)") — \(criteria.sessionWindowWeeks) weeks window",
            current: longestRecentSessionMeters / 1000,
            required: requiredSessionMeters / 1000,
            isMet: meetsLongestSessionCriteria,
            isInverted: phase == .tapering
        )
        let trimpItem = MilestoneItem(
            label: "Wekelijkse belasting",
            detail: "\(String(format: "%.0f", targetWeeklyTrimp)) TRIMP/week \(phase == .tapering ? "(max)" : "(min)")",
            current: currentWeeklyTrimp,
            required: targetWeeklyTrimp,
            isMet: meetsWeeklyTrimpCriteria,
            isInverted: phase == .tapering
        )
        return [sessionItem, trimpItem]
    }

    /// Full coaching context including phase, criteria, status and behaviour instructions — ready for AI injection.
    /// Sprint 17.2: now contains explicit compliment triggers, urgent milestone alerts and the schedule-accountability duty.
    var coachingContext: String {
        let weeksLeft    = goal.weeksRemaining
        let weeksLeftStr = String(format: "%.1f", weeksLeft)
        let longestKm    = String(format: "%.1f", longestRecentSessionMeters / 1000)
        let requiredKm   = String(format: "%.1f", requiredSessionMeters / 1000)
        let sessionCheck = meetsLongestSessionCriteria ? "✅" : "❌"
        let trimpCheck   = meetsWeeklyTrimpCriteria    ? "✅" : "❌"
        let trimpTarget  = String(format: "%.0f", targetWeeklyTrimp)
        let trimpActual  = String(format: "%.0f", currentWeeklyTrimp)
        let sessionLabel = phase == .tapering ? "≤\(requiredKm) km (tapering: bewust MINDER)" : "≥\(requiredKm) km"

        var lines = [
            "═══ PERIODISERING: '\(goal.title)' ═══",
            "Phase: \(phase.displayName) | \(weeksLeftStr) weeks remaining",
            criteria.coaching,
            "",
            "SUCCESCRITERIA DEZE FASE:",
            "\(sessionCheck) Longest session (past \(criteria.sessionWindowWeeks) weeks): \(longestKm) km (requirement: \(sessionLabel))",
            "\(trimpCheck) Weekly TRIMP: \(trimpActual) TRIMP/week (requirement: \(phase == .tapering ? "≤" : "≥")\(trimpTarget))"
        ]

        // Compliment triggers — the coach MUST use this as the opening
        if meetsLongestSessionCriteria {
            lines.append("")
            lines.append("🎉 COMPLIMENT TRIGGER: The longest-session requirement has been met! Start your answer with a sincere compliment about it. Name the specific distance.")
        } else {
            let shortfallKm = String(format: "%.1f", max(0, requiredSessionMeters - longestRecentSessionMeters) / 1000)
            lines.append("")
            lines.append("🚨 CRITICAL MILESTONE SHORTFALL: The longest session is \(shortfallKm) km short for the \(phase.displayName). This is the #1 priority for the schedule this week. Be direct but motivating — name the concrete target distance.")
        }

        if meetsWeeklyTrimpCriteria && phase != .tapering {
            lines.append("🎉 COMPLIMENT TRIGGER: The weekly TRIMP target has been met. Mention this as a positive sign of consistency.")
        }

        // Schedule-accountability duty on injury or adjustment
        lines.append("")
        lines.append("SCHEDULE ACCOUNTABILITY: If you adjust the schedule (e.g. due to injury or overload), you MUST explicitly explain how the \(phase.displayName) requirement (\(sessionLabel)) is still achievable. Use sport-specific alternatives if the primary sport temporarily isn't possible. E.g.: 'I'm replacing your running session with cycling, but we'll safeguard the aerobic base for \(goal.title) this way...'")

        // Goal-intent section — always inject so the coach knows how to prioritise
        lines.append("")
        lines.append(intentModifier.coachingInstruction)

        return lines.joined(separator: "\n")
    }
}
