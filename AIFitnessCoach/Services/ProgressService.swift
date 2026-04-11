import Foundation

// MARK: - Epic 23: Blueprint Analysis & Future Projections — Sprint 1: Gap Analysis

/// Uitbreiding van GoalBlueprint met sportwetenschappelijke wekelijkse km-target.
extension GoalBlueprint {
    /// Wekelijkse km-target in de opbouwfase (niet gecorrigeerd voor periodiseringsfase).
    var weeklyKmTarget: Double {
        switch goalType {
        case .marathon:     return 55.0   // Pfitzinger 18/55
        case .halfMarathon: return 40.0
        case .cyclingTour:  return 180.0  // Arnhem–Karlsruhe ~400 km / 4 dagen
        }
    }
}

/// De cumulatieve trainingsachterstand (of voorsprong) binnen de huidige trainingsfase.
///
/// De berekening kijkt NIET naar de wekelijkse reset, maar accumuleert het totale tekort
/// vanaf het begin van de huidige fase (bijv. Build Phase week 1) tot vandaag.
/// Als je vorige week 20 km te weinig deed, begint week 2 al 20 km in de min.
struct BlueprintGap {
    let goal: FitnessGoal
    let blueprintType: GoalBlueprintType
    let blueprint: GoalBlueprint

    // MARK: - Fase context

    /// De huidige trainingsfase (Base / Build / Peak / Taper).
    let currentPhase: TrainingPhase

    /// Datum waarop de huidige fase begon (max van fasestart en goal.createdAt).
    let phaseStartDate: Date

    /// Datum waarop de huidige fase eindigt (overgang naar volgende fase).
    let phaseEndDate: Date

    /// Huidig weeknummer binnen de fase (1-gebaseerd).
    let phaseWeekNumber: Int

    /// Totaal aantal weken in de huidige fase.
    let phaseTotalWeeks: Int

    // MARK: - TRIMP (cumulatief binnen fase)

    /// Verwacht cumulatief TRIMP vanaf fasestart tot vandaag (lineair geïnterpoleerd).
    let requiredTRIMPToDate: Double

    /// Werkelijk behaald cumulatief TRIMP vanaf fasestart tot vandaag.
    let actualTRIMPToDate: Double

    /// Totale TRIMP-target voor de gehele fase (= referentie voor de volle balk).
    let totalPhaseTRIMPTarget: Double

    // MARK: - Km (cumulatief binnen fase)

    /// Verwachte cumulatieve km vanaf fasestart tot vandaag (lineair geïnterpoleerd).
    let requiredKmToDate: Double

    /// Werkelijke cumulatieve km vanaf fasestart tot vandaag.
    let actualKmToDate: Double

    /// Totale km-target voor de gehele fase.
    let totalPhaseKmTarget: Double

    // MARK: - Afgeleide waarden

    /// Verschil TRIMP: positief = achterstand, negatief = voorsprong.
    var trimpGap: Double { requiredTRIMPToDate - actualTRIMPToDate }

    /// Verschil km: positief = achterstand, negatief = voorsprong.
    var kmGap: Double { requiredKmToDate - actualKmToDate }

    /// Weken resterend tot de doeldatum.
    var weeksRemaining: Double {
        goal.targetDate.timeIntervalSince(Date()) / (7 * 86400)
    }

    // MARK: - Voortgangspercentages (t.o.v. VOLLEDIGE fase, niet dagdoel)
    // Zo staat de balk op 0% aan het begin van de fase en op 100% aan het einde,
    // ongeacht hoeveel tijd er al verstreken is.

    /// Hoeveel van het totale fase-TRIMP je al hebt behaald (0.0 – 1.0).
    var trimpProgressPct: Double {
        guard totalPhaseTRIMPTarget > 0 else { return 0 }
        return min(1.0, actualTRIMPToDate / totalPhaseTRIMPTarget)
    }

    /// Waar je vandaag op de balk zou moeten staan — de "ghost" positie (0.0 – 1.0).
    var trimpReferencePct: Double {
        guard totalPhaseTRIMPTarget > 0 else { return 0 }
        return min(1.0, requiredTRIMPToDate / totalPhaseTRIMPTarget)
    }

    /// Hoeveel van de totale fase-km je al hebt behaald (0.0 – 1.0).
    var kmProgressPct: Double {
        guard totalPhaseKmTarget > 0 else { return 0 }
        return min(1.0, actualKmToDate / totalPhaseKmTarget)
    }

    /// Waar je vandaag op de km-balk zou moeten staan — de "ghost" positie (0.0 – 1.0).
    var kmReferencePct: Double {
        guard totalPhaseKmTarget > 0 else { return 0 }
        return min(1.0, requiredKmToDate / totalPhaseKmTarget)
    }

    // MARK: - Drempelwaarden

    var isBehindOnTRIMP: Bool { trimpGap > requiredTRIMPToDate * 0.10 }
    var isBehindOnKm: Bool    { kmGap > requiredKmToDate * 0.10 }

    // MARK: - UI-teksten

    /// Label boven de voortgangsbalk: "Voortgang Build Phase (Week 3/8)"
    var phaseProgressLabel: String {
        "\(currentPhase.displayName) (Week \(phaseWeekNumber)/\(phaseTotalWeeks))"
    }

    /// Status tekst TRIMP — cumulatief in de fase.
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

    /// Status tekst km — cumulatief in de fase.
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

    // MARK: - Coach context (AI-prompt injectie)

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
        if isBehindOnTRIMP {
            let extraPerWeek = weeksRemaining > 0 ? (trimpGap / weeksRemaining) : 0
            lines.append("📈 VOLUME-BIJSTURING: Om het fase-tekort in te halen, \(String(format: "%.0f", extraPerWeek)) extra TRIMP/week de komende weken.")
        }
        if isBehindOnKm, totalPhaseKmTarget > 0 {
            let extraKmPerWeek = weeksRemaining > 0 ? (kmGap / weeksRemaining) : 0
            lines.append("🚴 KM-BIJSTURING: \(String(format: "%.0f", extraKmPerWeek)) extra km/week nodig voor het afstandsschema.")
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

    // MARK: - Interne berekening

    private static func analyzeGap(for goal: FitnessGoal, activities: [ActivityRecord]) -> BlueprintGap? {
        guard let blueprintType = BlueprintChecker.detectBlueprintType(for: goal) else { return nil }
        let blueprint = BlueprintChecker.blueprint(for: blueprintType)

        let now = Date()
        let weeksRemaining = goal.targetDate.timeIntervalSince(now) / (7 * 86400)
        let phase = TrainingPhase.calculate(weeksRemaining: weeksRemaining)

        // Sport-type voor afstandsberekening
        let targetSport: SportCategory
        switch blueprintType {
        case .marathon, .halfMarathon: targetSport = .running
        case .cyclingTour:             targetSport = .cycling
        }

        // Bereken de begin- en einddatum van de huidige fase
        // De faseovergangen zijn gedefinieerd in TrainingPhase.calculate:
        //   tapering    < 2 weken
        //   peakPhase   2–4 weken
        //   buildPhase  4–12 weken
        //   baseBuilding ≥ 12 weken
        let calendar = Calendar.current
        let (phaseStartDate, phaseEndDate) = phaseDateRange(
            phase: phase,
            targetDate: goal.targetDate,
            goalCreatedAt: goal.createdAt,
            calendar: calendar
        )

        let phaseDurationDays = max(1.0, phaseEndDate.timeIntervalSince(phaseStartDate) / 86400)
        let elapsedDaysInPhase = max(0.0, min(phaseDurationDays, now.timeIntervalSince(phaseStartDate) / 86400))

        let phaseTotalWeeks   = phaseDurationDays / 7.0
        let elapsedWeeksInPhase = elapsedDaysInPhase / 7.0

        // Weeknummer binnen de fase (1-gebaseerd, max is phaseTotalWeeks)
        let phaseWeekNumber   = max(1, Int(ceil(elapsedWeeksInPhase)))
        let phaseTotalWeeksInt = max(1, Int(ceil(phaseTotalWeeks)))

        // Fase-gecorrigeerde wekelijkse TRIMP-target (blueprint × fase-multiplier)
        let adjustedWeeklyTRIMP = blueprint.weeklyTrimpTarget * phase.multiplier

        // Totale TRIMP-target voor de hele fase
        let totalPhaseTRIMP = adjustedWeeklyTRIMP * phaseTotalWeeks

        // Verwacht cumulatief TRIMP vandaag = lineair geïnterpoleerd
        let requiredTRIMP = adjustedWeeklyTRIMP * elapsedWeeksInPhase

        // Werkelijk verdiend TRIMP in deze fase
        let phaseActivities = activities.filter {
            $0.startDate >= phaseStartDate && $0.startDate <= now
        }
        let actualTRIMP = phaseActivities.compactMap { $0.trimp }.reduce(0, +)

        // Km-berekening (fase-gewogen: km-target × fase-multiplier voor fietsen/lopen)
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

    /// Berekent de startdatum en einddatum van een trainingsfase op basis van de doeldatum.
    /// De faseovergangen zijn gesynchroniseerd met TrainingPhase.calculate:
    ///   baseBuilding  → eindigt 12 weken voor de race
    ///   buildPhase    → eindigt 4 weken voor de race
    ///   peakPhase     → eindigt 2 weken voor de race
    ///   tapering      → eindigt op de racedag
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
            nominalStart = goalCreatedAt  // Base begint bij aanmaken doel
        case .buildPhase:
            end          = calendar.date(byAdding: .weekOfYear, value: -4,  to: targetDate) ?? targetDate
            nominalStart = calendar.date(byAdding: .weekOfYear, value: -12, to: targetDate) ?? targetDate
        case .peakPhase:
            end          = calendar.date(byAdding: .weekOfYear, value: -2,  to: targetDate) ?? targetDate
            nominalStart = calendar.date(byAdding: .weekOfYear, value: -4,  to: targetDate) ?? targetDate
        case .tapering:
            end          = targetDate
            nominalStart = calendar.date(byAdding: .weekOfYear, value: -2,  to: targetDate) ?? targetDate
        }

        // Als het doel aangemaakt werd ná de nominale fasestart, gebruik createdAt als start.
        // Dit voorkomt dat activiteiten van vóór het doel meegeteld worden.
        let start = max(nominalStart, goalCreatedAt)
        return (start, end)
    }
}
