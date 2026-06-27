import XCTest
@testable import AIFitnessCoach

/// Epic #62 story 62.1 — target-date lead time, title trimming and stretch-time plausibility.
final class GoalFormValidatorTests: XCTestCase {

    private var calendar: Calendar { Calendar(identifier: .gregorian) }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    // MARK: - Target date

    func testEarliestTargetDateIsSevenDaysOut() {
        let now = date(2026, 6, 1)
        let earliest = GoalFormValidator.earliestTargetDate(from: now, calendar: calendar)
        XCTAssertEqual(earliest, calendar.startOfDay(for: date(2026, 6, 8)))
    }

    func testDateExactlySevenDaysOutIsValid() {
        let now = date(2026, 6, 1)
        XCTAssertTrue(GoalFormValidator.isTargetDateValid(date(2026, 6, 8), from: now, calendar: calendar))
    }

    func testDateSixDaysOutIsInvalid() {
        let now = date(2026, 6, 1)
        XCTAssertFalse(GoalFormValidator.isTargetDateValid(date(2026, 6, 7), from: now, calendar: calendar))
    }

    func testPastDateIsInvalid() {
        let now = date(2026, 6, 1)
        XCTAssertFalse(GoalFormValidator.isTargetDateValid(date(2026, 5, 20), from: now, calendar: calendar))
    }

    func testLaterSameDaySevenDaysOutStillValid() {
        // now at 12:00, target at 00:00 seven days later → whole-day comparison passes.
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 23))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 0))!
        XCTAssertTrue(GoalFormValidator.isTargetDateValid(target, from: now, calendar: calendar))
    }

    // MARK: - Title

    func testSanitizedTitleTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(GoalFormValidator.sanitizedTitle("  Marathon\n"), "Marathon")
    }

    func testWhitespaceOnlyTitleIsInvalid() {
        XCTAssertFalse(GoalFormValidator.isTitleValid("   \n "))
    }

    func testNonEmptyTitleIsValid() {
        XCTAssertTrue(GoalFormValidator.isTitleValid("  10k PR "))
    }

    // MARK: - Stretch plausibility

    func testStretchZeroSeconds() {
        XCTAssertEqual(GoalFormValidator.stretchTimePlausibility(seconds: 0, sport: .running), .zero)
    }

    func testRunningMarathonTimeIsOk() {
        // 3:30:00 = 12600s — squarely within running's plausible band.
        XCTAssertEqual(GoalFormValidator.stretchTimePlausibility(seconds: 12600, sport: .running), .ok)
    }

    func testRunningFourMinutesIsTooFast() {
        XCTAssertEqual(GoalFormValidator.stretchTimePlausibility(seconds: 4 * 60, sport: .running), .tooFast)
    }

    func testSwimmingTwentyHoursIsTooSlow() {
        XCTAssertEqual(GoalFormValidator.stretchTimePlausibility(seconds: 20 * 3600, sport: .swimming), .tooSlow)
    }

    func testCyclingBoundsAreWiderThanRunning() {
        // 18h is too slow for running but still plausible for cycling (e.g. a long brevet).
        XCTAssertEqual(GoalFormValidator.stretchTimePlausibility(seconds: 18 * 3600, sport: .running), .tooSlow)
        XCTAssertEqual(GoalFormValidator.stretchTimePlausibility(seconds: 18 * 3600, sport: .cycling), .ok)
    }
}
