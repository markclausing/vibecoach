import XCTest
@testable import AIFitnessCoach

/// Epic #73 story 73.4 — unit tests for the unified periodisation context. The point of the story
/// is that the coach prompt can no longer contain two contradicting phase instructions, so most of
/// these assert on the *absence* of a conflict as much as on the header content.
///
/// `PeriodizationEngine.evaluate` reads `Date()` internally, so goals here are built relative to
/// the real now (unlike `MacrocyclePlannerTests`, which injects its clock).
final class MacrocycleContextFormatterTests: XCTestCase {

    private let cal = Calendar.current
    private let now = Date()

    private func makeGoal(title: String, targetInDays: Int, createdDaysAgo: Int = 30) -> FitnessGoal {
        FitnessGoal(
            title: title,
            // swiftlint:disable:next force_unwrapping
            targetDate: cal.date(byAdding: .day, value: targetInDays, to: now)!,
            // swiftlint:disable:next force_unwrapping
            createdAt: cal.date(byAdding: .day, value: -createdDaysAgo, to: now)!,
            isCompleted: false,
            sportCategory: .running,
            targetTRIMP: 2000
        )
    }

    /// Two overlapping races: Haarlem (interim) and Amsterdam (anchor) — the scenario that
    /// produced the contradicting prompt sections in the first place.
    private func twoRaceFixture() -> (haarlem: FitnessGoal, amsterdam: FitnessGoal,
                                      program: UnifiedProgram, results: [PeriodizationResult]) {
        let haarlem   = makeGoal(title: "Halve marathon Haarlem", targetInDays: 64)
        let amsterdam = makeGoal(title: "Marathon Amsterdam", targetInDays: 86)
        // swiftlint:disable:next force_unwrapping
        let program = MacrocyclePlanner.plan(goals: [haarlem, amsterdam], now: now)!
        let results = PeriodizationEngine.evaluateAllGoals(
            [haarlem, amsterdam],
            activities: [],
            phaseOverride: program.currentPhase
        )
        return (haarlem, amsterdam, program, results)
    }

    // MARK: - Header content

    func testHeaderNamesTheAnchorAsTheARaceAndTheInterimAsATuneUp() {
        let fixture = twoRaceFixture()
        let context = MacrocycleContextFormatter.format(
            program: fixture.program, results: fixture.results, now: now
        )

        XCTAssertTrue(context.contains("═══ UNIFIED TRAINING PROGRAM (one macrocycle) ═══"))
        XCTAssertTrue(context.contains("🎯 A-RACE: 'Marathon Amsterdam'"))
        XCTAssertFalse(context.contains("🎯 A-RACE: 'Halve marathon Haarlem'"))

        // The interim race appears under the tune-up list with its mini-taper, never as an anchor.
        XCTAssertTrue(context.contains("Interim races (tune-ups INSIDE this program"))
        XCTAssertTrue(context.contains("'Halve marathon Haarlem'"))
        XCTAssertTrue(context.contains("mini-taper from"))
    }

    func testHeaderCarriesTheCombinedWeeklyTargetAndProgramWeek() {
        let fixture = twoRaceFixture()
        let context = MacrocycleContextFormatter.format(
            program: fixture.program, results: fixture.results, now: now
        )

        let expectedTarget = String(format: "%.0f", fixture.program.weeklyTrimpTarget)
        XCTAssertTrue(context.contains("Combined weekly load target: \(expectedTarget) TRIMP/week."))

        let week = fixture.program.programWeek(at: now)
        XCTAssertTrue(context.contains("program week \(week.current)/\(week.total)"))
    }

    // MARK: - No contradicting phases (the actual bug)

    func testEveryGoalBlockReportsTheSameMacrocyclePhase() throws {
        let fixture = twoRaceFixture()
        XCTAssertEqual(fixture.results.count, 2, "both goals resolve to a running blueprint")

        let context = MacrocycleContextFormatter.format(
            program: fixture.program, results: fixture.results, now: now
        )

        let phaseLines = context
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("Phase: ") }
        XCTAssertEqual(phaseLines.count, 2)

        let phaseName = fixture.program.currentPhase.displayName
        XCTAssertTrue(phaseLines.allSatisfy { $0.contains(phaseName) },
                      "per-goal blocks must inherit the macrocycle phase, not their own countdown")

        // The regression this story fixes: without the override these exact two goals land in
        // *different* phases (Haarlem at 64 d is building, Amsterdam at 86 d is still base), which
        // is what produced two contradicting `═══ PERIODISERING ═══` sections in one prompt.
        let unoverridden = PeriodizationEngine.evaluateAllGoals(
            [fixture.haarlem, fixture.amsterdam], activities: []
        )
        XCTAssertEqual(Set(unoverridden.map(\.phase)).count, 2)
    }

    func testHardRuleForbidsAFullTaperForAnInterimRace() {
        let fixture = twoRaceFixture()
        let context = MacrocycleContextFormatter.format(
            program: fixture.program, results: fixture.results, now: now
        )
        XCTAssertTrue(context.contains("HARD RULE — ONE PROGRAM"))
        XCTAssertTrue(context.contains("Never advise a full taper for an interim race"))
    }

    // MARK: - Mini-taper

    func testActiveMiniTaperIsAnnouncedExplicitly() {
        // Haarlem 2 days out → inside its 4-day mini-taper window.
        let haarlem   = makeGoal(title: "Halve marathon Haarlem", targetInDays: 2)
        let amsterdam = makeGoal(title: "Marathon Amsterdam", targetInDays: 40)
        guard let program = MacrocyclePlanner.plan(goals: [haarlem, amsterdam], now: now) else {
            return XCTFail("expected a program for two active goals")
        }
        let results = PeriodizationEngine.evaluateAllGoals(
            [haarlem, amsterdam], activities: [], phaseOverride: program.currentPhase
        )

        let context = MacrocycleContextFormatter.format(program: program, results: results, now: now)

        XCTAssertTrue(program.inMiniTaper)
        XCTAssertTrue(context.contains("⚡ MINI-TAPER ACTIVE for 'Halve marathon Haarlem'"))
        XCTAssertTrue(context.contains("Do NOT start a full taper"))
    }

    func testNoMiniTaperLineWhenNoInterimRaceIsClose() {
        let fixture = twoRaceFixture()
        let context = MacrocycleContextFormatter.format(
            program: fixture.program, results: fixture.results, now: now
        )
        XCTAssertFalse(fixture.program.inMiniTaper)
        XCTAssertFalse(context.contains("⚡ MINI-TAPER ACTIVE"))
    }

    // MARK: - Degenerate cases (story 73.6 parity)

    func testSingleGoalStillGetsAHeaderWithoutAnInterimSection() {
        let amsterdam = makeGoal(title: "Marathon Amsterdam", targetInDays: 86)
        guard let program = MacrocyclePlanner.plan(goals: [amsterdam], now: now) else {
            return XCTFail("expected a program for one active goal")
        }
        let results = PeriodizationEngine.evaluateAllGoals(
            [amsterdam], activities: [], phaseOverride: program.currentPhase
        )

        let context = MacrocycleContextFormatter.format(program: program, results: results, now: now)

        XCTAssertTrue(context.contains("🎯 A-RACE: 'Marathon Amsterdam'"))
        XCTAssertFalse(context.contains("Interim races"))
        XCTAssertTrue(context.contains("═══ PERIODISERING: 'Marathon Amsterdam' ═══"))
    }

    func testNoProgramFallsBackToThePlainPerGoalJoin() {
        let amsterdam = makeGoal(title: "Marathon Amsterdam", targetInDays: 86)
        let results = PeriodizationEngine.evaluateAllGoals([amsterdam], activities: [])

        let context = MacrocycleContextFormatter.format(program: nil, results: results, now: now)

        XCTAssertEqual(context, results.map { $0.coachingContext }.joined(separator: "\n\n"))
        XCTAssertFalse(context.contains("UNIFIED TRAINING PROGRAM"))
    }

    func testEmptyInputProducesAnEmptyContext() {
        XCTAssertEqual(MacrocycleContextFormatter.format(program: nil, results: [], now: now), "")
    }

    // MARK: - §13 structural markers

    func testUnifiedMarkersAreDeclaredAsStructuralPromptMarkers() {
        XCTAssertTrue(CoachPromptAssembler.structuralPromptMarkers.contains("🎯 A-RACE"))
        XCTAssertTrue(CoachPromptAssembler.structuralPromptMarkers.contains("⚡ MINI-TAPER"))
    }
}
