import Foundation

// MARK: - Epic 17.1: PeriodizationEngine

/// Berekent per actief doel de sportwetenschappelijke voortgang op basis van de huidige
/// trainingsfase en de bijbehorende succescriteria uit de GoalBlueprint.
///
/// Werkt samen met BlueprintChecker (kritieke milestone-checks) en TrainingPhase (fase-detectie)
/// om een volledig beeld te geven: "Wat moet ik NU doen om op schema te blijven?"
struct PeriodizationEngine {

    // MARK: - Evaluatie

    /// Evalueert één doel: detecteert de actieve blueprint, bepaalt de fase en toetst
    /// de recente activiteiten aan de fase-specifieke succescriteria.
    ///
    /// - Parameters:
    ///   - goal: Het te evalueren fitnessdoel.
    ///   - activities: Alle beschikbare activiteiten van de gebruiker.
    ///   - latestReadinessScore: Meest recente VibeScore (0–100). Nil = onbekend → neutraal gedrag.
    /// - Returns: `PeriodizationResult` met fase, criteria, langste sessie en TRIMP-check,
    ///   of `nil` als er geen blueprint van toepassing is of het doel al afgerond/verlopen is.
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

        // Bepaal het sport-type dat bij de blueprint past (hardlopen voor marathon, fietsen voor tour)
        let targetSport: SportCategory
        switch blueprintType {
        case .marathon, .halfMarathon: targetSport = .running
        case .cyclingTour:             targetSport = .cycling
        }

        // Langste sessie binnen het fase-specifieke terugkijkvenster
        let windowStart = Calendar.current.date(
            byAdding: .weekOfYear,
            value: -criteria.sessionWindowWeeks,
            to: Date()
        ) ?? Date()

        let longestSession = activities
            .filter { $0.sportCategory == targetSport && $0.startDate >= windowStart }
            .map { $0.distance }
            .max() ?? 0.0

        // Gemiddeld wekelijks TRIMP over de afgelopen 4 weken (breed venster voor stabiliteit)
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date()) ?? Date()
        let recentTRIMP = activities
            .filter { $0.startDate >= fourWeeksAgo }
            .compactMap { $0.trimp }
            .reduce(0, +)
        let avgWeeklyTrimp = recentTRIMP / 4.0

        // Epic Doel-Intenties: bouw de intentie-modifier op basis van format, intent en VibeScore
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

    /// Evalueert alle actieve doelen en retourneert resultaten gesorteerd op urgentie
    /// (doelen die niet op schema zijn komen eerst).
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

    /// Bouwt een IntentModifier op basis van de intentie, het format en de actuele VibeScore van het doel.
    static func buildIntentModifier(
        goal: FitnessGoal,
        phase: TrainingPhase,
        readinessScore: Int?
    ) -> IntentModifier {
        let vibeScore = readinessScore ?? 70          // onbekend → neutraal
        let isHighReadiness = vibeScore > 65
        let isMultiDay      = goal.resolvedFormat == .multiDayStage

        // Completion-modus: aerobe basis, TENZIJ er een stretchGoalTime is én VibeScore hoog genoeg is.
        // Dan staat één temposessie per week toe — sporter wil finishen maar heeft ook een tijdsdoel.
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

        // Peak Performance-modus: intensiteit toegestaan als VibeScore hoog genoeg is
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

    // MARK: - Coaching Instructie Builders

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
