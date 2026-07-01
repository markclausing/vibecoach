import Foundation

// MARK: - Epic 23 Sprint 2 (Fix): Future Projection Engine — Bottleneck-based projection

// ──────────────────────────────────────────────────────────────────────────────
// BUGFIX RATIONALE
// ──────────────────────────────────────────────────────────────────────────────
// Original problem: the algorithm computed the projection date purely based on
// TRIMP (all activities), without distinguishing sport types. A marathon runner
// with an injury who temporarily cycles accumulated cycling TRIMP, which made the
// marathon projection optimistic — while the running km still lagged far behind.
//
// The fix consists of three layers:
//   1. SPORT ISOLATION: the km trend is computed exclusively on activities of the
//      target sport type (running → .running, cycling → .cycling).
//   2. BOTTLENECK RULE: projectedPeakDate = max(TRIMP date, km date).
//      The slowest-growing or furthest-behind metric determines the date.
//   3. SAFETY CHECK: if the cumulative km deficit is > 5% of the target, the
//      projection can never fall earlier than the plannedPeakDate.
// ──────────────────────────────────────────────────────────────────────────────

/// Which metric determines the projection date (for UI explanation and coach context).
enum BottleneckMetric {
    case trimp       // TRIMP is the limiting factor (km is ahead)
    case km          // Km is the bottleneck (sport-specific volume lags)
    case both        // Both unreachable or both equal
    case alreadyMet  // Athlete already meets both requirements
}

/// Projection status — whether the athlete reaches the Peak Phase before race day.
enum ProjectionStatus {
    /// The current weekly TRIMP and km already meet the Peak Phase requirement.
    case alreadyPeaking
    /// Forecast: the athlete reaches the Peak Phase before the planned peak date.
    case onTrack
    /// Forecast: the athlete reaches the Peak Phase only after the planned peak date,
    /// but still before race day — risk.
    case atRisk
    /// Mathematically unreachable at the current growth, but race > 12 weeks away —
    /// enough time for a targeted catch-up. Orange, not red.
    case catchUpNeeded
    /// Mathematically unreachable: even with the maximum growth cap the Peak Phase
    /// isn't reachable before race day (race < 12 weeks away), or the current volume
    /// is zero/negative.
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

/// The full future forecast for one goal — bottleneck-based.
struct GoalProjection {
    let goal: FitnessGoal
    let blueprintType: GoalBlueprintType

    // MARK: - TRIMP metrics (all activities — sport-independent)

    let currentWeeklyTRIMP: Double
    let observedGrowthRate: Double
    let effectiveGrowthRate: Double
    let requiredPeakTRIMP: Double

    // MARK: - KM metrics (STRICTLY sport-filtered)
    // Marathon/half marathon → only .running activities
    // Cycling tour           → only .cycling activities

    let currentWeeklyKm: Double
    let kmObservedGrowthRate: Double
    let effectiveKmGrowthRate: Double
    let requiredPeakKm: Double

    // MARK: - Projection results per metric

    /// Date on which TRIMP reaches the peak requirement (nil if already met or unreachable).
    let projectedPeakDateTRIMP: Date?

    /// Date on which km reaches the peak requirement (nil if already met or unreachable).
    let projectedPeakDateKm: Date?

    // MARK: - Bottleneck: the determinant of the final projection date

    /// The metric that determines the end date.
    let bottleneck: BottleneckMetric

    // MARK: - Final projection results (UI + coach)

    let plannedPeakDate: Date
    let projectedPeakDate: Date?
    let weeksDelta: Double
    let status: ProjectionStatus

    /// True if the Cross-Training Bonus was active: TRIMP ≥ 90% of the base week
    /// target, which raised the km growth cap from 10% to 17%.
    let hasCrossTrainingBonus: Bool

    // MARK: - Coach context

    var coachContext: String {
        let df = AppDateFormatters.prompt("d MMM")

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
                + (hasCrossTrainingBonus ? " — Cross-Training Bonus actief" : "") + ")"
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

    /// Maximum allowed weekly growth (the sports-science 10% rule).
    static let maxWeeklyGrowthRate: Double = 0.10

    /// Raised growth cap under the Cross-Training Bonus: the athlete has a strong
    /// aerobic base (TRIMP ≥ 90% of the base week target) but lags on sport-specific
    /// km. Sports-science justified: a well aerobically trained athlete can build up faster.
    static let maxWeeklyGrowthRateCrossTraining: Double = 0.17

    /// Minimum TRIMP ratio relative to the base week target to activate the Cross-Training Bonus.
    static let trimpOnScheduleThreshold: Double = 0.90

    /// Weeks until race day below which 'Unreachable' (red) may be shown.
    /// Above that the app shows 'Catch-up needed' (orange) — there is still enough time.
    static let gracePeriodWeeks: Int = 12

    /// Weeks before race day that the Peak Phase ideally starts.
    static let peakPhaseStartWeeksBefore: Int = 4

    /// Km deficit relative to target at which the safety cap activates.
    /// 5% below the peak requirement = projection never earlier than plannedPeakDate.
    static let kmSafetyThreshold: Double = 0.95

    // MARK: - Public API

    static func calculateProjections(
        for goals: [FitnessGoal],
        activities: [ActivityRecord]
    ) -> [GoalProjection] {
        goals
            .filter { !$0.isCompleted && Date() < $0.targetDate }
            .compactMap { calculateProjection(for: $0, activities: activities) }
    }

    // MARK: - Core algorithm

    static func calculateProjection(
        for goal: FitnessGoal,
        activities: [ActivityRecord]
    ) -> GoalProjection? {
        guard let blueprintType = BlueprintChecker.detectBlueprintType(for: goal) else { return nil }
        let blueprint = BlueprintChecker.blueprint(for: blueprintType)
        let calendar  = Calendar.current
        let now       = Date()

        // ── Step 1: Determine the target sport (strict — no cross-sport compensation) ──
        let targetSport: SportCategory
        switch blueprintType {
        case .marathon, .halfMarathon: targetSport = .running
        case .cyclingTour:             targetSport = .cycling
        }

        // ── Step 2: Weekly sliding windows (past 4 weeks) ──
        // week[0] = most recent (0–7 days ago)
        // week[3] = oldest (21–28 days ago)
        let weeklyTRIMP: [Double] = (0..<4).map { i in
            let end   = calendar.date(byAdding: .day, value: -(i * 7), to: now) ?? now
            let start = calendar.date(byAdding: .day, value: -((i + 1) * 7), to: now) ?? now
            return activities
                .filter { $0.startDate >= start && $0.startDate < end }
                .compactMap { $0.trimp }
                .reduce(0, +)
        }

        // Km: ONLY the target sport — cycling km don't count toward a running goal
        let weeklyKm: [Double] = (0..<4).map { i in
            let end   = calendar.date(byAdding: .day, value: -(i * 7), to: now) ?? now
            let start = calendar.date(byAdding: .day, value: -((i + 1) * 7), to: now) ?? now
            let sportActivities = activities.filter {
                $0.startDate >= start && $0.startDate < end && $0.sportCategory == targetSport
            }
            return sportActivities.map { $0.distance / 1000.0 }.reduce(0, +)
        }

        // ── Step 3: Current volume (average of the last 2 weeks) ──
        let currentWeeklyTRIMP = (weeklyTRIMP[0] + weeklyTRIMP[1]) / 2.0
        let currentWeeklyKm    = (weeklyKm[0]    + weeklyKm[1])    / 2.0

        // ── Step 3b: Cross-Training Bonus ──
        // If the overall TRIMP (including cross-training) is on schedule but the
        // sport-specific km lag (e.g. a calf injury), the athlete gets a higher km
        // growth cap. A good aerobic base accelerates recovery.
        let hasCrossTrainingBonus = currentWeeklyTRIMP >= trimpOnScheduleThreshold * blueprint.weeklyTrimpTarget
        let kmGrowthCap = hasCrossTrainingBonus ? maxWeeklyGrowthRateCrossTraining : maxWeeklyGrowthRate

        // ── Step 4: Growth rate per metric ──
        // Compare the average of week 0–1 with the average of week 2–3, divided by 2 weeks.
        let olderTRIMP = (weeklyTRIMP[2] + weeklyTRIMP[3]) / 2.0
        let observedTRIMPGrowth: Double = olderTRIMP > 5
            ? (currentWeeklyTRIMP - olderTRIMP) / olderTRIMP / 2.0
            : 0.0

        let olderKm = (weeklyKm[2] + weeklyKm[3]) / 2.0
        let observedKmGrowth: Double = olderKm > 0.5
            ? (currentWeeklyKm - olderKm) / olderKm / 2.0
            : 0.0

        let effectiveGrowthRate   = min(observedTRIMPGrowth, maxWeeklyGrowthRate)
        let effectiveKmGrowthRate = min(observedKmGrowth, kmGrowthCap)

        // ── Step 5: Peak requirements (blueprint × Peak Phase multiplier 1.30) ──
        // For tours (.singleDayTour / .multiDayStage) the peak requirement is lower than for a race:
        // a fondo or stage ride requires endurance over multiple days, not an absolute weekly peak volume.
        let peakKmFormatMultiplier: Double = {
            switch goal.resolvedFormat {
            case .singleDayRace:  return 1.00
            case .singleDayTour:  return 0.75
            case .multiDayStage:  return 0.65
            }
        }()
        let requiredPeakTRIMP = blueprint.weeklyTrimpTarget * TrainingPhase.peakPhase.multiplier
        let requiredPeakKm    = blueprint.weeklyKmTarget    * TrainingPhase.peakPhase.multiplier * peakKmFormatMultiplier

        let plannedPeakDate = calendar.date(
            byAdding: .weekOfYear,
            value: -peakPhaseStartWeeksBefore,
            to: goal.targetDate
        ) ?? goal.targetDate

        // ── Step 6: Projection date per metric ──
        let projectedPeakDateTRIMP = projectDate(
            current: currentWeeklyTRIMP,
            required: requiredPeakTRIMP,
            effectiveRate: effectiveGrowthRate,
            from: now,
            calendar: calendar
        )

        let projectedPeakDateKm = projectDate(
            current: currentWeeklyKm,
            required: requiredPeakKm,
            effectiveRate: effectiveKmGrowthRate,
            from: now,
            calendar: calendar
        )

        // ── Step 7: Bottleneck — the final date is the LATEST of the two ──
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

        // Both unreachable (no data or zero growth)?
        let trimpUnreachable = !trimpAlreadyMet && projectedPeakDateTRIMP == nil
        let kmUnreachable    = !kmAlreadyMet    && projectedPeakDateKm    == nil

        if trimpUnreachable && kmUnreachable {
            let weeksUntilRace = goal.weeksRemaining(from: now)
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

        // ── Step 8: Determine the bottleneck and compute the final date ──
        // Use a far-future sentinel for metrics that are already met
        let sentinel = Date.distantPast  // for "already met" cases
        let dayAfterTarget = Calendar.current.date(byAdding: .day, value: 1, to: goal.targetDate) ?? goal.targetDate
        let trimpDate = trimpAlreadyMet ? sentinel : (projectedPeakDateTRIMP ?? dayAfterTarget)
        let kmDate    = kmAlreadyMet    ? sentinel : (projectedPeakDateKm    ?? dayAfterTarget)

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

        // ── Step 9: Safety cap ──
        // If the weekly km is structurally below the peak requirement (< 95%), the
        // projection can never fall earlier than the planned peak date.
        // This prevents a TRIMP lead (from cross-training) masking a km deficit.
        let kmRatio = requiredPeakKm > 0 ? currentWeeklyKm / requiredPeakKm : 1.0
        if kmRatio < kmSafetyThreshold && rawProjectedDate < plannedPeakDate {
            rawProjectedDate = plannedPeakDate
        }

        // ── Step 10: Determine status ──
        let weeksDelta = Calendar.current.fractionalWeeks(from: plannedPeakDate, to: rawProjectedDate)
        let weeksUntilRace = goal.weeksRemaining(from: now)

        var status: ProjectionStatus
        if rawProjectedDate <= plannedPeakDate {
            status = .onTrack
        } else if rawProjectedDate <= goal.targetDate {
            status = .atRisk
        } else {
            status = .unreachable
        }

        // Grace Period: race still > 12 weeks away → don't show 'Unreachable'.
        // The athlete has enough time to adjust; red demotivates unnecessarily.
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

    /// Computes, via the logarithmic projection formula, how many weeks are needed
    /// to grow from `current` to `required` at `effectiveRate` per week.
    /// Returns `nil` if the calculation isn't possible or is negative.
    private static func projectDate(
        current: Double,
        required: Double,
        effectiveRate: Double,
        from now: Date,
        calendar: Calendar
    ) -> Date? {
        // Already met
        if current >= required { return nil }
        // No positive growth → unreachable
        guard current > 0, effectiveRate > 0 else { return nil }

        // n = log(required / current) / log(1 + r)
        let weeksNeeded = log(required / current) / log(1.0 + effectiveRate)
        guard weeksNeeded.isFinite, weeksNeeded > 0 else { return nil }

        return calendar.date(byAdding: .day, value: Int((weeksNeeded * 7).rounded()), to: now)
    }
}
