import XCTest
@testable import AIFitnessCoach

/// Unit tests voor ProgressService (Epic 23, Sprint 1).
///
/// Dekt drie onderdelen:
///   1. `TRIMPTranslator`         — pure statische functies zonder side-effects
///   2. `BlueprintGap`            — berekende properties van het gap-struct
///   3. `ProgressService`         — filtering, aggregatie en sortering van gaps
///   4. `GoalBlueprint.weeklyKmTarget` — Sprint 23 extension op GoalBlueprint
///
/// FitnessGoal en ActivityRecord zijn @Model klassen maar kunnen
/// zonder SwiftData-context worden aangemaakt voor property-reads (BlueprintCheckerTests-patroon).
final class ProgressServiceTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - Hulpfuncties

    /// Maakt een FitnessGoal aan met een targetDate N weken in de toekomst.
    private func makeGoal(
        title: String,
        sport: SportCategory? = nil,
        weeksAhead: Int = 20,
        weeksAgoCreated: Int = 0,
        isCompleted: Bool = false
    ) -> FitnessGoal {
        let target  = calendar.date(byAdding: .weekOfYear, value: weeksAhead,    to: Date())!
        let created = calendar.date(byAdding: .weekOfYear, value: -weeksAgoCreated, to: Date())!
        return FitnessGoal(
            title: title,
            targetDate: target,
            createdAt: created,
            isCompleted: isCompleted,
            sportCategory: sport
        )
    }

    /// Maakt een ActivityRecord aan met TRIMP, afstand en een startdatum N weken geleden.
    private func makeActivity(
        sport: SportCategory,
        distanceMeters: Double,
        trimp: Double,
        weeksAgo: Int = 1
    ) -> ActivityRecord {
        let date = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date())!
        return ActivityRecord(
            id: UUID().uuidString,
            name: "Test Training",
            distance: distanceMeters,
            movingTime: 3600,
            averageHeartrate: 150,
            sportCategory: sport,
            startDate: date,
            trimp: trimp
        )
    }

    /// Bouwt een BlueprintGap met volledig gecontroleerde waarden voor property-tests.
    private func makeGap(
        goalTitle: String = "Marathon Rotterdam",
        weeksAhead: Int = 20,
        phase: TrainingPhase = .buildPhase,
        requiredTRIMP: Double = 100,
        actualTRIMP: Double = 80,
        totalPhaseTRIMP: Double = 500,
        requiredKm: Double = 50,
        actualKm: Double = 40,
        totalPhaseKm: Double = 250,
        blueprintType: GoalBlueprintType = .marathon
    ) -> BlueprintGap {
        let targetDate = calendar.date(byAdding: .weekOfYear, value: weeksAhead, to: Date())!
        let goal = FitnessGoal(title: goalTitle, targetDate: targetDate)
        let blueprint = BlueprintChecker.blueprint(for: blueprintType)
        let phaseStart = calendar.date(byAdding: .weekOfYear, value: -4, to: Date())!
        let phaseEnd   = calendar.date(byAdding: .weekOfYear, value:  4, to: Date())!

        return BlueprintGap(
            goal: goal,
            blueprintType: blueprintType,
            blueprint: blueprint,
            currentPhase: phase,
            phaseStartDate: phaseStart,
            phaseEndDate: phaseEnd,
            phaseWeekNumber: 3,
            phaseTotalWeeks: 8,
            requiredTRIMPToDate: requiredTRIMP,
            actualTRIMPToDate: actualTRIMP,
            totalPhaseTRIMPTarget: totalPhaseTRIMP,
            requiredKmToDate: requiredKm,
            actualKmToDate: actualKm,
            totalPhaseKmTarget: totalPhaseKm
        )
    }

    // MARK: - TRIMPTranslator: translate

    func testTranslate_CyclingTour_8Trimp_ShowsBothZones() {
        let result = TRIMPTranslator.translate(8.0, for: .cyclingTour)
        XCTAssertEqual(result, "+4 min rustige rit of +2 min tempo-rit")
    }

    func testTranslate_Marathon_4Trimp_ShowsBothZones() {
        let result = TRIMPTranslator.translate(4.0, for: .marathon)
        XCTAssertEqual(result, "+2 min duurloop (Z2) of +1 min intervaltraining (Z4)")
    }

    func testTranslate_HalfMarathon_UsesRunningLabels() {
        let result = TRIMPTranslator.translate(4.0, for: .halfMarathon)
        XCTAssertTrue(result.contains("duurloop"))
        XCTAssertTrue(result.contains("intervaltraining"))
    }

    func testTranslate_SmallTrimp_BothZonesEqual_ShowsOnlyZone2() {
        let result = TRIMPTranslator.translate(2.0, for: .cyclingTour)
        XCTAssertEqual(result, "+1 min rustige rit")
        XCTAssertFalse(result.contains("of"))
    }

    // MARK: - TRIMPTranslator: bannerText & coachHint

    func testBannerText_ContainsTrimpValueAndHint() {
        let text = TRIMPTranslator.bannerText(8.0, for: .cyclingTour)
        XCTAssertTrue(text.contains("8"))
        XCTAssertTrue(text.contains("rustige rit"))
        XCTAssertTrue(text.hasPrefix("Circa"))
        XCTAssertTrue(text.hasSuffix("."))
    }

    func testCoachHint_ContainsTrimpAndEqualsSign() {
        let hint = TRIMPTranslator.coachHint(8.0, for: .marathon)
        XCTAssertTrue(hint.contains("8"))
        XCTAssertTrue(hint.contains("≈"))
        XCTAssertTrue(hint.contains("duurloop"))
    }

    // MARK: - GoalBlueprint.weeklyKmTarget

    func testWeeklyKmTarget_Marathon_Returns55() {
        let blueprint = BlueprintChecker.blueprint(for: .marathon)
        XCTAssertEqual(blueprint.weeklyKmTarget, 55.0, accuracy: 0.01)
    }

    func testWeeklyKmTarget_HalfMarathon_Returns40() {
        let blueprint = BlueprintChecker.blueprint(for: .halfMarathon)
        XCTAssertEqual(blueprint.weeklyKmTarget, 40.0, accuracy: 0.01)
    }

    func testWeeklyKmTarget_CyclingTour_Returns180() {
        let blueprint = BlueprintChecker.blueprint(for: .cyclingTour)
        XCTAssertEqual(blueprint.weeklyKmTarget, 180.0, accuracy: 0.01)
    }

    // MARK: - BlueprintGap: trimpGap & kmGap

    func testTRIMPGap_Positive_WhenBehind() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 80)
        XCTAssertEqual(gap.trimpGap, 20, accuracy: 0.01)
    }

    func testTRIMPGap_Negative_WhenAhead() {
        let gap = makeGap(requiredTRIMP: 80, actualTRIMP: 100)
        XCTAssertEqual(gap.trimpGap, -20, accuracy: 0.01)
    }

    func testKmGap_Positive_WhenBehind() {
        let gap = makeGap(requiredKm: 50, actualKm: 30)
        XCTAssertEqual(gap.kmGap, 20, accuracy: 0.01)
    }

    func testKmGap_Negative_WhenAhead() {
        let gap = makeGap(requiredKm: 30, actualKm: 50)
        XCTAssertEqual(gap.kmGap, -20, accuracy: 0.01)
    }

    // MARK: - BlueprintGap: voortgangspercentages

    func testTRIMPProgressPct_CorrectRatio() {
        let gap = makeGap(actualTRIMP: 80, totalPhaseTRIMP: 500)
        XCTAssertEqual(gap.trimpProgressPct, 0.16, accuracy: 0.001)
    }

    func testTRIMPProgressPct_ClampsToOne() {
        let gap = makeGap(actualTRIMP: 600, totalPhaseTRIMP: 500)
        XCTAssertEqual(gap.trimpProgressPct, 1.0, accuracy: 0.001)
    }

    func testTRIMPProgressPct_ZeroWhenNoTarget() {
        let gap = makeGap(actualTRIMP: 50, totalPhaseTRIMP: 0)
        XCTAssertEqual(gap.trimpProgressPct, 0.0)
    }

    func testTRIMPReferencePct_LinearProportion() {
        let gap = makeGap(requiredTRIMP: 100, totalPhaseTRIMP: 500)
        XCTAssertEqual(gap.trimpReferencePct, 0.20, accuracy: 0.001)
    }

    func testTRIMPReferencePct_ClampsToOne() {
        let gap = makeGap(requiredTRIMP: 600, totalPhaseTRIMP: 500)
        XCTAssertEqual(gap.trimpReferencePct, 1.0, accuracy: 0.001)
    }

    func testKmProgressPct_CorrectRatio() {
        let gap = makeGap(actualKm: 40, totalPhaseKm: 250)
        XCTAssertEqual(gap.kmProgressPct, 0.16, accuracy: 0.001)
    }

    func testKmProgressPct_ClampsToOne() {
        let gap = makeGap(actualKm: 300, totalPhaseKm: 250)
        XCTAssertEqual(gap.kmProgressPct, 1.0, accuracy: 0.001)
    }

    func testKmReferencePct_LinearProportion() {
        let gap = makeGap(requiredKm: 50, totalPhaseKm: 250)
        XCTAssertEqual(gap.kmReferencePct, 0.20, accuracy: 0.001)
    }

    // MARK: - BlueprintGap: drempelwaarden

    func testIsBehindOnTRIMP_TrueWhenGapExceeds10Pct() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 80)
        XCTAssertTrue(gap.isBehindOnTRIMP)
    }

    func testIsBehindOnTRIMP_FalseWhenWithin10Pct() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 95)
        XCTAssertFalse(gap.isBehindOnTRIMP)
    }

    func testIsBehindOnTRIMP_FalseWhenAhead() {
        let gap = makeGap(requiredTRIMP: 80, actualTRIMP: 100)
        XCTAssertFalse(gap.isBehindOnTRIMP)
    }

    func testIsBehindOnKm_TrueWhenGapExceeds10Pct() {
        let gap = makeGap(requiredKm: 50, actualKm: 30)
        XCTAssertTrue(gap.isBehindOnKm)
    }

    func testIsBehindOnKm_FalseWhenAhead() {
        let gap = makeGap(requiredKm: 30, actualKm: 50)
        XCTAssertFalse(gap.isBehindOnKm)
    }

    // MARK: - BlueprintGap: extraTRIMPPerWeek & catchUpHint

    func testExtraTRIMPPerWeek_ZeroWhenNotBehind() {
        let gap = makeGap(requiredTRIMP: 80, actualTRIMP: 100, weeksAhead: 20)
        XCTAssertEqual(gap.extraTRIMPPerWeek, 0.0)
    }

    func testExtraTRIMPPerWeek_PositiveWhenBehind() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 80, weeksAhead: 20)
        XCTAssertGreaterThan(gap.extraTRIMPPerWeek, 0)
    }

    func testCatchUpHint_NilWhenNotBehind() {
        let gap = makeGap(requiredTRIMP: 80, actualTRIMP: 100)
        XCTAssertNil(gap.catchUpHint)
    }

    func testCatchUpHint_NilWhenExtraTRIMPTooSmall() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 89, weeksAhead: 200)
        XCTAssertNil(gap.catchUpHint)
    }

    func testCatchUpHint_NotNilWhenSignificantlyBehind() {
        let gap = makeGap(requiredTRIMP: 200, actualTRIMP: 50, weeksAhead: 4)
        XCTAssertNotNil(gap.catchUpHint)
        XCTAssertTrue(gap.catchUpHint?.contains("TRIMP") == true)
    }

    // MARK: - BlueprintGap: phaseProgressLabel

    func testPhaseProgressLabel_ContainsPhaseNameAndWeek() {
        let gap = makeGap(phase: .buildPhase)
        let label = gap.phaseProgressLabel
        XCTAssertTrue(label.contains("Build Phase"))
        XCTAssertTrue(label.contains("3"))
        XCTAssertTrue(label.contains("8"))
    }

    // MARK: - BlueprintGap: trimpStatusLine

    func testTRIMPStatusLine_BehindMessage() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 60)
        XCTAssertTrue(gap.trimpStatusLine.contains("achter"))
    }

    func testTRIMPStatusLine_AheadMessage() {
        let gap = makeGap(requiredTRIMP: 60, actualTRIMP: 100)
        XCTAssertTrue(gap.trimpStatusLine.contains("voor"))
    }

    func testTRIMPStatusLine_OnTrackMessage() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 98)
        XCTAssertTrue(gap.trimpStatusLine.contains("ideale pad"))
    }

    // MARK: - BlueprintGap: kmStatusLine

    func testKmStatusLine_NilWhenNoKmTarget() {
        let gap = makeGap(totalPhaseKm: 0)
        XCTAssertNil(gap.kmStatusLine)
    }

    func testKmStatusLine_BehindMessage() {
        let gap = makeGap(requiredKm: 50, actualKm: 40, totalPhaseKm: 250)
        XCTAssertTrue(gap.kmStatusLine?.contains("achter") == true)
    }

    func testKmStatusLine_AheadMessage() {
        let gap = makeGap(requiredKm: 40, actualKm: 50, totalPhaseKm: 250)
        XCTAssertTrue(gap.kmStatusLine?.contains("méér") == true)
    }

    func testKmStatusLine_OnTrackMessage() {
        let gap = makeGap(requiredKm: 50, actualKm: 50.5, totalPhaseKm: 250)
        XCTAssertTrue(gap.kmStatusLine?.contains("ideale pad") == true)
    }

    // MARK: - BlueprintGap: coachContext

    func testCoachContext_ContainsGoalTitleAndBlueprint() {
        let gap = makeGap(goalTitle: "Marathon Rotterdam", blueprintType: .marathon)
        let ctx = gap.coachContext
        XCTAssertTrue(ctx.contains("Marathon Rotterdam"))
        XCTAssertTrue(ctx.contains("Marathon"))
    }

    func testCoachContext_ContainsTRIMPProgressLine() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 80, totalPhaseTRIMP: 500)
        let ctx = gap.coachContext
        XCTAssertTrue(ctx.contains("TRIMP"))
    }

    func testCoachContext_ContainsCatchUpHintWhenBehind() {
        let gap = makeGap(requiredTRIMP: 200, actualTRIMP: 50, weeksAhead: 4)
        let ctx = gap.coachContext
        XCTAssertTrue(ctx.contains("VOLUME-BIJSTURING"))
    }

    // MARK: - ProgressService.analyzeGaps

    func testAnalyzeGaps_EmptyGoals_ReturnsEmpty() {
        let result = ProgressService.analyzeGaps(for: [], activities: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testAnalyzeGaps_CompletedGoal_IsFiltered() {
        let goal = makeGoal(title: "Marathon Rotterdam", isCompleted: true)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testAnalyzeGaps_PastTargetDate_IsFiltered() {
        let pastDate = calendar.date(byAdding: .weekOfYear, value: -1, to: Date())!
        let goal = FitnessGoal(title: "Marathon Rotterdam", targetDate: pastDate)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testAnalyzeGaps_NoBlueprintGoal_IsFiltered() {
        let goal = makeGoal(title: "Gewoon fitter worden", sport: .strength)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testAnalyzeGaps_ValidGoalNoActivities_ReturnsOneGap() {
        let goal = makeGoal(title: "Marathon Rotterdam", sport: .running, weeksAhead: 8, weeksAgoCreated: 4)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.blueprintType, .marathon)
    }

    func testAnalyzeGaps_ActivitiesInPhase_CountedInActualTRIMP() {
        let goal = makeGoal(title: "Marathon Rotterdam", sport: .running, weeksAhead: 8, weeksAgoCreated: 4)
        let act1 = makeActivity(sport: .running, distanceMeters: 15000, trimp: 80, weeksAgo: 1)
        let act2 = makeActivity(sport: .running, distanceMeters: 12000, trimp: 60, weeksAgo: 2)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [act1, act2])
        XCTAssertEqual(result.first?.actualTRIMPToDate, 140, accuracy: 0.01)
    }

    func testAnalyzeGaps_ActivitiesOutsidePhase_NotCounted() {
        let goal = makeGoal(title: "Marathon Rotterdam", sport: .running, weeksAhead: 8, weeksAgoCreated: 4)
        let oldActivity = makeActivity(sport: .running, distanceMeters: 20000, trimp: 200, weeksAgo: 6)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [oldActivity])
        XCTAssertEqual(result.first?.actualTRIMPToDate ?? -1, 0, accuracy: 0.01)
    }

    func testAnalyzeGaps_SortedByTRIMPGapDescending() {
        let goalA = makeGoal(title: "Marathon Amsterdam", sport: .running, weeksAhead: 8, weeksAgoCreated: 4)
        let goalB = makeGoal(title: "Arnhem Karlsruhe cycling tour", sport: .cycling, weeksAhead: 8, weeksAgoCreated: 4)

        var activities = [ActivityRecord]()
        for week in 1...5 {
            activities.append(makeActivity(sport: .running, distanceMeters: 15000, trimp: 600, weeksAgo: week))
        }

        let result = ProgressService.analyzeGaps(for: [goalA, goalB], activities: activities)

        guard result.count == 2 else {
            XCTFail("Beide doelen moeten een gap opleveren; gekregen: \(result.count)")
            return
        }

        XCTAssertGreaterThan(result[0].trimpGap, result[1].trimpGap)
    }

    func testAnalyzeGaps_MultipleValidGoals_AllReturned() {
        let goalA = makeGoal(title: "Marathon Amsterdam", sport: .running, weeksAhead: 16)
        let goalB = makeGoal(title: "Arnhem Karlsruhe cycling tour", sport: .cycling, weeksAhead: 16)
        let result = ProgressService.analyzeGaps(for: [goalA, goalB], activities: [])
        XCTAssertEqual(result.count, 2)
    }
}
