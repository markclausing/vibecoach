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

    /// 8 TRIMP, fietsen: zone2 = ceil(8/2)=4, zone4 = ceil(8/4)=2 → beide zones getoond.
    func testTranslate_CyclingTour_8Trimp_ShowsBothZones() {
        let result = TRIMPTranslator.translate(8.0, for: .cyclingTour)
        XCTAssertEqual(result, "+4 min rustige rit of +2 min tempo-rit",
                       "8 TRIMP cyclingTour moet beide zones tonen met de juiste labels.")
    }

    /// 4 TRIMP, marathon: zone2 = ceil(4/2)=2, zone4 = ceil(4/4)=1 → beide zones getoond.
    func testTranslate_Marathon_4Trimp_ShowsBothZones() {
        let result = TRIMPTranslator.translate(4.0, for: .marathon)
        XCTAssertEqual(result, "+2 min duurloop (Z2) of +1 min intervaltraining (Z4)",
                       "4 TRIMP marathon moet hardloopspecifieke labels gebruiken.")
    }

    /// Halve marathon gebruikt dezelfde hardlooplabels als marathon.
    func testTranslate_HalfMarathon_UsesRunningLabels() {
        let result = TRIMPTranslator.translate(4.0, for: .halfMarathon)
        XCTAssertTrue(result.contains("duurloop"),
                      "halfMarathon moet 'duurloop'-label gebruiken.")
        XCTAssertTrue(result.contains("intervaltraining"),
                      "halfMarathon moet 'intervaltraining'-label gebruiken.")
    }

    /// 2 TRIMP, fietsen: zone2 = ceil(2/2)=1, zone4 = ceil(2/4)=1 → beide gelijk → alleen zone2.
    func testTranslate_SmallTrimp_BothZonesEqual_ShowsOnlyZone2() {
        let result = TRIMPTranslator.translate(2.0, for: .cyclingTour)
        XCTAssertEqual(result, "+1 min rustige rit",
                       "Als zone2Min == zone4Min moet alleen de zone2-versie getoond worden.")
        XCTAssertFalse(result.contains("of"),
                       "Bij gelijke zones mag 'of' niet in de tekst staan.")
    }

    // MARK: - TRIMPTranslator: bannerText & coachHint

    /// bannerText moet het TRIMP-getal en de hint bevatten in de juiste zin.
    func testBannerText_ContainsTrimpValueAndHint() {
        let text = TRIMPTranslator.bannerText(8.0, for: .cyclingTour)
        XCTAssertTrue(text.contains("8"),
                      "bannerText moet het afgeronde TRIMP-getal bevatten.")
        XCTAssertTrue(text.contains("rustige rit"),
                      "bannerText moet de zone2-hint bevatten.")
        XCTAssertTrue(text.hasPrefix("Circa"),
                      "bannerText moet beginnen met 'Circa'.")
        XCTAssertTrue(text.hasSuffix("."),
                      "bannerText moet eindigen met een punt.")
    }

    /// coachHint heeft een compacter formaat met ≈-teken.
    func testCoachHint_ContainsTrimpAndEqualsSign() {
        let hint = TRIMPTranslator.coachHint(8.0, for: .marathon)
        XCTAssertTrue(hint.contains("8"),
                      "coachHint moet het TRIMP-getal bevatten.")
        XCTAssertTrue(hint.contains("≈"),
                      "coachHint moet het ≈-teken bevatten.")
        XCTAssertTrue(hint.contains("duurloop"),
                      "coachHint moet de zone2-label bevatten.")
    }

    // MARK: - GoalBlueprint.weeklyKmTarget

    /// Marathon: Pfitzinger 18/55 → 55 km/week.
    func testWeeklyKmTarget_Marathon_Returns55() {
        let blueprint = BlueprintChecker.blueprint(for: .marathon)
        XCTAssertEqual(blueprint.weeklyKmTarget, 55.0, accuracy: 0.01,
                       "Marathon blueprint moet 55 km/week als opbouwdoel hanteren.")
    }

    /// Halve marathon: 40 km/week.
    func testWeeklyKmTarget_HalfMarathon_Returns40() {
        let blueprint = BlueprintChecker.blueprint(for: .halfMarathon)
        XCTAssertEqual(blueprint.weeklyKmTarget, 40.0, accuracy: 0.01,
                       "Halve marathon blueprint moet 40 km/week als opbouwdoel hanteren.")
    }

    /// Fietstocht (Arnhem–Karlsruhe): 180 km/week.
    func testWeeklyKmTarget_CyclingTour_Returns180() {
        let blueprint = BlueprintChecker.blueprint(for: .cyclingTour)
        XCTAssertEqual(blueprint.weeklyKmTarget, 180.0, accuracy: 0.01,
                       "Cycling tour blueprint moet 180 km/week als opbouwdoel hanteren.")
    }

    // MARK: - BlueprintGap: trimpGap & kmGap

    /// Achterstand: required > actual → trimpGap is positief.
    func testTRIMPGap_Positive_WhenBehind() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 80)
        XCTAssertEqual(gap.trimpGap, 20, accuracy: 0.01,
                       "required(100) - actual(80) = gap 20 (achterstand).")
    }

    /// Voorsprong: actual > required → trimpGap is negatief.
    func testTRIMPGap_Negative_WhenAhead() {
        let gap = makeGap(requiredTRIMP: 80, actualTRIMP: 100)
        XCTAssertEqual(gap.trimpGap, -20, accuracy: 0.01,
                       "required(80) - actual(100) = gap -20 (voorsprong).")
    }

    /// Km-achterstand: required > actual → kmGap is positief.
    func testKmGap_Positive_WhenBehind() {
        let gap = makeGap(requiredKm: 50, actualKm: 30)
        XCTAssertEqual(gap.kmGap, 20, accuracy: 0.01,
                       "required(50) - actual(30) = kmGap 20 (achterstand).")
    }

    /// Km-voorsprong: actual > required → kmGap is negatief.
    func testKmGap_Negative_WhenAhead() {
        let gap = makeGap(requiredKm: 30, actualKm: 50)
        XCTAssertEqual(gap.kmGap, -20, accuracy: 0.01,
                       "required(30) - actual(50) = kmGap -20 (voorsprong).")
    }

    // MARK: - BlueprintGap: voortgangspercentages

    /// trimpProgressPct = actual / total (80/500 = 0.16).
    func testTRIMPProgressPct_CorrectRatio() {
        let gap = makeGap(actualTRIMP: 80, totalPhaseTRIMP: 500)
        XCTAssertEqual(gap.trimpProgressPct, 0.16, accuracy: 0.001,
                       "80/500 moet 16% opleveren.")
    }

    /// trimpProgressPct wordt afgekapt op 1.0 als actual > total.
    func testTRIMPProgressPct_ClampsToOne() {
        let gap = makeGap(actualTRIMP: 600, totalPhaseTRIMP: 500)
        XCTAssertEqual(gap.trimpProgressPct, 1.0, accuracy: 0.001,
                       "Overtraining (actual > total) mag nooit boven 100% komen.")
    }

    /// trimpProgressPct = 0 als er geen fase-target is (voorkomt deling door nul).
    func testTRIMPProgressPct_ZeroWhenNoTarget() {
        let gap = makeGap(actualTRIMP: 50, totalPhaseTRIMP: 0)
        XCTAssertEqual(gap.trimpProgressPct, 0.0,
                       "Geen totale fase-target → progress = 0 (geen deling door nul).")
    }

    /// trimpReferencePct = required / total (100/500 = 0.20).
    func testTRIMPReferencePct_LinearProportion() {
        let gap = makeGap(requiredTRIMP: 100, totalPhaseTRIMP: 500)
        XCTAssertEqual(gap.trimpReferencePct, 0.20, accuracy: 0.001,
                       "100/500 moet de ghost-positie op 20% zetten.")
    }

    /// trimpReferencePct afgekapt op 1.0.
    func testTRIMPReferencePct_ClampsToOne() {
        let gap = makeGap(requiredTRIMP: 600, totalPhaseTRIMP: 500)
        XCTAssertEqual(gap.trimpReferencePct, 1.0, accuracy: 0.001,
                       "required > total → ghost-positie maximaal 100%.")
    }

    /// kmProgressPct = actual / total (40/250 = 0.16).
    func testKmProgressPct_CorrectRatio() {
        let gap = makeGap(actualKm: 40, totalPhaseKm: 250)
        XCTAssertEqual(gap.kmProgressPct, 0.16, accuracy: 0.001,
                       "40/250 moet 16% km-voortgang opleveren.")
    }

    /// kmProgressPct afgekapt op 1.0.
    func testKmProgressPct_ClampsToOne() {
        let gap = makeGap(actualKm: 300, totalPhaseKm: 250)
        XCTAssertEqual(gap.kmProgressPct, 1.0, accuracy: 0.001,
                       "actual km > total mag nooit boven 100% komen.")
    }

    /// kmReferencePct = required / total (50/250 = 0.20).
    func testKmReferencePct_LinearProportion() {
        let gap = makeGap(requiredKm: 50, totalPhaseKm: 250)
        XCTAssertEqual(gap.kmReferencePct, 0.20, accuracy: 0.001,
                       "50/250 moet de ghost km-positie op 20% zetten.")
    }

    // MARK: - BlueprintGap: drempelwaarden

    /// isBehindOnTRIMP = true als trimpGap > required × 10%.
    /// gap = 100 - 80 = 20 > 100 × 0.10 = 10 → TRUE.
    func testIsBehindOnTRIMP_TrueWhenGapExceeds10Pct() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 80)
        XCTAssertTrue(gap.isBehindOnTRIMP,
                      "Gap 20 > drempel 10 (10%) → isBehindOnTRIMP moet true zijn.")
    }

    /// isBehindOnTRIMP = false als trimpGap ≤ required × 10%.
    /// gap = 100 - 95 = 5 ≤ 100 × 0.10 = 10 → FALSE.
    func testIsBehindOnTRIMP_FalseWhenWithin10Pct() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 95)
        XCTAssertFalse(gap.isBehindOnTRIMP,
                       "Gap 5 ≤ drempel 10 (10%) → isBehindOnTRIMP moet false zijn.")
    }

    /// isBehindOnTRIMP = false als atleet voor ligt (trimpGap is negatief).
    func testIsBehindOnTRIMP_FalseWhenAhead() {
        let gap = makeGap(requiredTRIMP: 80, actualTRIMP: 100)
        XCTAssertFalse(gap.isBehindOnTRIMP,
                       "Voorsprong (negatieve gap) → isBehindOnTRIMP moet false zijn.")
    }

    /// isBehindOnKm = true als kmGap > required × 10%.
    /// gap = 50 - 30 = 20 > 50 × 0.10 = 5 → TRUE.
    func testIsBehindOnKm_TrueWhenGapExceeds10Pct() {
        let gap = makeGap(requiredKm: 50, actualKm: 30)
        XCTAssertTrue(gap.isBehindOnKm,
                      "Km-gap 20 > drempel 5 (10%) → isBehindOnKm moet true zijn.")
    }

    /// isBehindOnKm = false als atleet voorloopt.
    func testIsBehindOnKm_FalseWhenAhead() {
        let gap = makeGap(requiredKm: 30, actualKm: 50)
        XCTAssertFalse(gap.isBehindOnKm,
                       "Voorsprong op km → isBehindOnKm moet false zijn.")
    }

    // MARK: - BlueprintGap: extraTRIMPPerWeek & catchUpHint

    /// extraTRIMPPerWeek = 0 als de atleet niet achterloopt.
    func testExtraTRIMPPerWeek_ZeroWhenNotBehind() {
        // actual > required → niet achter
        let gap = makeGap(requiredTRIMP: 80, actualTRIMP: 100, weeksAhead: 20)
        XCTAssertEqual(gap.extraTRIMPPerWeek, 0.0,
                       "Voorsprong → extraTRIMPPerWeek moet 0 zijn.")
    }

    /// extraTRIMPPerWeek is positief en gelijk aan trimpGap / weeksRemaining als achter.
    func testExtraTRIMPPerWeek_PositiveWhenBehind() {
        // gap = 100-80=20; weeksRemaining ≈ 20w; extra ≈ 1.0/week
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 80, weeksAhead: 20)
        XCTAssertGreaterThan(gap.extraTRIMPPerWeek, 0,
                             "Achterstand met tijd resterend → extraTRIMPPerWeek moet positief zijn.")
    }

    /// catchUpHint = nil als niet achter.
    func testCatchUpHint_NilWhenNotBehind() {
        let gap = makeGap(requiredTRIMP: 80, actualTRIMP: 100)
        XCTAssertNil(gap.catchUpHint,
                     "Geen achterstand → catchUpHint moet nil zijn.")
    }

    /// catchUpHint = nil als extraTRIMPPerWeek ≤ 0.5 (te klein om te melden).
    func testCatchUpHint_NilWhenExtraTRIMPTooSmall() {
        // gap = 100 - 89 = 11 > 10% (100×0.10) → isBehindOnTRIMP = TRUE
        // Maar met 200w resterend → extra = 11/200 = 0.055 ≤ 0.5 → nil
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 89, weeksAhead: 200)
        // extraTRIMPPerWeek ≈ 0.055 → nil omdat ≤ 0.5
        XCTAssertNil(gap.catchUpHint,
                     "Extra TRIMP/week ≤ 0.5 → catchUpHint moet nil zijn.")
    }

    /// catchUpHint is niet nil en bevat een zinvolle tekst als de atleet significant achterloopt.
    func testCatchUpHint_NotNilWhenSignificantlyBehind() {
        // gap = 200-50=150 > 200×0.10=20 → isBehindOnTRIMP=TRUE
        // weeksRemaining ≈ 4 → extra = 150/4 = 37.5 >> 0.5
        let gap = makeGap(requiredTRIMP: 200, actualTRIMP: 50, weeksAhead: 4)
        XCTAssertNotNil(gap.catchUpHint,
                        "Significante achterstand → catchUpHint moet een tekst bevatten.")
        XCTAssertTrue(gap.catchUpHint?.contains("TRIMP") == true,
                      "catchUpHint moet 'TRIMP' bevatten.")
    }

    // MARK: - BlueprintGap: phaseProgressLabel

    /// phaseProgressLabel bevat de fase-naam en het weeknummer.
    func testPhaseProgressLabel_ContainsPhaseNameAndWeek() {
        let gap = makeGap(phase: .buildPhase)
        let label = gap.phaseProgressLabel
        XCTAssertTrue(label.contains("Build Phase"),
                      "Label moet de fase-naam 'Build Phase' bevatten.")
        XCTAssertTrue(label.contains("3"),
                      "Label moet het huidige weeknummer (3) bevatten.")
        XCTAssertTrue(label.contains("8"),
                      "Label moet het totale aantal weken (8) bevatten.")
    }

    // MARK: - BlueprintGap: trimpStatusLine

    /// Achterstand > 5 TRIMP → "achter"-boodschap.
    func testTRIMPStatusLine_BehindMessage() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 60)  // gap = 40 > 5
        XCTAssertTrue(gap.trimpStatusLine.contains("achter"),
                      "Gap > 5 → statusline moet 'achter' bevatten.")
    }

    /// Voorsprong > 5 TRIMP → "voor"-boodschap.
    func testTRIMPStatusLine_AheadMessage() {
        let gap = makeGap(requiredTRIMP: 60, actualTRIMP: 100)  // gap = -40 < -5
        XCTAssertTrue(gap.trimpStatusLine.contains("voor"),
                      "Gap < -5 → statusline moet 'voor' bevatten.")
    }

    /// Gap tussen -5 en +5 → "op het ideale pad"-boodschap.
    func testTRIMPStatusLine_OnTrackMessage() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 98)  // gap = 2 → on-track
        XCTAssertTrue(gap.trimpStatusLine.contains("ideale pad"),
                      "Gap tussen -5 en +5 → statusline moet 'ideale pad' bevatten.")
    }

    // MARK: - BlueprintGap: kmStatusLine

    /// kmStatusLine = nil als er geen km-target is (totalPhaseKmTarget = 0).
    func testKmStatusLine_NilWhenNoKmTarget() {
        let gap = makeGap(totalPhaseKm: 0)
        XCTAssertNil(gap.kmStatusLine,
                     "Geen km-target → kmStatusLine moet nil zijn.")
    }

    /// Km-achterstand > 1 km → "achter"-boodschap.
    func testKmStatusLine_BehindMessage() {
        let gap = makeGap(requiredKm: 50, actualKm: 40, totalPhaseKm: 250)  // gap = 10 > 1
        XCTAssertTrue(gap.kmStatusLine?.contains("achter") == true,
                      "Km-gap > 1 → statusline moet 'achter' bevatten.")
    }

    /// Km-voorsprong > 1 km → "méér gedaan"-boodschap.
    func testKmStatusLine_AheadMessage() {
        let gap = makeGap(requiredKm: 40, actualKm: 50, totalPhaseKm: 250)  // gap = -10 < -1
        XCTAssertTrue(gap.kmStatusLine?.contains("méér") == true,
                      "Km-gap < -1 → statusline moet 'méér' bevatten.")
    }

    /// Km-gap tussen -1 en +1 → "op het ideale pad"-boodschap.
    func testKmStatusLine_OnTrackMessage() {
        let gap = makeGap(requiredKm: 50, actualKm: 50.5, totalPhaseKm: 250)  // gap = -0.5 → on-track
        XCTAssertTrue(gap.kmStatusLine?.contains("ideale pad") == true,
                      "Km-gap binnen ±1 → statusline moet 'ideale pad' bevatten.")
    }

    // MARK: - BlueprintGap: coachContext

    /// coachContext bevat de doeltitel en de blueprint-naam.
    func testCoachContext_ContainsGoalTitleAndBlueprint() {
        let gap = makeGap(goalTitle: "Marathon Rotterdam", blueprintType: .marathon)
        let ctx = gap.coachContext
        XCTAssertTrue(ctx.contains("Marathon Rotterdam"),
                      "coachContext moet de doeltitel bevatten.")
        XCTAssertTrue(ctx.contains("Marathon"),
                      "coachContext moet de blueprint-naam bevatten.")
    }

    /// coachContext bevat TRIMP-voortgangsregel.
    func testCoachContext_ContainsTRIMPProgressLine() {
        let gap = makeGap(requiredTRIMP: 100, actualTRIMP: 80, totalPhaseTRIMP: 500)
        let ctx = gap.coachContext
        XCTAssertTrue(ctx.contains("TRIMP"),
                      "coachContext moet de TRIMP-voortgangsregel bevatten.")
    }

    /// coachContext bevat bijsturingshint als de atleet significant achterloopt.
    func testCoachContext_ContainsCatchUpHintWhenBehind() {
        let gap = makeGap(requiredTRIMP: 200, actualTRIMP: 50, weeksAhead: 4)
        let ctx = gap.coachContext
        XCTAssertTrue(ctx.contains("VOLUME-BIJSTURING"),
                      "Significante achterstand → coachContext moet bijsturingssectie bevatten.")
    }

    // MARK: - ProgressService.analyzeGaps

    /// Lege doellijst → lege uitvoer.
    func testAnalyzeGaps_EmptyGoals_ReturnsEmpty() {
        let result = ProgressService.analyzeGaps(for: [], activities: [])
        XCTAssertTrue(result.isEmpty,
                      "Geen doelen → geen gaps.")
    }

    /// Voltooid doel wordt gefilterd.
    func testAnalyzeGaps_CompletedGoal_IsFiltered() {
        let goal = makeGoal(title: "Marathon Rotterdam", isCompleted: true)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertTrue(result.isEmpty,
                      "Voltooid doel moet worden gefilterd uit de gap-analyse.")
    }

    /// Doel met targetDate in het verleden wordt gefilterd.
    func testAnalyzeGaps_PastTargetDate_IsFiltered() {
        let pastDate = calendar.date(byAdding: .weekOfYear, value: -1, to: Date())!
        let goal = FitnessGoal(title: "Marathon Rotterdam", targetDate: pastDate)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertTrue(result.isEmpty,
                      "Verlopen doel (targetDate in verleden) moet worden gefilterd.")
    }

    /// Doel zonder herkenbaar blueprint-type (sport: strength, generieke titel) → geen gap.
    func testAnalyzeGaps_NoBlueprintGoal_IsFiltered() {
        let goal = makeGoal(title: "Gewoon fitter worden", sport: .strength)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertTrue(result.isEmpty,
                      "Doel zonder blueprint-type moet worden gefilterd.")
    }

    /// Geldig marathon-doel zonder activiteiten → geeft één gap terug.
    func testAnalyzeGaps_ValidGoalNoActivities_ReturnsOneGap() {
        let goal = makeGoal(title: "Marathon Rotterdam", sport: .running, weeksAhead: 8, weeksAgoCreated: 4)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertEqual(result.count, 1,
                       "Één geldig doel moet één gap opleveren.")
        XCTAssertEqual(result.first?.blueprintType, .marathon,
                       "Blueprint type moet marathon zijn.")
    }

    /// Activiteiten binnen de fase worden meegenomen in de actualTRIMP-berekening.
    func testAnalyzeGaps_ActivitiesInPhase_CountedInActualTRIMP() {
        let goal = makeGoal(title: "Marathon Rotterdam", sport: .running, weeksAhead: 8, weeksAgoCreated: 4)
        // Activiteiten 1 en 2 weken geleden (vallen binnen de fase)
        let act1 = makeActivity(sport: .running, distanceMeters: 15000, trimp: 80, weeksAgo: 1)
        let act2 = makeActivity(sport: .running, distanceMeters: 12000, trimp: 60, weeksAgo: 2)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [act1, act2])
        XCTAssertEqual(result.first?.actualTRIMPToDate, 140, accuracy: 0.01,
                       "Twee activiteiten met TRIMP 80+60=140 moeten meegeteld worden.")
    }

    /// Activiteiten buiten de fase (te oud) worden NIET meegenomen.
    func testAnalyzeGaps_ActivitiesOutsidePhase_NotCounted() {
        // Doel: 8 weken ahead, 4 weken geleden aangemaakt → fase start 4 weken geleden
        let goal = makeGoal(title: "Marathon Rotterdam", sport: .running, weeksAhead: 8, weeksAgoCreated: 4)
        // Activiteit 6 weken geleden → vóór fasestart (4w geleden) → niet meegeteld
        let oldActivity = makeActivity(sport: .running, distanceMeters: 20000, trimp: 200, weeksAgo: 6)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [oldActivity])
        XCTAssertEqual(result.first?.actualTRIMPToDate ?? -1, 0, accuracy: 0.01,
                       "Activiteit vóór fasestart moet NIET meegeteld worden in actualTRIMP.")
    }

    /// Sortering: doel met grotere achterstand (hogere trimpGap) staat vooraan.
    func testAnalyzeGaps_SortedByTRIMPGapDescending() {
        // Doel A: marathon, 4w geleden aangemaakt, 8w ahead, veel activiteiten → klein/negatief gap
        let goalA = makeGoal(title: "Marathon Amsterdam", sport: .running, weeksAhead: 8, weeksAgoCreated: 4)
        // Doel B: cycling, 4w geleden aangemaakt, 8w ahead, geen activiteiten → groot positief gap
        let goalB = makeGoal(title: "Arnhem Karlsruhe cycling tour", sport: .cycling, weeksAhead: 8, weeksAgoCreated: 4)

        // Activiteiten voor Goal A: veel TRIMP zodat er een voorsprong is (negatieve gap)
        let activities: [ActivityRecord] = (1...5).map { week in
            makeActivity(sport: .running, distanceMeters: 15000, trimp: 600, weeksAgo: week)
        }

        let result = ProgressService.analyzeGaps(for: [goalA, goalB], activities: activities)

        guard result.count == 2 else {
            XCTFail("Beide doelen moeten een gap opleveren; gekregen: \(result.count)")
            return
        }

        // Goal B (geen activiteiten, grote achterstand) moet als eerste staan
        XCTAssertGreaterThan(result[0].trimpGap, result[1].trimpGap,
                             "Het doel met de grootste achterstand (hoogste trimpGap) moet vooraan staan.")
    }

    /// Meerdere doelen zonder activiteiten worden alle teruggegeven.
    func testAnalyzeGaps_MultipleValidGoals_AllReturned() {
        let goalA = makeGoal(title: "Marathon Amsterdam", sport: .running, weeksAhead: 16)
        let goalB = makeGoal(title: "Arnhem Karlsruhe cycling tour", sport: .cycling, weeksAhead: 16)
        let result = ProgressService.analyzeGaps(for: [goalA, goalB], activities: [])
        XCTAssertEqual(result.count, 2,
                       "Twee geldige doelen moeten twee gaps opleveren.")
    }
}
