import XCTest
@testable import AIFitnessCoach

// Epic #72 story 72.1: unit tests for the deterministic GoalVerdictBuilder.
final class GoalVerdictBuilderTests: XCTestCase {
    /// Baseline input with no targets and no risk — every test tweaks this from a known state.
    private func makeInput(
        phaseWeekNumber: Int = 3,
        phaseTotalWeeks: Int = 8,
        trimpActual: Double = 0,
        trimpExpectedToDate: Double = 0,
        trimpPhaseTarget: Double = 0,
        kmActual: Double = 0,
        kmExpectedToDate: Double = 0,
        kmPhaseTarget: Double = 0,
        achievedTargetLabels: [String] = [],
        isAtRisk: Bool = false,
        isTaperingOverload: Bool = false,
        riskCurrentWeeklyRate: Double? = nil,
        riskRequiredWeeklyRate: Double? = nil
    ) -> GoalVerdictInput {
        GoalVerdictInput(
            phaseWeekNumber: phaseWeekNumber,
            phaseTotalWeeks: phaseTotalWeeks,
            trimpActual: trimpActual,
            trimpExpectedToDate: trimpExpectedToDate,
            trimpPhaseTarget: trimpPhaseTarget,
            kmActual: kmActual,
            kmExpectedToDate: kmExpectedToDate,
            kmPhaseTarget: kmPhaseTarget,
            achievedTargetLabels: achievedTargetLabels,
            isAtRisk: isAtRisk,
            isTaperingOverload: isTaperingOverload,
            riskCurrentWeeklyRate: riskCurrentWeeklyRate,
            riskRequiredWeeklyRate: riskRequiredWeeklyRate
        )
    }

    // MARK: - 1. nil vs non-nil

    func testBuildReturnsNilWhenNoTargetsAndNoRisk() {
        let input = makeInput()
        XCTAssertNil(GoalVerdictBuilder.build(input))
    }

    func testBuildReturnsNonNilWhenOnlyAtRiskIsTrue() {
        let input = makeInput(isAtRisk: true, riskCurrentWeeklyRate: 50, riskRequiredWeeklyRate: 70)
        XCTAssertNotNil(GoalVerdictBuilder.build(input))
    }

    // MARK: - 2. paceStatus boundaries

    func testPaceStatusExactlyTenPercentGapIsOnPace() {
        // expected 100, gap must be > 10 to count as behind; exactly 10 stays onPace.
        let status = GoalVerdictBuilder.paceStatus(actual: 90, expectedToDate: 100)
        XCTAssertEqual(status, .onPace)
    }

    func testPaceStatusJustOverTenPercentGapIsBehind() {
        let status = GoalVerdictBuilder.paceStatus(actual: 89.98, expectedToDate: 100)
        XCTAssertEqual(status, .behind)
    }

    func testPaceStatusExactlyTenPercentAheadIsOnPace() {
        let status = GoalVerdictBuilder.paceStatus(actual: 110, expectedToDate: 100)
        XCTAssertEqual(status, .onPace)
    }

    func testPaceStatusJustOverTenPercentAheadIsAhead() {
        let status = GoalVerdictBuilder.paceStatus(actual: 110.02, expectedToDate: 100)
        XCTAssertEqual(status, .ahead)
    }

    // MARK: - 3. expectedToDate == 0

    func testPaceStatusZeroExpectedIsOnPace() {
        XCTAssertEqual(GoalVerdictBuilder.paceStatus(actual: 5, expectedToDate: 0), .onPace)
    }

    func testBuildZeroExpectedWithPositiveTargetIsOnTrack() {
        let input = makeInput(
            trimpActual: 5,
            trimpExpectedToDate: 0,
            trimpPhaseTarget: 300
        )
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertEqual(verdict?.tone, .onTrack)
    }

    // MARK: - 4. Tone precedence

    func testToneAtRiskWinsOverBehindMetric() {
        let input = makeInput(
            trimpActual: 50,
            trimpExpectedToDate: 100,
            trimpPhaseTarget: 300,
            isAtRisk: true,
            riskCurrentWeeklyRate: 40,
            riskRequiredWeeklyRate: 80
        )
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertEqual(verdict?.tone, .atRisk)
    }

    func testToneSlightlyBehindWhenKmBehindAndTrimpOnPace() {
        let input = makeInput(
            trimpActual: 100,
            trimpExpectedToDate: 100,
            trimpPhaseTarget: 300,
            kmActual: 10,
            kmExpectedToDate: 30,
            kmPhaseTarget: 100
        )
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertEqual(verdict?.tone, .slightlyBehind)
    }

    // MARK: - 5. Full facts order and payloads

    func testFullInputFactsOrderAndPayloads() {
        let input = makeInput(
            phaseWeekNumber: 4,
            phaseTotalWeeks: 10,
            trimpActual: 100,
            trimpExpectedToDate: 155.6,
            trimpPhaseTarget: 400,
            kmActual: 20,
            kmExpectedToDate: 22,
            kmPhaseTarget: 80,
            achievedTargetLabels: ["Lange duurrit"]
        )
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertEqual(verdict?.tone, .slightlyBehind)
        XCTAssertEqual(verdict?.facts, [
            .weekContext(week: 4, totalWeeks: 10),
            .milestoneAchieved(label: "Lange duurrit"),
            .loadBehind(deltaTRIMP: 56),
            .distanceOnPace
        ])
    }

    // MARK: - 6. Delta rounding

    func testLoadBehindDeltaRounding() {
        let input = makeInput(
            trimpActual: 100.0,
            trimpExpectedToDate: 155.6,
            trimpPhaseTarget: 400
        )
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertEqual(verdict?.facts.last, .loadBehind(deltaTRIMP: 56))
    }

    func testDistanceSlightlyBehindDeltaRounding() {
        let input = makeInput(
            kmActual: 10.0,
            kmExpectedToDate: 15.6,
            kmPhaseTarget: 50
        )
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertEqual(verdict?.facts.last, .distanceSlightlyBehind(deltaKm: 6))
    }

    // MARK: - 7. weekContext clamping

    func testWeekContextClampsBelowRangeToOne() {
        let input = makeInput(phaseWeekNumber: 0, phaseTotalWeeks: 8, trimpPhaseTarget: 100)
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertEqual(verdict?.facts.first, .weekContext(week: 1, totalWeeks: 8))
    }

    func testWeekContextClampsAboveRangeToTotalWeeks() {
        let input = makeInput(phaseWeekNumber: 12, phaseTotalWeeks: 8, trimpPhaseTarget: 100)
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertEqual(verdict?.facts.first, .weekContext(week: 8, totalWeeks: 8))
    }

    func testZeroTotalWeeksProducesNoWeekContextFact() {
        let input = makeInput(phaseWeekNumber: 3, phaseTotalWeeks: 0, trimpPhaseTarget: 100)
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertFalse(verdict?.facts.contains(where: {
            if case .weekContext = $0 { return true }
            return false
        }) ?? true)
    }

    // MARK: - 8. Only first achieved label becomes a fact

    func testOnlyFirstAchievedLabelBecomesFact() {
        let input = makeInput(
            trimpPhaseTarget: 100,
            achievedTargetLabels: ["Eerste target", "Tweede target"]
        )
        let verdict = GoalVerdictBuilder.build(input)
        let milestoneFacts = verdict?.facts.filter {
            if case .milestoneAchieved = $0 { return true }
            return false
        }
        XCTAssertEqual(milestoneFacts, [.milestoneAchieved(label: "Eerste target")])
    }

    // MARK: - 8b. Absolute dead-band (§1: day-one noise)

    /// On-device repro (12 Jul 2026, 10:31): day one of a phase, nothing trained yet —
    /// expected-to-date was 31 TRIMP / 1 km, both >10% relative, and the verdict read
    /// "Slightly behind". A gap smaller than one easy session is not a deviation.
    func testDayOneSmallGapsStayOnTrack() {
        let input = makeInput(
            trimpActual: 0,
            trimpExpectedToDate: 31,
            trimpPhaseTarget: 1031,
            kmActual: 0,
            kmExpectedToDate: 1,
            kmPhaseTarget: 30
        )
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertEqual(verdict?.tone, .onTrack)
        XCTAssertEqual(verdict?.facts.contains(.loadOnPace), true)
        XCTAssertEqual(verdict?.facts.contains(.distanceOnPace), true)
    }

    func testGapPastAbsoluteFloorIsBehind() {
        // 41 TRIMP > floor 40 and > 10% of 41 expected → behind again.
        let input = makeInput(trimpActual: 0, trimpExpectedToDate: 41, trimpPhaseTarget: 1031)
        XCTAssertEqual(GoalVerdictBuilder.build(input)?.tone, .slightlyBehind)
        // 6 km > floor 5 → behind.
        let kmInput = makeInput(kmActual: 0, kmExpectedToDate: 6, kmPhaseTarget: 30)
        XCTAssertEqual(GoalVerdictBuilder.build(kmInput)?.tone, .slightlyBehind)
    }

    func testAbsoluteFloorAlsoSuppressesAheadNoise() {
        // 35 TRIMP ahead on day one (< floor 40) → still onPace, not "ahead of schedule".
        let input = makeInput(trimpActual: 66, trimpExpectedToDate: 31, trimpPhaseTarget: 1031)
        XCTAssertEqual(GoalVerdictBuilder.build(input)?.facts.contains(.loadOnPace), true)
    }

    // MARK: - 9. taperingOverload replaces offTrack

    func testTaperingOverloadReplacesOffTrack() {
        let input = makeInput(
            isAtRisk: true,
            isTaperingOverload: true,
            riskCurrentWeeklyRate: 40,
            riskRequiredWeeklyRate: 80
        )
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertEqual(verdict?.facts.last, .taperingOverload)
    }

    func testOffTrackFactWhenNotTapering() {
        let input = makeInput(
            isAtRisk: true,
            isTaperingOverload: false,
            riskCurrentWeeklyRate: 40.4,
            riskRequiredWeeklyRate: 80.6
        )
        let verdict = GoalVerdictBuilder.build(input)
        XCTAssertEqual(verdict?.facts.last, .offTrack(currentWeekly: 40, requiredWeekly: 81))
    }
}
