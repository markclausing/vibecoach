import Foundation

// MARK: - Epic 23 Sprint 2 (Fix): Future Projection Engine — Bottleneck-gebaseerde projectie

// ──────────────────────────────────────────────────────────────────────────────
// BUGFIX RATIONALE
// ──────────────────────────────────────────────────────────────────────────────
// Origineel probleem: het algoritme berekende de projectiedatum puur op basis van
// TRIMP (alle activiteiten), zonder onderscheid tussen sport-types. Een marathonloper
// met een blessure die tijdelijk fietst, accumuleerde fietsen-TRIMP waardoor de
// marathon-projectie optimistisch werd — terwijl de hardloop-km nog ver achterliep.
//
// De fix bestaat uit drie lagen:
//   1. SPORT-ISOLATIE: km-trend wordt uitsluitend berekend op activiteiten van
//      het doelsport-type (hardlopen → .running, fietsen → .cycling).
//   2. BOTTLENECK-REGEL: projectedPeakDate = max(TRIMP-datum, km-datum).
//      De langzaamst groeiende of verst achterlopende metric bepaalt de datum.
//   3. VEILIGHEIDSCHECK: als de cumulatieve km-achterstand > 5% van de target
//      is, kan de projectie nooit vroeger vallen dan de plannedPeakDate.
// ──────────────────────────────────────────────────────────────────────────────

/// Welke metric de projectiedatum bepaalt (voor UI-toelichting en coach-context).
enum BottleneckMetric {
    case trimp       // TRIMP is de beperkende factor (km loopt voor)
    case km          // Km is de bottleneck (sport-specifiek volume loopt achter)
    case both        // Beide unreachable of beide gelijk
    case alreadyMet  // Atleet voldoet al aan beide eisen
}

/// Projectiestatus — of de atleet de Peak Phase haalt vóór zijn racedag.
enum ProjectionStatus {
    /// Het huidige wekelijkse TRIMP én km voldoen al aan de Peak Phase-eis.
    case alreadyPeaking
    /// Prognose: de atleet haalt de Peak Phase vóór de geplande peakdatum.
    case onTrack
    /// Prognose: de atleet haalt de Peak Phase pas ná de geplande peakdatum,
    /// maar nog vóór de racedag — risico.
    case atRisk
    /// Wiskundig onhaalbaar met huidige groei, maar race > 12 weken weg —
    /// voldoende tijd voor een gerichte inhaalslag. Oranje, niet rood.
    case catchUpNeeded
    /// Wiskundig onhaalbaar: zelfs met maximale groeicap is de Peak Phase niet haalbaar
    /// vóór de racedag (race < 12 weken weg), of het huidige volume is nul/negatief.
    case unreachable

    var icon: String {
        switch self {
        case .alreadyPeaking: return "checkmark.seal.fill"
        case .onTrack:        return "arrow.up.right.circle.fill"
        case .atRisk:         return "exclamationmark.triangle.fill"
        case .catchUpNeeded:  return "arrow.up.circle.fill"
        case .unreachable:    return "xmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .alreadyPeaking, .onTrack:    return "green"
        case .atRisk, .catchUpNeeded:      return "orange"
        case .unreachable:                 return "red"
        }
    }

    var label: String {
        switch self {
        case .alreadyPeaking: return "Peak Phase bereikt"
        case .onTrack:        return "Op koers"
        case .atRisk:         return "Risico"
        case .catchUpNeeded:  return "Inhaalslag nodig"
        case .unreachable:    return "Onhaalbaar"
        }
    }
}

/// De volledige toekomstprognose voor één doel — bottleneck-gebaseerd.
struct GoalProjection {
    let goal: FitnessGoal
    let blueprintType: GoalBlueprintType

    // MARK: - TRIMP metrics (alle activiteiten — sport-onafhankelijk)

    let currentWeeklyTRIMP: Double
    let observedGrowthRate: Double
    let effectiveGrowthRate: Double
    let requiredPeakTRIMP: Double

    // MARK: - KM metrics (STRIKT sport-gefilterd)
    // Marathon/halve marathon → alleen .running activiteiten
    // Fietstocht             → alleen .cycling activiteiten

    let currentWeeklyKm: Double
    let kmObservedGrowthRate: Double
    let effectiveKmGrowthRate: Double
    let requiredPeakKm: Double

    // MARK: - Projectieresultaten per metric

    /// Datum waarop TRIMP de piekeis bereikt (nil als al voldaan of onbereikbaar).
    let projectedPeakDateTRIMP: Date?

    /// Datum waarop km de piekeis bereikt (nil als al voldaan of onbereikbaar).
    let projectedPeakDateKm: Date?

    // MARK: - Bottleneck: de bepaler van de finale projectiedatum

    /// De metric die de einddatum bepaalt.
    let bottleneck: BottleneckMetric

    // MARK: - Finale projectieresultaten (UI + coach)

    let plannedPeakDate: Date
    let projectedPeakDate: Date?
    let weeksDelta: Double
    let status: ProjectionStatus

    /// True als de Cross-Training Bonus actief was: TRIMP ≥ 90% van basisweekdoel,
    /// waardoor de km-groeicap verhoogd werd van 10% naar 17%.
    let hasCrossTrainingBonus: Bool

    // MARK: - Coach context

    var coachContext: String {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        df.locale = Locale(identifier: "nl_NL")

        let plannedStr   = df.string(from: plannedPeakDate)
        let targetStr    = df.string(from: goal.targetDate)
        let trimpInt     = Int(currentWeeklyTRIMP.rounded())
        let kmStr        = String(format: "%.1f", currentWeeklyKm)
        let reqTRIMPInt  = Int(requiredPeakTRIMP.rounded())
        let reqKmStr     = String(format: "%.1f", requiredPeakKm)
        let growthPct    = Int((observedGrowthRate * 100).rounded())
        let kmGrowthPct  = Int((kmObservedGrowthRate * 100).rounded())
        let kmCapPct     = hasCrossTrainingBonus ? 17 : 10

        var lines: [String] = [
            "Doel: '\(goal.title)' — racedag \(targetStr)",
            "Huidig wekelijks TRIMP: ~\(trimpInt) (piek-eis: ~\(reqTRIMPInt)) | "
                + "Huidig wekelijks \(kmLabel): ~\(kmStr) km (piek-eis: ~\(reqKmStr) km)",
            "TRIMP-groei: \(growthPct)%/week | \(kmLabel)-groei: \(kmGrowthPct)%/week (max \(kmCapPct)%"
                + (hasCrossTrainingBonus ? " — Cross-Training Bonus actief" : "") + ")",
        ]

        switch bottleneck {
        case .km:
            if hasCrossTrainingBonus {
                lines.append("⚠️ BOTTLENECK: \(kmLabel) is de beperkende factor. "
                    + "MAAR: de aerobe basis (TRIMP) is sterk genoeg (≥ 90% van basisweekdoel). "
                    + "Cross-Training Bonus: groeicap km verhoogd naar 17%/week. "
                    + "Zodra de atleet hersteld is van de blessure, kan het loopvolume sneller worden opgebouwd. "
                    + "Instructie: focus op herstel van de specifieke sport — niet op meer algemene cardio.")
            } else {
                lines.append("⚠️ BOTTLENECK: Het sport-specifieke kilometers-volume (\(kmLabel)) is de beperkende factor. "
                    + "Hoge TRIMP van andere sporten (bijv. fietsen bij een hardloopblessure) telt NIET mee voor deze projectie.")
            }
        case .trimp:
            lines.append("ℹ️ TRIMP is de beperkende factor. Het \(kmLabel)-volume ligt al op schema.")
        case .both:
            lines.append("⚠️ BEIDE metrics (TRIMP én \(kmLabel)) lopen achter op schema.")
        case .alreadyMet:
            break
        }

        switch status {
        case .alreadyPeaking:
            lines.append("✅ PROGNOSE: Atleet bevindt zich al op Peak Phase-belasting voor beide metrics. Vasthouden en taperen.")

        case .onTrack:
            let projStr = projectedPeakDate.map { df.string(from: $0) } ?? "—"
            let delta   = Int(abs(weeksDelta).rounded())
            lines.append("🟢 PROGNOSE: Peak Phase bereikt ~\(projStr) — \(delta) week(en) vóór \(plannedStr). Op schema.")

        case .atRisk:
            let projStr = projectedPeakDate.map { df.string(from: $0) } ?? "—"
            let delta   = Int(abs(weeksDelta).rounded())
            lines.append("🟠 PROGNOSE: Peak Phase pas ~\(projStr) — \(delta) week(en) ná \(plannedStr). "
                + "Coach MOET het volume verhogen. Instructie: geef concreet voorbeeld hoe één training verlengd kan worden.")

        case .catchUpNeeded:
            let projStr = projectedPeakDate.map { df.string(from: $0) } ?? "—"
            let delta   = Int(abs(weeksDelta).rounded())
            lines.append("🟠 PROGNOSE: Race > 12 weken weg — er is tijd voor een inhaalslag. "
                + "Piekbelasting verwacht ~\(projStr) — \(delta) week(en) ná \(plannedStr). "
                + "INSTRUCTIE: Stel een geleidelijk opbouwplan voor de komende 4–6 weken. "
                + "Noem de situatie constructief — niet alarmerend.")

        case .unreachable:
            lines.append("🔴 PROGNOSE: Wiskundig onhaalbaar vóór racedag \(targetStr). "
                + "KRITIEKE INSTRUCTIE: Bespreek met de atleet: (1) doeldatum uitstellen, "
                + "(2) doeltype aanpassen of (3) race als trainingsrace beschouwen.")
        }

        return lines.joined(separator: "\n")
    }

    private var kmLabel: String {
        switch blueprintType {
        case .marathon, .halfMarathon: return "hardloop-km"
        case .cyclingTour:             return "fiets-km"
        }
    }
}

// MARK: - FutureProjectionService

struct FutureProjectionService {

    /// Maximaal toegestane wekelijkse groei (sportwetenschappelijke 10%-regel).
    static let maxWeeklyGrowthRate: Double = 0.10

    /// Verhoogde groeicap bij Cross-Training Bonus: atleet heeft sterke aerobe basis
    /// (TRIMP ≥ 90% van basisweekdoel) maar loopt achter op sport-specifieke km.
    /// Sportwetenschappelijk verantwoord: goede aeroob-getrainde atleet kan sneller opbouwen.
    static let maxWeeklyGrowthRateCrossTraining: Double = 0.17

    /// Minimale TRIMP-ratio t.o.v. basisweekdoel om Cross-Training Bonus te activeren.
    static let trimpOnScheduleThreshold: Double = 0.90

    /// Weken tot racedag waarbij 'Onhaalbaar' (rood) mag worden getoond.
    /// Daarboven toont de app 'Inhaalslag nodig' (oranje) — er is nog genoeg tijd.
    static let gracePeriodWeeks: Int = 12

    /// Weken vóór racedag dat Peak Phase idealiter begint.
    static let peakPhaseStartWeeksBefore: Int = 4

    /// Km-achterstand t.o.v. target waarbij de veiligheidscap actief wordt.
    /// 5% onder de piek-eis = projectie nooit eerder dan plannedPeakDate.
    static let kmSafetyThreshold: Double = 0.95

    // MARK: - Publieke API

    static func calculateProjections(
        for goals: [FitnessGoal],
        activities: [ActivityRecord]
    ) -> [GoalProjection] {
        goals
            .filter { !$0.isCompleted && Date() < $0.targetDate }
            .compactMap { calculateProjection(for: $0, activities: activities) }
    }

    // MARK: - Kernalgoritme

    static func calculateProjection(
        for goal: FitnessGoal,
        activities: [ActivityRecord]
    ) -> GoalProjection? {
        guard let blueprintType = BlueprintChecker.detectBlueprintType(for: goal) else { return nil }
        let blueprint = BlueprintChecker.blueprint(for: blueprintType)
        let calendar  = Calendar.current
        let now       = Date()

        // ── Stap 1: Doelsport bepalen (strikt — geen cross-sport compensatie) ──
        let targetSport: SportCategory
        switch blueprintType {
        case .marathon, .halfMarathon: targetSport = .running
        case .cyclingTour:             targetSport = .cycling
        }

        // ── Stap 2: Wekelijkse sliding windows (afgelopen 4 weken) ──
        // week[0] = meest recent (0–7 dagen geleden)
        // week[3] = oudst (21–28 dagen geleden)
        let weeklyTRIMP: [Double] = (0..<4).map { i in
            let end   = calendar.date(byAdding: .day, value: -(i * 7),       to: now) ?? now
            let start = calendar.date(byAdding: .day, value: -((i + 1) * 7), to: now) ?? now
            return activities
                .filter { $0.startDate >= start && $0.startDate < end }
                .compactMap { $0.trimp }
                .reduce(0, +)
        }

        // Km: ALLEEN de doelsport — fiets-km tellen niet mee voor een hardloopdoel
        let weeklyKm: [Double] = (0..<4).map { i in
            let end   = calendar.date(byAdding: .day, value: -(i * 7),       to: now) ?? now
            let start = calendar.date(byAdding: .day, value: -((i + 1) * 7), to: now) ?? now
            let sportActivities = activities.filter {
                $0.startDate >= start && $0.startDate < end && $0.sportCategory == targetSport
            }
            return sportActivities.map { $0.distance / 1000.0 }.reduce(0, +)
        }

        // ── Stap 3: Huidig volume (gemiddelde laatste 2 weken) ──
        let currentWeeklyTRIMP = (weeklyTRIMP[0] + weeklyTRIMP[1]) / 2.0
        let currentWeeklyKm    = (weeklyKm[0]    + weeklyKm[1])    / 2.0

        // ── Stap 3b: Cross-Training Bonus ──
        // Als de algehele TRIMP (inclusief cross-training) op schema is maar de
        // sport-specifieke km achterlopen (bijv. kuitblessure), krijgt de atleet
        // een hogere km-groeicap. Een goede aerobe basis versnelt het herstel.
        let hasCrossTrainingBonus = currentWeeklyTRIMP >= trimpOnScheduleThreshold * blueprint.weeklyTrimpTarget
        let kmGrowthCap = hasCrossTrainingBonus ? maxWeeklyGrowthRateCrossTraining : maxWeeklyGrowthRate

        // ── Stap 4: Groeisnelheid per metric ──
        // Vergelijk gemiddelde week 0–1 met gemiddelde week 2–3, gedeeld door 2 weken.
        let olderTRIMP = (weeklyTRIMP[2] + weeklyTRIMP[3]) / 2.0
        let observedTRIMPGrowth: Double = olderTRIMP > 5
            ? (currentWeeklyTRIMP - olderTRIMP) / olderTRIMP / 2.0
            : 0.0

        let olderKm = (weeklyKm[2] + weeklyKm[3]) / 2.0
        let observedKmGrowth: Double = olderKm > 0.5
            ? (currentWeeklyKm - olderKm) / olderKm / 2.0
            : 0.0

        let effectiveGrowthRate   = min(observedTRIMPGrowth, maxWeeklyGrowthRate)
        let effectiveKmGrowthRate = min(observedKmGrowth,    kmGrowthCap)

        // ── Stap 5: Piek-eisen (blueprint × Peak Phase multiplier 1.30) ──
        let requiredPeakTRIMP = blueprint.weeklyTrimpTarget * TrainingPhase.peakPhase.multiplier
        let requiredPeakKm    = blueprint.weeklyKmTarget    * TrainingPhase.peakPhase.multiplier

        let plannedPeakDate = calendar.date(
            byAdding: .weekOfYear,
            value: -peakPhaseStartWeeksBefore,
            to: goal.targetDate
        ) ?? goal.targetDate

        // ── Stap 6: Projectiedatum per metric ──
        let projectedPeakDateTRIMP = projectDate(
            current:       currentWeeklyTRIMP,
            required:      requiredPeakTRIMP,
            effectiveRate: effectiveGrowthRate,
            from:          now,
            calendar:      calendar
        )

        let projectedPeakDateKm = projectDate(
            current:       currentWeeklyKm,
            required:      requiredPeakKm,
            effectiveRate: effectiveKmGrowthRate,
            from:          now,
            calendar:      calendar
        )

        // ── Stap 7: Bottleneck — de final datum is de LATEST van de twee ──
        let trimpAlreadyMet = currentWeeklyTRIMP >= requiredPeakTRIMP
        let kmAlreadyMet    = currentWeeklyKm    >= requiredPeakKm

        if trimpAlreadyMet && kmAlreadyMet {
            return GoalProjection(
                goal: goal, blueprintType: blueprintType,
                currentWeeklyTRIMP: currentWeeklyTRIMP,
                observedGrowthRate: observedTRIMPGrowth, effectiveGrowthRate: effectiveGrowthRate,
                requiredPeakTRIMP: requiredPeakTRIMP,
                currentWeeklyKm: currentWeeklyKm,
                kmObservedGrowthRate: observedKmGrowth, effectiveKmGrowthRate: effectiveKmGrowthRate,
                requiredPeakKm: requiredPeakKm,
                projectedPeakDateTRIMP: nil, projectedPeakDateKm: nil,
                bottleneck: .alreadyMet,
                plannedPeakDate: plannedPeakDate, projectedPeakDate: nil,
                weeksDelta: 0, status: .alreadyPeaking,
                hasCrossTrainingBonus: false
            )
        }

        // Beide unreachable (geen data of nul groei)?
        let trimpUnreachable = !trimpAlreadyMet && projectedPeakDateTRIMP == nil
        let kmUnreachable    = !kmAlreadyMet    && projectedPeakDateKm    == nil

        if trimpUnreachable && kmUnreachable {
            let weeksUntilRace = goal.targetDate.timeIntervalSince(now) / (7 * 86400)
            let earlyStatus: ProjectionStatus = weeksUntilRace > Double(gracePeriodWeeks)
                ? .catchUpNeeded : .unreachable
            return GoalProjection(
                goal: goal, blueprintType: blueprintType,
                currentWeeklyTRIMP: currentWeeklyTRIMP,
                observedGrowthRate: observedTRIMPGrowth, effectiveGrowthRate: effectiveGrowthRate,
                requiredPeakTRIMP: requiredPeakTRIMP,
                currentWeeklyKm: currentWeeklyKm,
                kmObservedGrowthRate: observedKmGrowth, effectiveKmGrowthRate: effectiveKmGrowthRate,
                requiredPeakKm: requiredPeakKm,
                projectedPeakDateTRIMP: nil, projectedPeakDateKm: nil,
                bottleneck: .both,
                plannedPeakDate: plannedPeakDate, projectedPeakDate: nil,
                weeksDelta: weeksUntilRace,
                status: earlyStatus,
                hasCrossTrainingBonus: hasCrossTrainingBonus
            )
        }

        // ── Stap 8: Bottleneck bepalen en finale datum berekenen ──
        // Gebruik een ver-toekomst sentinel voor metrices die al voldaan zijn
        let sentinel = Date.distantPast  // voor "al voldaan" gevallen
        let trimpDate = trimpAlreadyMet ? sentinel : (projectedPeakDateTRIMP ?? goal.targetDate.addingTimeInterval(86400))
        let kmDate    = kmAlreadyMet    ? sentinel : (projectedPeakDateKm    ?? goal.targetDate.addingTimeInterval(86400))

        let bottleneck: BottleneckMetric
        var rawProjectedDate: Date

        if kmUnreachable || (!trimpUnreachable && kmDate > trimpDate) {
            bottleneck = .km
            rawProjectedDate = kmDate
        } else if trimpUnreachable || trimpDate > kmDate {
            bottleneck = .trimp
            rawProjectedDate = trimpDate
        } else {
            bottleneck = .both
            rawProjectedDate = max(trimpDate, kmDate)
        }

        // ── Stap 9: Veiligheidscap ──
        // Als de wekelijkse km structureel onder de piek-eis zit (< 95%), kan de
        // projectie nooit eerder vallen dan de gepland peakdatum.
        // Dit voorkomt dat een TRIMP-voorsprong (door cross-training) een km-achterstand maskeert.
        let kmRatio = requiredPeakKm > 0 ? currentWeeklyKm / requiredPeakKm : 1.0
        if kmRatio < kmSafetyThreshold && rawProjectedDate < plannedPeakDate {
            rawProjectedDate = plannedPeakDate
        }

        // ── Stap 10: Status bepalen ──
        let weeksDelta = rawProjectedDate.timeIntervalSince(plannedPeakDate) / (7 * 86400)
        let weeksUntilRace = goal.targetDate.timeIntervalSince(now) / (7 * 86400)

        var status: ProjectionStatus
        if rawProjectedDate <= plannedPeakDate {
            status = .onTrack
        } else if rawProjectedDate <= goal.targetDate {
            status = .atRisk
        } else {
            status = .unreachable
        }

        // Grace Period: race nog > 12 weken weg → 'Onhaalbaar' niet tonen.
        // De atleet heeft genoeg tijd om bij te sturen; rood demotiveert onnodig.
        if status == .unreachable && weeksUntilRace > Double(gracePeriodWeeks) {
            status = .catchUpNeeded
        }

        return GoalProjection(
            goal: goal, blueprintType: blueprintType,
            currentWeeklyTRIMP: currentWeeklyTRIMP,
            observedGrowthRate: observedTRIMPGrowth, effectiveGrowthRate: effectiveGrowthRate,
            requiredPeakTRIMP: requiredPeakTRIMP,
            currentWeeklyKm: currentWeeklyKm,
            kmObservedGrowthRate: observedKmGrowth, effectiveKmGrowthRate: effectiveKmGrowthRate,
            requiredPeakKm: requiredPeakKm,
            projectedPeakDateTRIMP: projectedPeakDateTRIMP,
            projectedPeakDateKm: projectedPeakDateKm,
            bottleneck: bottleneck,
            plannedPeakDate: plannedPeakDate,
            projectedPeakDate: rawProjectedDate,
            weeksDelta: weeksDelta,
            status: status,
            hasCrossTrainingBonus: hasCrossTrainingBonus
        )
    }

    // MARK: - Coach context builder

    static func buildCoachContext(from projections: [GoalProjection]) -> String {
        guard !projections.isEmpty else { return "" }
        var lines = ["[PROGNOSE — TOEKOMSTPROJECTIE (Sprint 23.2):"]
        for projection in projections {
            lines.append(projection.coachContext)
            lines.append("")
        }
        lines.append("""
        Gedragsregel:
        - Bij bottleneck .km: wijs altijd expliciet op de sport-specifieke achterstand.
          Noem nooit de TRIMP-score als de km-achterstand de limiterende factor is.
        - Bij Cross-Training Bonus (hasCrossTrainingBonus = true): toon empathie voor de blessure
          en benadruk dat het SNELLER beter kan gaan omdat de aerobe basis sterk is.
        - Bij 'Inhaalslag nodig' (.catchUpNeeded): NOOIT alarmerend. Wees constructief —
          er is genoeg tijd. Stel een concreet opbouwplan voor.
        - Bij 'Risico' of 'Onhaalbaar': stel proactief een bijsturingsplan voor.
        - Verbind de prognose altijd aan de huidig lopende trainingsfase.]
        """)
        return lines.joined(separator: "\n")
    }

    // MARK: - Private helper

    /// Berekent via de logaritmische projectieformule hoeveel weken er nodig zijn
    /// om van `current` naar `required` te groeien bij `effectiveRate` per week.
    /// Geeft `nil` terug als de berekening niet mogelijk of negatief is.
    private static func projectDate(
        current: Double,
        required: Double,
        effectiveRate: Double,
        from now: Date,
        calendar: Calendar
    ) -> Date? {
        // Al voldaan
        if current >= required { return nil }
        // Geen positieve groei → onbereikbaar
        guard current > 0, effectiveRate > 0 else { return nil }

        // n = log(required / current) / log(1 + r)
        let weeksNeeded = log(required / current) / log(1.0 + effectiveRate)
        guard weeksNeeded.isFinite, weeksNeeded > 0 else { return nil }

        return calendar.date(byAdding: .day, value: Int((weeksNeeded * 7).rounded()), to: now)
    }
}
