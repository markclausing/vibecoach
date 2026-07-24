import XCTest
@testable import AIFitnessCoach

/// Epic #73 story 73.1 — unit tests for `MacrocyclePlanner`, the engine that merges every active
/// goal into one macrocycle (A-race anchor + interim races as mini-taper tune-ups). All dates are
/// absolute and `now` is injected, so the tests are deterministic.
final class MacrocyclePlannerTests: XCTestCase {

    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func date(days: Int, from base: Date) -> Date {
        cal.date(byAdding: .day, value: days, to: base)!
    }

    private func makeGoal(title: String,
                          targetInDays: Int,
                          createdDaysAgo: Int = 7,
                          targetTRIMP: Double = 2000,
                          isCompleted: Bool = false) -> FitnessGoal {
        FitnessGoal(
            title: title,
            targetDate: date(days: targetInDays, from: now),
            createdAt: date(days: -createdDaysAgo, from: now),
            isCompleted: isCompleted,
            sportCategory: .running,
            targetTRIMP: targetTRIMP
        )
    }

    // MARK: - Empty / degenerate

    func testNoActiveGoalsReturnsNil() {
        XCTAssertNil(MacrocyclePlanner.plan(goals: [], now: now))
    }

    func testCompletedAndExpiredGoalsAreFilteredOut() {
        let completed = makeGoal(title: "Done", targetInDays: 30, isCompleted: true)
        let expired   = makeGoal(title: "Past", targetInDays: -5)
        XCTAssertNil(MacrocyclePlanner.plan(goals: [completed, expired], now: now))
    }

    // MARK: - Single goal (parity)

    func testSingleGoalIsItsOwnAnchorWithNoInterimRaces() {
        let goal = makeGoal(title: "Marathon Amsterdam", targetInDays: 86)
        let program = MacrocyclePlanner.plan(goals: [goal], now: now)

        let unwrapped = try? XCTUnwrap(program)
        XCTAssertEqual(unwrapped?.anchorGoalID, goal.id)
        XCTAssertEqual(unwrapped?.races.count, 1)
        XCTAssertEqual(unwrapped?.races.first?.isAnchor, true)
        XCTAssertNil(unwrapped?.races.first?.miniTaperStart)          // anchor uses the macrocycle taper
        XCTAssertEqual(unwrapped?.end, goal.targetDate)
        XCTAssertGreaterThan(unwrapped?.weeklyTrimpTarget ?? 0, 0)
    }

    // MARK: - Two overlapping races (the screenshot scenario)

    func testLaterRaceAnchorsTheMacrocycleEarlierIsInterim() throws {
        let haarlem   = makeGoal(title: "Halve marathon Haarlem", targetInDays: 64)
        let amsterdam = makeGoal(title: "Marathon Amsterdam", targetInDays: 86)

        let program = try XCTUnwrap(MacrocyclePlanner.plan(goals: [haarlem, amsterdam], now: now))

        // The later race anchors the program; it ends on the anchor's date.
        XCTAssertEqual(program.anchorGoalID, amsterdam.id)
        XCTAssertEqual(program.end, amsterdam.targetDate)

        // Races are sorted by date: Haarlem (interim) then Amsterdam (anchor).
        XCTAssertEqual(program.races.map(\.goalID), [haarlem.id, amsterdam.id])

        let haarlemMarker = try XCTUnwrap(program.races.first { $0.goalID == haarlem.id })
        XCTAssertFalse(haarlemMarker.isAnchor)
        XCTAssertEqual(haarlemMarker.priority, .b)
        // Interim race gets a mini-taper ending on race day.
        let expectedTaperStart = date(days: 64 - MacrocyclePlanner.miniTaperDays, from: now)
        XCTAssertEqual(haarlemMarker.miniTaperStart, expectedTaperStart)

        let amsterdamMarker = try XCTUnwrap(program.races.first { $0.goalID == amsterdam.id })
        XCTAssertTrue(amsterdamMarker.isAnchor)
        XCTAssertEqual(amsterdamMarker.priority, .a)
        XCTAssertNil(amsterdamMarker.miniTaperStart)
    }

    // MARK: - Mini-taper override of the current phase

    func testNowInsideInterimMiniTaperOverridesCurrentPhaseToTapering() throws {
        // Haarlem 2 days out → its 4-day mini-taper window [now-2, now+2) contains now.
        let haarlem   = makeGoal(title: "Halve marathon Haarlem", targetInDays: 2)
        let amsterdam = makeGoal(title: "Marathon Amsterdam", targetInDays: 30)

        let program = try XCTUnwrap(MacrocyclePlanner.plan(goals: [haarlem, amsterdam], now: now))

        XCTAssertEqual(program.anchorGoalID, amsterdam.id)
        XCTAssertTrue(program.inMiniTaper)
        XCTAssertEqual(program.currentPhase, .tapering)
    }

    func testFarFromAnyRaceIsNotInMiniTaperNorTapering() throws {
        // 86 days from the anchor and no interim race nearby → building, not tapering.
        let amsterdam = makeGoal(title: "Marathon Amsterdam", targetInDays: 86)
        let program = try XCTUnwrap(MacrocyclePlanner.plan(goals: [amsterdam], now: now))

        XCTAssertFalse(program.inMiniTaper)
        XCTAssertNotEqual(program.currentPhase, .tapering)
    }

    // MARK: - Anchor selection is priority/date driven

    func testAnchorIsAlwaysTheLatestRaceRegardlessOfInputOrder() throws {
        let early = makeGoal(title: "Early", targetInDays: 20)
        let late  = makeGoal(title: "Late", targetInDays: 120)
        let mid   = makeGoal(title: "Mid", targetInDays: 60)

        // Input order shuffled — anchor must still be the latest race.
        let program = try XCTUnwrap(MacrocyclePlanner.plan(goals: [mid, late, early], now: now))
        XCTAssertEqual(program.anchorGoalID, late.id)
        XCTAssertEqual(program.races.count, 3)
        // Every non-anchor earlier race is an interim tune-up with a mini-taper.
        let interimMarkers = program.races.filter { !$0.isAnchor }
        XCTAssertEqual(interimMarkers.count, 2)
        XCTAssertTrue(interimMarkers.allSatisfy { $0.miniTaperStart != nil })
    }
}
