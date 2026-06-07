import Foundation

// MARK: - Epic 17.1: PeriodizationEngine

/// Computes, per active goal, the sports-science progress based on the current
/// training phase and the corresponding success criteria from the GoalBlueprint.
///
/// Works together with BlueprintChecker (critical milestone checks) and TrainingPhase (phase detection)
/// to give a complete picture: "What do I need to do NOW to stay on schedule?"
struct PeriodizationEngine {

    // MARK: - Evaluation

    /// Evaluates one goal: detects the active blueprint, determines the phase and tests
    /// the recent activities against the phase-specific success criteria.
    ///
    /// - Parameters:
    ///   - goal: The fitness goal to evaluate.
    ///   - activities: All available activities of the user.
    ///   - latestReadinessScore: Most recent VibeScore (0–100). Nil = unknown → neutral behaviour.
    /// - Returns: A `PeriodizationResult` with phase, criteria, longest session and TRIMP check,
    ///   or `nil` if no blueprint applies or the goal is already completed/expired.
    static func evaluate(
        goal: FitnessGoal,
        activities: [ActivityRecord],
        latestReadinessScore: Int? = nil
    ) -> PeriodizationResult? {
        guard !goal.isCompleted, Date() < goal.targetDate else { return nil }
        guard let blueprintType = BlueprintChecker.detectBlueprintType(for: goal) else { return nil }

        let bp = BlueprintChecker.blueprint(for: blueprintType)
        let weeksRemaining = goal.weeksRemaining
        let phase = TrainingPhase.calculate(weeksRemaining: weeksRemaining)
        let criteria = phase.successCriteria

        // Determine the sport type matching the blueprint (running for marathon, cycling for tour)
        let targetSport: SportCategory
        switch blueprintType {
        case .marathon, .halfMarathon: targetSport = .running
        case .cyclingTour:             targetSport = .cycling
        }

        // Longest session within the phase-specific look-back window
        let windowStart = Calendar.current.date(
            byAdding: .weekOfYear,
            value: -criteria.sessionWindowWeeks,
            to: Date()
        ) ?? Date()

        let longestSession = activities
            .filter { $0.sportCategory == targetSport && $0.startDate >= windowStart }
            .map { $0.distance }
            .max() ?? 0.0

        // Average weekly TRIMP over the past 4 weeks (a wide window for stability)
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date()) ?? Date()
        let recentTRIMP = activities
            .filter { $0.startDate >= fourWeeksAgo }
            .compactMap { $0.trimp }
            .reduce(0, +)
        let avgWeeklyTrimp = recentTRIMP / 4.0

        // Epic Goal Intents: build the intent modifier based on format, intent and VibeScore
        let intentModifier = buildIntentModifier(goal: goal, phase: phase, readinessScore: latestReadinessScore)

        return PeriodizationResult(
            goal: goal,
            blueprint: bp,
            phase: phase,
            criteria: criteria,
            longestRecentSessionMeters: longestSession,
            currentWeeklyTrimp: avgWeeklyTrimp,
            intentModifier: intentModifier
        )
    }

    /// Evaluates all active goals and returns results sorted by urgency
    /// (goals not on schedule come first).
    static func evaluateAllGoals(
        _ goals: [FitnessGoal],
        activities: [ActivityRecord],
        latestReadinessScore: Int? = nil
    ) -> [PeriodizationResult] {
        let now = Date()
        return goals
            .filter { !$0.isCompleted && now < $0.targetDate }
            .compactMap { evaluate(goal: $0, activities: activities, latestReadinessScore: latestReadinessScore) }
            .sorted { !$0.isOnTrack && $1.isOnTrack }
    }

    // MARK: - Intent Modifier Builder

    /// Builds an IntentModifier based on the goal's intent, format and current VibeScore.
    static func buildIntentModifier(
        goal: FitnessGoal,
        phase: TrainingPhase,
        readinessScore: Int?
    ) -> IntentModifier {
        let vibeScore = readinessScore ?? 70          // unknown → neutral
        let isHighReadiness = vibeScore > 65
        let isMultiDay      = goal.resolvedFormat == .multiDayStage

        // Completion mode: aerobic base, UNLESS there is a stretchGoalTime and the VibeScore is high enough.
        // Then one tempo session per week is allowed — the athlete wants to finish but also has a time goal.
        if goal.resolvedIntent == .completion {
            let hasStretchWithReadiness = goal.stretchGoalTime != nil && isHighReadiness
            return IntentModifier(
                weeklyTrimpMultiplier: 0.90,
                allowHighIntensity: hasStretchWithReadiness,
                backToBackEmphasis: isMultiDay,
                stretchPaceAllowed: hasStretchWithReadiness,
                coachingInstruction: completionInstruction(goal: goal, vibeScore: vibeScore, isMultiDay: isMultiDay, stretchAllowed: hasStretchWithReadiness)
            )
        }

        // Peak Performance mode: intensity allowed if the VibeScore is high enough
        let stretchPaceAllowed = isHighReadiness && goal.stretchGoalTime != nil && phase != .tapering
        let allowHighIntensity = isHighReadiness && phase != .tapering

        return IntentModifier(
            weeklyTrimpMultiplier: isMultiDay ? 0.95 : 1.0,
            allowHighIntensity: allowHighIntensity,
            backToBackEmphasis: isMultiDay,
            stretchPaceAllowed: stretchPaceAllowed,
            coachingInstruction: peakPerformanceInstruction(
                goal: goal, vibeScore: vibeScore,
                stretchPaceAllowed: stretchPaceAllowed,
                allowHighIntensity: allowHighIntensity,
                isMultiDay: isMultiDay
            )
        )
    }

    // MARK: - Coaching Instruction Builders

    private static func completionInstruction(goal: FitnessGoal, vibeScore: Int, isMultiDay: Bool, stretchAllowed: Bool) -> String {
        var lines = ["══ GOAL INTENT: FINISH / SURVIVE ══"]

        if stretchAllowed, let stretchTime = goal.stretchGoalTime {
            let totalSec = Int(stretchTime)
            let hours    = totalSec / 3600
            let minutes  = (totalSec % 3600) / 60
            let timeStr  = hours > 0 ? "\(hours)h\(String(format: "%02d", minutes))" : "\(minutes) min"
            lines.append("Primary intent: FINISH — but a target time of \(timeStr) is set.")
            lines.append("Vibe Score (\(vibeScore)) is high enough: add at most 1 tempo session per week at goal pace. The base stays Zone 1-2; tempo is additional, not leading.")
        } else {
            lines.append("The user wants to finish this event safely — no race strategy.")
            lines.append("INSTRUCTION: Prioritise Zone 1-2 (aerobic base). NO lactate intervals or tempo blocks.")
            lines.append("Schedule principle: endurance > intensity. Long, easy sessions are central.")
        }

        if isMultiDay {
            lines.append("FORMAT — MULTI-DAY STAGE TOUR: Spread the load across consecutive days (e.g. Sat + Sun back-to-back endurance). Reduce high intensity further — adapting to cumulative fatigue is the primary goal.")
        }
        if vibeScore < 65 {
            lines.append("⚠️ LOW VIBE SCORE (\(vibeScore)): Recovery comes first this week. Lower volume by 20% and cut every intense session — completion is at risk if the athlete starts exhausted.")
        }
        return lines.joined(separator: "\n")
    }

    private static func peakPerformanceInstruction(
        goal: FitnessGoal,
        vibeScore: Int,
        stretchPaceAllowed: Bool,
        allowHighIntensity: Bool,
        isMultiDay: Bool
    ) -> String {
        var lines = ["══ GOAL INTENT: MAXIMUM PERFORMANCE ══"]

        if isMultiDay {
            lines.append("FORMAT — MULTI-DAY STAGE TOUR: Spread the heavy load across consecutive days (Sat + Sun back-to-back). Reduce the number of lactate intervals vs. a single-day race — endurance and recovery speed are decisive here.")
        }

        if !allowHighIntensity {
            lines.append("⚠️ VIBE SCORE (\(vibeScore)) TOO LOW for high intensity: Cut tempo intervals and prioritise recovery this week. Performance is saved by resting now, not by pushing through.")
        }

        if stretchPaceAllowed, let stretchTime = goal.stretchGoalTime {
            let totalSec = Int(stretchTime)
            let hours    = totalSec / 3600
            let minutes  = (totalSec % 3600) / 60
            let timeStr  = hours > 0 ? "\(hours)h\(String(format: "%02d", minutes))" : "\(minutes) min"
            lines.append("✅ TARGET TIME \(timeStr) — Vibe Score (\(vibeScore)) is high enough: add 1 tempo session per week at goal speed. Compute the goal pace and state it explicitly in the schedule ('tempo block at goal speed').")
        } else if let stretchTime = goal.stretchGoalTime {
            let totalSec = Int(stretchTime)
            let hours    = totalSec / 3600
            let minutes  = (totalSec % 3600) / 60
            let timeStr  = hours > 0 ? "\(hours)h\(String(format: "%02d", minutes))" : "\(minutes) min"
            lines.append("🔴 TARGET TIME \(timeStr) set but Vibe Score (\(vibeScore)) is too low or taper phase active: Fall back to PURE ENDURANCE. No tempo blocks at goal speed — recover first, then perform.")
        }

        return lines.joined(separator: "\n")
    }
}
