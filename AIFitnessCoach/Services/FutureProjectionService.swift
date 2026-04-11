import Foundation

// MARK: - Epic 23 Sprint 2: Future Projection Engine

/// Projectiestatus — of de atleet de Peak Phase haalt vóór zijn racedag.
enum ProjectionStatus {
    /// Het huidige wekelijkse TRIMP voldoet al aan de Peak Phase-eis.
    case alreadyPeaking
    /// Prognose: de atleet haalt de Peak Phase vóór de geplande peakdatum.
    case onTrack
    /// Prognose: de atleet haalt de Peak Phase pas ná de geplande peakdatum,
    /// maar nog vóór de racedag — risico.
    case atRisk
    /// Wiskundig onhaalbaar: zelfs met 10% groei per week is de Peak Phase niet haalbaar
    /// vóór de racedag, of het huidige volume is nul/negatief.
    case unreachable

    /// Icoon voor de UI.
    var icon: String {
        switch self {
        case .alreadyPeaking: return "checkmark.seal.fill"
        case .onTrack:        return "arrow.up.right.circle.fill"
        case .atRisk:         return "exclamationmark.triangle.fill"
        case .unreachable:    return "xmark.circle.fill"
        }
    }

    /// Kleur voor de UI-badge.
    var color: String {
        switch self {
        case .alreadyPeaking, .onTrack: return "green"
        case .atRisk:                   return "orange"
        case .unreachable:              return "red"
        }
    }

    /// Korte beschrijving voor in de UI.
    var label: String {
        switch self {
        case .alreadyPeaking: return "Peak Phase bereikt"
        case .onTrack:        return "Op koers"
        case .atRisk:         return "Risico"
        case .unreachable:    return "Onhaalbaar"
        }
    }
}

/// De volledige toekomstprognose voor één doel.
///
/// Beantwoordt de vraag: "Wanneer bereikt de atleet de Peak Phase
/// op basis van zijn huidige groeitempo?"
struct GoalProjection {
    let goal: FitnessGoal
    let blueprintType: GoalBlueprintType

    // MARK: - Huidig volume (gemiddelde laatste 2 weken)

    /// Gemiddeld wekelijks TRIMP over de afgelopen 2 weken (referentiepunt voor projectie).
    let currentWeeklyTRIMP: Double

    /// Gemiddelde procentuele TRIMP-groei per week over de afgelopen 3 weken.
    /// Kan negatief zijn bij dalend volume.
    let observedGrowthRate: Double

    /// De daadwerkelijk toegepaste groeisnelheid (begrensd op 10% per week als veiligheidsgrens).
    let effectiveGrowthRate: Double

    // MARK: - Peak Phase vereiste

    /// Benodigde wekelijkse TRIMP voor de Peak Phase (blueprint × 1.30).
    let requiredPeakTRIMP: Double

    /// Gepland begin van de Peak Phase — 4 weken vóór de racedag.
    let plannedPeakDate: Date

    // MARK: - Projectieresultaat

    /// Berekende datum waarop het huidige groeitempo de Peak Phase-eis bereikt.
    /// Nil bij `alreadyPeaking` of wanneer groei nul/negatief is en status `unreachable`.
    let projectedPeakDate: Date?

    /// Aantal weken dat de projectie afwijkt van het plan.
    /// Positief = te laat (achter), negatief = eerder dan gepland (voorsprong).
    let weeksDelta: Double

    /// De definitieve projectiestatus.
    let status: ProjectionStatus

    // MARK: - Coach context

    var coachContext: String {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        df.locale = Locale(identifier: "nl_NL")

        let plannedStr    = df.string(from: plannedPeakDate)
        let targetStr     = df.string(from: goal.targetDate)
        let currentInt    = Int(currentWeeklyTRIMP.rounded())
        let requiredInt   = Int(requiredPeakTRIMP.rounded())
        let growthPct     = Int((observedGrowthRate * 100).rounded())

        var lines: [String] = [
            "Doel: '\(goal.title)' — racedag \(targetStr)",
            "Huidig wekelijks volume: ~\(currentInt) TRIMP/week | Peak Phase-eis: ~\(requiredInt) TRIMP/week",
            "Gemeten groeitempo: \(growthPct)% per week (max toegestaan: 10%)"
        ]

        switch status {
        case .alreadyPeaking:
            lines.append("✅ PROGNOSE: Atleet bevindt zich al op Peak Phase-belasting. Geen extra opbouw nodig — vasthouden en straks taperen.")

        case .onTrack:
            let projStr = projectedPeakDate.map { df.string(from: $0) } ?? "—"
            let delta   = Int(abs(weeksDelta).rounded())
            lines.append("🟢 PROGNOSE: Peak Phase wordt bereikt ~\(projStr) — \(delta) week(en) vóór het geplande piekmoment (\(plannedStr)). Atleet ligt voor op schema.")

        case .atRisk:
            let projStr = projectedPeakDate.map { df.string(from: $0) } ?? "—"
            let delta   = Int(abs(weeksDelta).rounded())
            lines.append("🟠 PROGNOSE: Peak Phase bereikt pas ~\(projStr) — \(delta) week(en) ná het geplande piekmoment (\(plannedStr)). De voorbereiding loopt achter. Coach MOET het weekvolume verhogen om dit in te halen.")
            lines.append("Instructie: Verhoog het wekelijkse trainingsvolume de komende weken geleidelijk met maximaal 10% per week om de prognose te verbeteren. Geef een concreet voorbeeld van hoe de gebruiker één training kan verlengen.")

        case .unreachable:
            lines.append("🔴 PROGNOSE: Wiskundig onhaalbaar om de Peak Phase te bereiken vóór de racedag \(targetStr) met de huidige groeisnelheid van \(growthPct)%. Zelfs met het maximaal toegestane groeiplafond van 10%/week is de Peak Phase niet haalbaar zonder overtraining.")
            lines.append("KRITIEKE INSTRUCTIE: Bespreek dit open met de atleet. Opties: (1) de doeldatum uitstellen, (2) het doeltype aanpassen (bijv. marathonambities naar halve marathon), (3) de resterende tijd maximaal benutten en de race als 'trainingsrace' beschouwen.")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - FutureProjectionService

struct FutureProjectionService {

    /// Maximaal toegestane wekelijkse TRIMP-groei (sportwetenschappelijke 10%-regel).
    static let maxWeeklyGrowthRate: Double = 0.10

    /// Aantal weken vóór de racedag dat de Peak Phase idealiter begint.
    static let peakPhaseStartWeeksBefore: Int = 4

    // MARK: - Publieke API

    /// Berekent de toekomstprognose voor alle actieve doelen met een blueprint.
    static func calculateProjections(
        for goals: [FitnessGoal],
        activities: [ActivityRecord]
    ) -> [GoalProjection] {
        goals
            .filter { !$0.isCompleted && Date() < $0.targetDate }
            .compactMap { calculateProjection(for: $0, activities: activities) }
    }

    // MARK: - Interne berekening

    static func calculateProjection(
        for goal: FitnessGoal,
        activities: [ActivityRecord]
    ) -> GoalProjection? {
        guard let blueprintType = BlueprintChecker.detectBlueprintType(for: goal) else { return nil }
        let blueprint = BlueprintChecker.blueprint(for: blueprintType)
        let calendar  = Calendar.current
        let now       = Date()

        // STAP 1: Wekelijkse TRIMP berekenen over de afgelopen 4 weken (sliding windows).
        // Week 0 = afgelopen 7 dagen (meest recent), week 3 = 21–28 dagen geleden.
        let weeklyTRIMP = (0..<4).map { weekIndex -> Double in
            let end   = calendar.date(byAdding: .day, value: -(weekIndex * 7),     to: now) ?? now
            let start = calendar.date(byAdding: .day, value: -((weekIndex + 1) * 7), to: now) ?? now
            return activities
                .filter { $0.startDate >= start && $0.startDate < end }
                .compactMap { $0.trimp }
                .reduce(0, +)
        }
        // weeklyTRIMP[0] = meest recente week, [3] = oudste week

        // STAP 2: Huidig volume = gemiddelde van de twee meest recente weken.
        let currentWeeklyTRIMP = (weeklyTRIMP[0] + weeklyTRIMP[1]) / 2.0

        // STAP 3: Groeitempo berekenen op basis van de drie meest recente complete weken.
        // Gebruik week[1] (1w oud) en week[3] (3w oud) voor een stabielere schatting.
        // Groei = (recent - oud) / oud / periodelengte
        let observedGrowthRate: Double
        let olderTRIMP = (weeklyTRIMP[2] + weeklyTRIMP[3]) / 2.0  // gemiddelde week 2–3 geleden
        if olderTRIMP > 5 {
            // Procentuele groei over de 2-weeks periode (van week 2-3 naar week 0-1)
            let recentAvg = currentWeeklyTRIMP
            observedGrowthRate = (recentAvg - olderTRIMP) / olderTRIMP / 2.0  // /2 = per week
        } else {
            // Onvoldoende historische data — neem 0% groei als conservatieve schatting
            observedGrowthRate = 0.0
        }

        // Begrenzen op het 10%-plafond (sportwetenschappelijke veiligheidsgrens)
        let effectiveGrowthRate = min(observedGrowthRate, maxWeeklyGrowthRate)

        // STAP 4: Peak Phase-eis berekenen.
        // Peak Phase-multiplier = 1.30 (zie TrainingPhase.peakPhase.multiplier)
        let requiredPeakTRIMP  = blueprint.weeklyTrimpTarget * TrainingPhase.peakPhase.multiplier
        let plannedPeakDate    = calendar.date(
            byAdding: .weekOfYear,
            value: -peakPhaseStartWeeksBefore,
            to: goal.targetDate
        ) ?? goal.targetDate

        // STAP 5: Status bepalen.
        // Geval A: Atleet zit al op of boven de Peak Phase-eis.
        if currentWeeklyTRIMP >= requiredPeakTRIMP {
            return GoalProjection(
                goal: goal,
                blueprintType: blueprintType,
                currentWeeklyTRIMP: currentWeeklyTRIMP,
                observedGrowthRate: observedGrowthRate,
                effectiveGrowthRate: effectiveGrowthRate,
                requiredPeakTRIMP: requiredPeakTRIMP,
                plannedPeakDate: plannedPeakDate,
                projectedPeakDate: nil,
                weeksDelta: 0,
                status: .alreadyPeaking
            )
        }

        // Geval B: Volume is (bijna) nul of groei is nul/negatief.
        // Dan is de Peak Phase nooit haalbaar — controleer eerst of capped growth >= 0.
        guard currentWeeklyTRIMP > 5, effectiveGrowthRate > 0 else {
            return GoalProjection(
                goal: goal,
                blueprintType: blueprintType,
                currentWeeklyTRIMP: currentWeeklyTRIMP,
                observedGrowthRate: observedGrowthRate,
                effectiveGrowthRate: effectiveGrowthRate,
                requiredPeakTRIMP: requiredPeakTRIMP,
                plannedPeakDate: plannedPeakDate,
                projectedPeakDate: nil,
                weeksDelta: goal.targetDate.timeIntervalSince(now) / (7 * 86400),
                status: .unreachable
            )
        }

        // STAP 6: Berekenen hoeveel weken er nodig zijn om de Peak Phase-eis te bereiken.
        // Formule: currentTRIMP × (1 + r)^n = requiredTRIMP
        //       → n = log(required / current) / log(1 + r)
        let weeksNeeded = log(requiredPeakTRIMP / currentWeeklyTRIMP) / log(1.0 + effectiveGrowthRate)

        guard weeksNeeded.isFinite, weeksNeeded >= 0 else {
            return GoalProjection(
                goal: goal,
                blueprintType: blueprintType,
                currentWeeklyTRIMP: currentWeeklyTRIMP,
                observedGrowthRate: observedGrowthRate,
                effectiveGrowthRate: effectiveGrowthRate,
                requiredPeakTRIMP: requiredPeakTRIMP,
                plannedPeakDate: plannedPeakDate,
                projectedPeakDate: nil,
                weeksDelta: 0,
                status: .unreachable
            )
        }

        let projectedPeakDate = calendar.date(
            byAdding: .day,
            value: Int((weeksNeeded * 7).rounded()),
            to: now
        ) ?? now

        // Weken afwijking t.o.v. geplande peakdatum:
        // positief = projectedDate is ná plannedPeakDate (achter)
        // negatief = projectedDate is vóór plannedPeakDate (voor)
        let weeksDelta = projectedPeakDate.timeIntervalSince(plannedPeakDate) / (7 * 86400)

        // Status bepalen
        let status: ProjectionStatus
        if projectedPeakDate <= plannedPeakDate {
            status = .onTrack
        } else if projectedPeakDate <= goal.targetDate {
            status = .atRisk
        } else {
            status = .unreachable
        }

        return GoalProjection(
            goal: goal,
            blueprintType: blueprintType,
            currentWeeklyTRIMP: currentWeeklyTRIMP,
            observedGrowthRate: observedGrowthRate,
            effectiveGrowthRate: effectiveGrowthRate,
            requiredPeakTRIMP: requiredPeakTRIMP,
            plannedPeakDate: plannedPeakDate,
            projectedPeakDate: projectedPeakDate,
            weeksDelta: weeksDelta,
            status: status
        )
    }

    // MARK: - Coach context builder

    /// Bouwt het `[PROGNOSE]` blok voor de AI-prompt.
    static func buildCoachContext(from projections: [GoalProjection]) -> String {
        guard !projections.isEmpty else { return "" }
        var lines = ["[PROGNOSE — TOEKOMSTPROJECTIE (Sprint 23.2):"]
        for projection in projections {
            lines.append(projection.coachContext)
            lines.append("")
        }
        lines.append("Gedragsregel: Als de prognose 'Risico' of 'Onhaalbaar' toont, MOET de coach proactief een concreet bijsturingsplan voorstellen — zonder dat de gebruiker er om vraagt.]")
        return lines.joined(separator: "\n")
    }
}
