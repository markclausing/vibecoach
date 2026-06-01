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
        var lines = ["══ DOEL-INTENTIE: UITLOPEN / OVERLEVEN ══"]

        if stretchAllowed, let stretchTime = goal.stretchGoalTime {
            let totalSec = Int(stretchTime)
            let hours    = totalSec / 3600
            let minutes  = (totalSec % 3600) / 60
            let timeStr  = hours > 0 ? "\(hours)u\(String(format: "%02d", minutes))" : "\(minutes) min"
            lines.append("Primaire intentie: FINISHEN — maar er is een doeltijd van \(timeStr) ingesteld.")
            lines.append("VibeScore (\(vibeScore)) is hoog genoeg: Voeg maximaal 1 temposessie per week toe op doelpace. Basis blijft Zone 1-2; tempo is additioneel, niet leidend.")
        } else {
            lines.append("De gebruiker wil dit evenement uitlopen en veilig finishen — géén racestrategie.")
            lines.append("INSTRUCTIE: Prioriteer Zone 1-2 (aerobe basis). GEEN lactaat-intervallen of tempo-blokken.")
            lines.append("Schema-principe: duurvermogen > intensiteit. Lange, rustige trainingen staan centraal.")
        }

        if isMultiDay {
            lines.append("FORMAAT — MEERDAAGSE ETAPPERIT: Verspreid de belasting over opeenvolgende dagen (bijv. Za + Zo back-to-back duurtraining). Verminder hoge intensiteit verder — gewenning aan accumulatievermoeidheid is het primaire doel.")
        }
        if vibeScore < 65 {
            lines.append("⚠️ LAGE VIBE SCORE (\(vibeScore)): Herstel staat deze week voorop. Verlaag volume met 20% en schrap elke intensieve sessie — completion staat op het spel als de sporter uitgeput aan de start staat.")
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
        var lines = ["══ DOEL-INTENTIE: MAXIMALE PRESTATIE ══"]

        if isMultiDay {
            lines.append("FORMAAT — MEERDAAGSE ETAPPERIT: Verspreid de zware belasting over opeenvolgende dagen (Za + Zo back-to-back). Verlaag het aantal lactaat-intervallen t.o.v. een eendaagse race — duurvermogen en herstelsnelheid zijn hier doorslaggevend.")
        }

        if !allowHighIntensity {
            lines.append("⚠️ VIBE SCORE (\(vibeScore)) TE LAAG voor hoge intensiteit: Schrap tempo-intervallen en prioriteer herstel deze week. De prestatie wordt gered door nu rust te nemen, niet door door te bijten.")
        }

        if stretchPaceAllowed, let stretchTime = goal.stretchGoalTime {
            let totalSec = Int(stretchTime)
            let hours    = totalSec / 3600
            let minutes  = (totalSec % 3600) / 60
            let timeStr  = hours > 0 ? "\(hours)u\(String(format: "%02d", minutes))" : "\(minutes) min"
            lines.append("✅ DOELTIJD \(timeStr) — VibeScore (\(vibeScore)) is hoog genoeg: Voeg 1 temposessie per week toe op doelsnelheid. Bereken de doelpace en benoem dit expliciet in het schema ('tempo-blok op doelsnelheid').")
        } else if let stretchTime = goal.stretchGoalTime {
            let totalSec = Int(stretchTime)
            let hours    = totalSec / 3600
            let minutes  = (totalSec % 3600) / 60
            let timeStr  = hours > 0 ? "\(hours)u\(String(format: "%02d", minutes))" : "\(minutes) min"
            lines.append("🔴 DOELTIJD \(timeStr) ingesteld maar VibeScore (\(vibeScore)) is te laag of taperfase actief: Val terug op PURE DUURTRAINING. Geen tempo-blokken op doelsnelheid — eerst herstellen, dan presteren.")
        }

        return lines.joined(separator: "\n")
    }
}
