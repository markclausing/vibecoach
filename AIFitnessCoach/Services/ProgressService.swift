import Foundation

// MARK: - Epic 23: Blueprint Analysis & Future Projections — Sprint 1: Gap Analysis

/// Uitbreiding van GoalBlueprint met sportwetenschappelijke wekelijkse km-target.
/// Gebaseerd op standaard trainingsmodellen: de wekelijkse kilomeritage die een sporter
/// op piekniveau moet rijden/lopen om het doel te halen.
extension GoalBlueprint {
    /// Wekelijkse km-target in de opbouwfase (niet gecorrigeerd voor periodiseringsfase).
    var weeklyKmTarget: Double {
        switch goalType {
        case .marathon:     return 55.0   // Standaard marathon trainingsvolume (Pfitzinger 18/55)
        case .halfMarathon: return 40.0   // Halve marathon basisvolume
        case .cyclingTour:  return 180.0  // Fietstocht (Arnhem–Karlsruhe ~400 km over 4 dagen)
        }
    }
}

/// Het verschil tussen wat de Blueprint vereist en wat de atleet tot nu toe heeft bereikt.
/// Positieve waarden = achterstand, negatieve waarden = voorsprong.
struct BlueprintGap {
    /// Het doel waarop dit gap-rapport betrekking heeft.
    let goal: FitnessGoal

    /// Blueprint-type dat gedetecteerd werd (marathon, half marathon, cycling tour).
    let blueprintType: GoalBlueprintType

    /// De bijbehorende blueprint met de sportwetenschappelijke normen.
    let blueprint: GoalBlueprint

    // MARK: - TRIMP Gap

    /// Het totale TRIMP dat verdiend zou moeten zijn op basis van de lineaire progressie
    /// vanuit het begin van het doel tot vandaag. Berekend als:
    ///   vereist TRIMP = (computedTargetTRIMP / totale weken) × verlopen weken
    let requiredTRIMPToDate: Double

    /// Het totaal werkelijk verdiende TRIMP over alle activiteiten in de doelperiode.
    let actualTRIMPToDate: Double

    /// Verschil: positief = achterstand, negatief = voorsprong.
    var trimpGap: Double { requiredTRIMPToDate - actualTRIMPToDate }

    /// Percentage dat de atleet van de verwachte TRIMP heeft behaald (gecapped op 200%).
    var trimpProgressPct: Double {
        guard requiredTRIMPToDate > 0 else { return 0 }
        return min(2.0, actualTRIMPToDate / requiredTRIMPToDate)
    }

    // MARK: - Afstandsgap (alleen voor hardloop- en fietsdoelen)

    /// Vereiste totale afstand (km) op basis van lineaire progressie vanaf de startdatum.
    /// Gebruik: (blueprint.weeklyKmTarget / 7) × verlopen dagen
    let requiredKmToDate: Double

    /// Werkelijk totale afstand (km) over alle activiteiten in de doelperiode.
    let actualKmToDate: Double

    /// Verschil in km: positief = achterstand, negatief = voorsprong.
    var kmGap: Double { requiredKmToDate - actualKmToDate }

    /// Percentage van de verwachte afstand behaald (gecapped op 200%).
    var kmProgressPct: Double {
        guard requiredKmToDate > 0 else { return 0 }
        return min(2.0, actualKmToDate / requiredKmToDate)
    }

    // MARK: - Weken resterend

    /// Weken resterend tot de doeldatum.
    var weeksRemaining: Double {
        goal.targetDate.timeIntervalSince(Date()) / (7 * 86400)
    }

    /// Verlopen weken (vanaf goal.createdAt).
    var weeksElapsed: Double {
        Date().timeIntervalSince(goal.createdAt) / (7 * 86400)
    }

    // MARK: - Menselijk leesbare samenvatting

    /// True als er een significante achterstand is (>10% van het vereiste volume ontbreekt).
    var isBehindOnTRIMP: Bool { trimpGap > requiredTRIMPToDate * 0.10 }

    /// True als er een significante km-achterstand is (>10%).
    var isBehindOnKm: Bool { kmGap > requiredKmToDate * 0.10 }

    /// Een korte, leesbare zin over de TRIMP-status — voor de UI en de coach.
    var trimpStatusLine: String {
        let gapStr = String(format: "%.0f", abs(trimpGap))
        if trimpGap > 0 {
            return "Je ligt \(gapStr) TRIMP achter op het verwachte niveau."
        } else if trimpGap < 0 {
            return "Je ligt \(gapStr) TRIMP voor op het schema — goed bezig!"
        } else {
            return "Je zit precies op schema."
        }
    }

    /// Een korte, leesbare zin over de afstandsstatus — voor de UI en de coach.
    var kmStatusLine: String? {
        guard requiredKmToDate > 0 else { return nil }
        let gapKm = String(format: "%.0f", abs(kmGap))
        if kmGap > 0 {
            return "Je ligt \(gapKm) km achter op het verwachte schema voor \(goal.title)."
        } else if kmGap < 0 {
            return "Je hebt \(gapKm) km méér gereden dan vereist op dit punt."
        } else {
            return "Qua afstand zit je precies op schema."
        }
    }

    /// Volledig context-blok voor de AI-prompt injectie (Epic 23 Sprint 1).
    var coachContext: String {
        let weeksLeftStr = String(format: "%.1f", weeksRemaining)
        let pctStr       = String(format: "%.0f%%", trimpProgressPct * 100)
        var lines = [
            "Doel: '\(goal.title)' — \(weeksLeftStr) weken resterend",
            "Blueprint: \(blueprintType.displayName)",
            "TRIMP-voortgang: \(String(format: "%.0f", actualTRIMPToDate)) / \(String(format: "%.0f", requiredTRIMPToDate)) verdiend (\(pctStr))",
            trimpStatusLine
        ]
        if let kmLine = kmStatusLine {
            lines.append(kmLine)
        }
        // Geef de coach een concreet bijsturingsadvies als de atleet achterstaat
        if isBehindOnTRIMP {
            let extraPerWeek = weeksRemaining > 0 ? (trimpGap / weeksRemaining) : 0
            lines.append("📈 VOLUME-BIJSTURING NODIG: Om het tekort in te halen, moet de wekelijkse TRIMP de komende weken met \(String(format: "%.0f", extraPerWeek)) extra TRIMP/week stijgen. Vertel de gebruiker hoeveel procent meer volume dit betekent ten opzichte van de huidige belasting.")
        }
        if isBehindOnKm, requiredKmToDate > 0 {
            let extraKmPerWeek = weeksRemaining > 0 ? (kmGap / weeksRemaining) : 0
            lines.append("🚴 KM-BIJSTURING NODIG: \(String(format: "%.0f", extraKmPerWeek)) extra km/week zijn nodig om het schema alsnog te halen.")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - ProgressService

/// Berekent per actief doel het verschil tussen het sportwetenschappelijk verwachte
/// trainingsvolume en het daadwerkelijk behaalde volume tot nu toe.
///
/// Gebruik: `ProgressService.analyzeGaps(for: goals, activities: activities)`
struct ProgressService {

    // MARK: - Publieke API

    /// Berekent de BlueprintGap voor alle actieve doelen.
    /// - Parameters:
    ///   - goals: Alle actieve (niet-afgeronde) doelen.
    ///   - activities: Alle gesynchroniseerde activiteiten (HealthKit of Strava).
    /// - Returns: Gesorteerde array van BlueprintGap — doelen met de grootste achterstand eerste.
    static func analyzeGaps(for goals: [FitnessGoal], activities: [ActivityRecord]) -> [BlueprintGap] {
        let now = Date()
        return goals
            .filter { !$0.isCompleted && now < $0.targetDate }
            .compactMap { analyzeGap(for: $0, activities: activities) }
            .sorted { $0.trimpGap > $1.trimpGap } // Grootste achterstand eerst
    }

    // MARK: - Interne berekening per doel

    private static func analyzeGap(for goal: FitnessGoal, activities: [ActivityRecord]) -> BlueprintGap? {
        guard let blueprintType = BlueprintChecker.detectBlueprintType(for: goal) else { return nil }
        let blueprint = BlueprintChecker.blueprint(for: blueprintType)

        // Bepaal het sport-type voor de afstandsberekening
        let targetSport: SportCategory
        switch blueprintType {
        case .marathon, .halfMarathon: targetSport = .running
        case .cyclingTour:             targetSport = .cycling
        }

        let now       = Date()
        let startDate = goal.createdAt
        let totalDays = max(1.0, goal.targetDate.timeIntervalSince(startDate) / 86400)
        let elapsedDays = max(0.0, now.timeIntervalSince(startDate) / 86400)

        // Lineaire TRIMP-verwachting tot vandaag:
        //   required = (totale target TRIMP / totale looptijd in weken) × verlopen weken
        let totalWeeks   = totalDays / 7.0
        let elapsedWeeks = elapsedDays / 7.0
        let requiredTRIMP = (goal.computedTargetTRIMP / max(0.1, totalWeeks)) * elapsedWeeks

        // Werkelijk verdiend TRIMP in de doelperiode
        let activitiesInPeriod = activities.filter { $0.startDate >= startDate && $0.startDate <= now }
        let actualTRIMP = activitiesInPeriod.compactMap { $0.trimp }.reduce(0, +)

        // Afstandsberekening: wekelijkse km-target × verlopen weken
        let weeklyKmTarget = blueprint.weeklyKmTarget
        let requiredKm   = weeklyKmTarget * elapsedWeeks
        let actualKm     = activitiesInPeriod
            .filter { $0.sportCategory == targetSport }
            .map { $0.distance / 1000.0 }
            .reduce(0, +)

        return BlueprintGap(
            goal: goal,
            blueprintType: blueprintType,
            blueprint: blueprint,
            requiredTRIMPToDate: requiredTRIMP,
            actualTRIMPToDate: actualTRIMP,
            requiredKmToDate: requiredKm,
            actualKmToDate: actualKm
        )
    }
}
