import XCTest
@testable import AIFitnessCoach

/// Epic #36 sub-task 36.1 — vervangt de eerdere smoke-test met volledige
/// dekking voor `TRIMPTranslator`, `BlueprintGap` (alle computed properties)
/// en `ProgressService.analyzeGaps` (integratie). De berekeningen hier zijn
/// het hart van de gap-analyse uit Epic 23, dus regressies zijn duur —
/// vandaar dat we ook de string-output vastpinnen.
final class ProgressServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeGoal(
        title: String,
        weeksUntil: Double,
        createdAtWeeksAgo: Double = 12,
        sportCategory: SportCategory? = nil,
        isCompleted: Bool = false
    ) -> FitnessGoal {
        let now = Date()
        let target = now.addingTimeInterval(weeksUntil * 7 * 86400)
        let createdAt = now.addingTimeInterval(-createdAtWeeksAgo * 7 * 86400)
        return FitnessGoal(
            title: title,
            targetDate: target,
            createdAt: createdAt,
            isCompleted: isCompleted,
            sportCategory: sportCategory
        )
    }

    private func makeActivity(
        sport: SportCategory,
        startDate: Date,
        distanceMeters: Double = 0,
        trimp: Double = 0
    ) -> ActivityRecord {
        ActivityRecord(
            id: UUID().uuidString,
            name: "Activity",
            distance: distanceMeters,
            movingTime: 3600,
            averageHeartrate: 150,
            sportCategory: sport,
            startDate: startDate,
            trimp: trimp
        )
    }

    /// Volledig samengestelde `BlueprintGap` met overschrijfbare velden zodat
    /// elke test alleen de relevante invoer hoeft te muteren.
    private func makeGap(
        blueprintType: GoalBlueprintType = .marathon,
        currentPhase: TrainingPhase = .buildPhase,
        phaseWeekNumber: Int = 1,
        phaseTotalWeeks: Int = 8,
        requiredTRIMP: Double = 100,
        actualTRIMP: Double = 100,
        totalPhaseTRIMP: Double = 800,
        requiredKm: Double = 50,
        actualKm: Double = 50,
        totalPhaseKm: Double = 400,
        weeksUntilTarget: Double = 8
    ) -> BlueprintGap {
        let goal = makeGoal(title: "Marathon Amsterdam", weeksUntil: weeksUntilTarget)
        return BlueprintGap(
            goal: goal,
            blueprintType: blueprintType,
            blueprint: BlueprintChecker.blueprint(for: blueprintType),
            currentPhase: currentPhase,
            phaseStartDate: Date().addingTimeInterval(-Double(phaseWeekNumber) * 7 * 86400),
            phaseEndDate: Date().addingTimeInterval(Double(phaseTotalWeeks - phaseWeekNumber) * 7 * 86400),
            phaseWeekNumber: phaseWeekNumber,
            phaseTotalWeeks: phaseTotalWeeks,
            requiredTRIMPToDate: requiredTRIMP,
            actualTRIMPToDate: actualTRIMP,
            totalPhaseTRIMPTarget: totalPhaseTRIMP,
            requiredKmToDate: requiredKm,
            actualKmToDate: actualKm,
            totalPhaseKmTarget: totalPhaseKm
        )
    }

    // MARK: - TRIMPTranslator

    func testTRIMPTranslator_Translate_MarathonGivesRunningLabels() {
        let result = TRIMPTranslator.translate(20, for: .marathon)
        XCTAssertTrue(result.contains("duurloop (Z2)"),
                      "Marathon-vertaling moet de Z2 duurloop-label bevatten — kreeg: \(result)")
        XCTAssertTrue(result.contains("intervaltraining (Z4)"),
                      "Marathon-vertaling moet de Z4 interval-label bevatten — kreeg: \(result)")
    }

    func testTRIMPTranslator_Translate_CyclingTourGivesRideLabels() {
        let result = TRIMPTranslator.translate(20, for: .cyclingTour)
        XCTAssertTrue(result.contains("rustige rit"))
        XCTAssertTrue(result.contains("tempo-rit"))
    }

    func testTRIMPTranslator_Translate_HalfMarathonUsesRunningLabels() {
        let result = TRIMPTranslator.translate(20, for: .halfMarathon)
        XCTAssertTrue(result.contains("duurloop (Z2)"))
        XCTAssertTrue(result.contains("intervaltraining (Z4)"))
    }

    /// Bij kleine TRIMP-waarden (1.0) wordt zone2Min == zone4Min == 1; de
    /// translator combineert dan tot één compact bericht zonder "of".
    func testTRIMPTranslator_Translate_VerySmallTRIMP_ReturnsCombinedSingleLabel() {
        let result = TRIMPTranslator.translate(1.0, for: .marathon)
        XCTAssertFalse(result.contains(" of "),
                       "Bij gelijke zone2/zone4-minuten verwachten we één gecombineerde uitvoer.")
        XCTAssertTrue(result.contains("+1 min"))
    }

    /// Z2 = 2 TRIMP/min → 20 TRIMP = 10 min Z2.
    /// Z4 = 4 TRIMP/min → 20 TRIMP = 5 min Z4.
    func testTRIMPTranslator_Translate_RoundsCorrectly() {
        let result = TRIMPTranslator.translate(20, for: .marathon)
        XCTAssertTrue(result.contains("+10 min duurloop (Z2)"))
        XCTAssertTrue(result.contains("+5 min intervaltraining (Z4)"))
    }

    func testTRIMPTranslator_BannerText_FormatsTrimpAsRoundedInt() {
        let result = TRIMPTranslator.bannerText(8.4, for: .marathon)
        XCTAssertTrue(result.hasPrefix("Circa 8 extra TRIMP/week"),
                      "Verwacht 'Circa 8' (afgerond), kreeg: \(result)")
        XCTAssertTrue(result.hasSuffix("."), "BannerText moet met een punt eindigen.")
    }

    func testTRIMPTranslator_CoachHint_FormatsCompactly() {
        let result = TRIMPTranslator.coachHint(8.4, for: .cyclingTour)
        XCTAssertTrue(result.hasPrefix("8 TRIMP ≈"))
        XCTAssertTrue(result.contains("rustige rit"))
    }

    // MARK: - GoalBlueprint.weeklyKmTarget

    func testWeeklyKmTarget_PerBlueprintType() {
        XCTAssertEqual(BlueprintChecker.marathonBlueprint.weeklyKmTarget, 55.0)
        XCTAssertEqual(BlueprintChecker.halfMarathonBlueprint.weeklyKmTarget, 40.0)
        XCTAssertEqual(BlueprintChecker.cyclingTourBlueprint.weeklyKmTarget, 180.0)
    }

    // MARK: - BlueprintGap — TRIMP/Km gap math

    func testBlueprintGap_TrimpGap_PositiveWhenBehind() {
        let gap = makeGap(requiredTRIMP: 200, actualTRIMP: 150)
        XCTAssertEqual(gap.trimpGap, 50, accuracy: 0.001)
    }

    func testBlueprintGap_TrimpGap_NegativeWhenAhead() {
        let gap = makeGap(requiredTRIMP: 150, actualTRIMP: 200)
        XCTAssertEqual(gap.trimpGap, -50, accuracy: 0.001)
    }

    func testBlueprintGap_KmGap_BothDirections() {
        XCTAssertEqual(makeGap(requiredKm: 100, actualKm: 80).kmGap, 20, accuracy: 0.001)
        XCTAssertEqual(makeGap(requiredKm: 80, actualKm: 100).kmGap, -20, accuracy: 0.001)
    }

    // MARK: - BlueprintGap — Progress percentages

    func testBlueprintGap_TrimpProgressPct_ClampedAtOne() {
        let gap = makeGap(actualTRIMP: 1000, totalPhaseTRIMP: 800)
        XCTAssertEqual(gap.trimpProgressPct, 1.0, accuracy: 0.001,
                       "Voortgang moet capped zijn op 100% bij overshooting.")
    }

    func testBlueprintGap_TrimpProgressPct_SafeWhenTotalZero() {
        let gap = makeGap(totalPhaseTRIMP: 0)
        XCTAssertEqual(gap.trimpProgressPct, 0,
                       "Bij totaal=0 mag er geen division-by-zero crash zijn.")
        XCTAssertEqual(gap.trimpReferencePct, 0)
    }

    func testBlueprintGap_KmProgressPct_SafeWhenTotalZero() {
        let gap = makeGap(totalPhaseKm: 0)
        XCTAssertEqual(gap.kmProgressPct, 0)
        XCTAssertEqual(gap.kmReferencePct, 0)
    }

    func testBlueprintGap_ReferencePct_TracksRequired() {
        let gap = makeGap(requiredTRIMP: 400, totalPhaseTRIMP: 800)
        XCTAssertEqual(gap.trimpReferencePct, 0.5, accuracy: 0.001)
    }

    // MARK: - BlueprintGap — Threshold logic (10% margin)

    func testBlueprintGap_IsBehindOnTRIMP_AtTenPercentThreshold() {
        // Gap precies op de drempel (10% van required) telt NIET als achter
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 90)
        XCTAssertFalse(gap.isBehindOnTRIMP,
                       "Een gap van 10 op required 100 ligt op de 10%-drempel — exclusief.")
    }

    func testBlueprintGap_IsBehindOnTRIMP_TrueWhenJustOverThreshold() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 89)
        XCTAssertTrue(gap.isBehindOnTRIMP,
                      "Een gap van 11 op required 100 (>10%) hoort wél als achter te tellen.")
    }

    func testBlueprintGap_IsBehindOnTRIMP_FalseWhenAhead() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 200)
        XCTAssertFalse(gap.isBehindOnTRIMP)
    }

    func testBlueprintGap_IsBehindOnKm_TenPercentRule() {
        XCTAssertFalse(makeGap(requiredKm: 100, actualKm: 90).isBehindOnKm)
        XCTAssertTrue(makeGap(requiredKm: 100, actualKm: 89).isBehindOnKm)
    }

    // MARK: - BlueprintGap — extraTRIMPPerWeek + catchUpHint

    func testBlueprintGap_ExtraTRIMPPerWeek_ZeroWhenNotBehind() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 100)
        XCTAssertEqual(gap.extraTRIMPPerWeek, 0)
    }

    func testBlueprintGap_ExtraTRIMPPerWeek_DivIdesGapOverWeeksRemaining() {
        // 50 TRIMP achter, 4 weken resterend → 12.5/week
        let gap = makeGap(
            requiredTRIMP: 200,
            actualTRIMP: 150,
            weeksUntilTarget: 4
        )
        XCTAssertEqual(gap.extraTRIMPPerWeek, 12.5, accuracy: 0.5)
    }

    func testBlueprintGap_CatchUpHint_NilWhenNotBehind() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 100)
        XCTAssertNil(gap.catchUpHint)
    }

    func testBlueprintGap_CatchUpHint_NilWhenBelowHalfTRIMPPerWeek() {
        // 11 TRIMP achter, 100 weken resterend → ≈ 0.11/week (<0.5 drempel)
        let gap = makeGap(
            requiredTRIMP: 100,
            actualTRIMP: 89,
            weeksUntilTarget: 100
        )
        XCTAssertNil(gap.catchUpHint,
                     "Bij <0.5 TRIMP/week extra is een hint te kleinschalig om te tonen.")
    }

    func testBlueprintGap_CatchUpHint_NonNilWhenMeaningfullyBehind() {
        let gap = makeGap(
            requiredTRIMP: 200,
            actualTRIMP: 100,
            weeksUntilTarget: 4
        )
        let hint = gap.catchUpHint
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint!.contains("extra TRIMP/week"))
    }

    // MARK: - BlueprintGap — Status strings

    func testBlueprintGap_TrimpStatusLine_BehindBranch() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 80)
        XCTAssertTrue(gap.trimpStatusLine.contains("achter"),
                      "Bij trimpGap > 5 verwachten we een 'achter'-formulering.")
    }

    func testBlueprintGap_TrimpStatusLine_AheadBranch() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 130)
        XCTAssertTrue(gap.trimpStatusLine.contains("voor"),
                      "Bij trimpGap < -5 verwachten we 'voor in deze fase'.")
    }

    func testBlueprintGap_TrimpStatusLine_OnTrackBranch() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 102)
        XCTAssertEqual(gap.trimpStatusLine, "Je zit precies op het ideale pad.")
    }

    func testBlueprintGap_KmStatusLine_NilWhenTotalZero() {
        let gap = makeGap(totalPhaseKm: 0)
        XCTAssertNil(gap.kmStatusLine)
    }

    func testBlueprintGap_KmStatusLine_BehindBranch() {
        let gap = makeGap(requiredKm: 50, actualKm: 30)
        XCTAssertTrue(gap.kmStatusLine?.contains("achter") ?? false)
    }

    func testBlueprintGap_KmStatusLine_AheadBranch() {
        let gap = makeGap(requiredKm: 50, actualKm: 60)
        XCTAssertTrue(gap.kmStatusLine?.contains("méér") ?? false)
    }

    // MARK: - BlueprintGap — Phase label

    func testBlueprintGap_PhaseProgressLabel_FormatsWeekAndPhase() {
        let gap = makeGap(currentPhase: .buildPhase, phaseWeekNumber: 3, phaseTotalWeeks: 8)
        XCTAssertEqual(gap.phaseProgressLabel, "Build Phase (Week 3/8)")
    }

    // MARK: - BlueprintGap — coachContext

    func testBlueprintGap_CoachContext_IncludesGoalAndPhaseInfo() {
        let gap = makeGap()
        let context = gap.coachContext
        XCTAssertTrue(context.contains("Doel:"))
        XCTAssertTrue(context.contains("Blueprint:"))
        XCTAssertTrue(context.contains("Fase TRIMP-voortgang:"))
    }

    func testBlueprintGap_CoachContext_AddsVolumeBijsturingWhenBehind() {
        let gap = makeGap(
            requiredTRIMP: 200,
            actualTRIMP: 100,
            weeksUntilTarget: 4
        )
        XCTAssertTrue(gap.coachContext.contains("VOLUME-BIJSTURING"),
                      "Bij significante achterstand moet de coach-context een volume-instructie bevatten.")
    }

    func testBlueprintGap_CoachContext_AddsKmBijsturingWhenBehindOnKm() {
        let gap = makeGap(
            requiredKm: 100,
            actualKm: 50,
            totalPhaseKm: 400
        )
        XCTAssertTrue(gap.coachContext.contains("KM-BIJSTURING"))
    }

    func testBlueprintGap_CoachContext_OmitsBijsturingWhenOnTrack() {
        let gap = makeGap()
        XCTAssertFalse(gap.coachContext.contains("VOLUME-BIJSTURING"))
        XCTAssertFalse(gap.coachContext.contains("KM-BIJSTURING"))
    }

    // MARK: - ProgressService.analyzeGaps — integratie

    func testAnalyzeGaps_SkipsCompletedGoals() {
        let goal = makeGoal(
            title: "Marathon Berlin",
            weeksUntil: 8,
            sportCategory: .running,
            isCompleted: true
        )
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testAnalyzeGaps_SkipsExpiredGoals() {
        // Doeldatum in het verleden → moet eruit gefilterd worden
        let goal = makeGoal(title: "Marathon Past", weeksUntil: -2, sportCategory: .running)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testAnalyzeGaps_SkipsGoalsWithoutDetectableBlueprint() {
        // Geen herkenbare titel + geen sportCategory → geen blueprint detectable
        let goal = makeGoal(title: "Random doel zonder match", weeksUntil: 8)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testAnalyzeGaps_SortedByTrimpGapDescending() {
        // Twee marathon-doelen met verschillende achterstand
        let aheadGoal = makeGoal(title: "Marathon Amsterdam", weeksUntil: 8, sportCategory: .running)
        let behindGoal = makeGoal(title: "Halve Marathon Utrecht", weeksUntil: 8, sportCategory: .running)

        // De huidige fase-context maakt het lastig om exacte gaps te garanderen,
        // maar we kunnen wel verifiëren dat het resultaat gesorteerd is.
        let result = ProgressService.analyzeGaps(for: [aheadGoal, behindGoal], activities: [])
        if result.count >= 2 {
            for i in 0..<(result.count - 1) {
                XCTAssertGreaterThanOrEqual(
                    result[i].trimpGap,
                    result[i + 1].trimpGap,
                    "Resultaat moet aflopend gesorteerd zijn op trimpGap."
                )
            }
        }
    }

    func testAnalyzeGaps_AccumulatesActualTRIMPInPhaseWindow() {
        // 8 weken vooruit = buildPhase (4–12 weken). Phase-window is 8 weken vóór nu.
        let goal = makeGoal(
            title: "Marathon Amsterdam",
            weeksUntil: 8,
            createdAtWeeksAgo: 16,
            sportCategory: .running
        )
        let now = Date()
        let inPhase = makeActivity(sport: .running, startDate: now.addingTimeInterval(-3 * 86400), trimp: 50)
        let outOfPhase = makeActivity(sport: .running, startDate: now.addingTimeInterval(-200 * 86400), trimp: 999)

        let result = ProgressService.analyzeGaps(for: [goal], activities: [inPhase, outOfPhase])
        XCTAssertEqual(result.count, 1)
        let gap = result[0]
        XCTAssertEqual(gap.actualTRIMPToDate, 50, accuracy: 0.01,
                       "Alleen activiteiten binnen de fase-window mogen meetellen.")
    }

    func testAnalyzeGaps_OnlyCountsKmFromMatchingSportCategory() {
        // Marathon-doel: alleen running-km tellen, fietsritten worden uitgesloten.
        let goal = makeGoal(
            title: "Marathon Amsterdam",
            weeksUntil: 8,
            createdAtWeeksAgo: 16,
            sportCategory: .running
        )
        let now = Date()
        let runActivity = makeActivity(
            sport: .running,
            startDate: now.addingTimeInterval(-3 * 86400),
            distanceMeters: 10_000,  // 10 km
            trimp: 30
        )
        let cyclingActivity = makeActivity(
            sport: .cycling,
            startDate: now.addingTimeInterval(-2 * 86400),
            distanceMeters: 50_000,  // 50 km — moet niet meetellen
            trimp: 40
        )

        let result = ProgressService.analyzeGaps(for: [goal], activities: [runActivity, cyclingActivity])
        XCTAssertEqual(result.count, 1)
        let gap = result[0]
        XCTAssertEqual(gap.actualKmToDate, 10, accuracy: 0.01,
                       "Voor een marathon-doel mogen fietskm's NIET meetellen in actualKmToDate.")
        XCTAssertEqual(gap.actualTRIMPToDate, 70, accuracy: 0.01,
                       "TRIMP wordt wél van álle sporten in de fase opgeteld (cardiosystem-belasting).")
    }
}
