import XCTest
@testable import AIFitnessCoach

/// Epic #55 story 55.3: unit tests for the multi-day event-window prompt block and the
/// defensive `resolvedFormat`/`resolvedIntent` fix. Pure-Swift, no AppStorage (§6).
final class EventWindowContextFormatterTests: XCTestCase {

    private let cal = Calendar.current

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))!
    }

    private func goal(startOffset: Int, days: Int?, title: String = "Arnhem → Karlsruhe",
                      format: EventFormat? = .multiDayStage, intent: PrimaryIntent? = .completion,
                      completed: Bool = false) -> FitnessGoal {
        FitnessGoal(
            title: title,
            targetDate: day(startOffset),
            isCompleted: completed,
            format: format,
            intent: intent,
            eventDurationDays: days
        )
    }

    // MARK: - Empty / negative paths

    func test_format_noGoals_returnsEmpty() {
        XCTAssertEqual(EventWindowContextFormatter.format(goals: []), "")
    }

    func test_format_singleDayEvent_returnsEmpty() {
        // duration 1 = effectively single-day → not an event window.
        let g = goal(startOffset: 3, days: 1)
        XCTAssertEqual(EventWindowContextFormatter.format(goals: [g]), "")
    }

    func test_format_eventBeyondHorizon_returnsEmpty() {
        let g = goal(startOffset: 30, days: 5) // a month away
        XCTAssertEqual(EventWindowContextFormatter.format(goals: [g]), "")
    }

    func test_format_completedEvent_returnsEmpty() {
        let g = goal(startOffset: 2, days: 5, completed: true)
        XCTAssertEqual(EventWindowContextFormatter.format(goals: [g]), "")
    }

    func test_format_fullyPastEvent_returnsEmpty() {
        // Ended well in the past, recovery tail also gone.
        let g = goal(startOffset: -20, days: 3)
        XCTAssertEqual(EventWindowContextFormatter.format(goals: [g]), "")
    }

    // MARK: - Happy path

    func test_format_upcomingMultiDayEvent_includesWindowAndRules() {
        let g = goal(startOffset: 2, days: 5)
        let out = EventWindowContextFormatter.format(goals: [g])

        XCTAssertTrue(out.contains("EVENT WINDOW"))
        XCTAssertTrue(out.contains("Arnhem → Karlsruhe"))
        XCTAssertTrue(out.contains("5 consecutive event days"))
        XCTAssertTrue(out.contains("PLAN NO OTHER TRAINING"))
        XCTAssertTrue(out.contains("IGNORE FIXED PREFERENCES"))
        XCTAssertTrue(out.contains("CROSS-GOAL SUPPRESSION"))
        XCTAssertTrue(out.contains("PLAN RECOVERY FIRST"))
        XCTAssertTrue(out.contains("NOT a race"))
    }

    func test_format_usesISODatesForStartAndEnd() {
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"
        let start = day(1), end = day(3) // 3-day event spanning day1..day3

        let g = goal(startOffset: 1, days: 3)
        let out = EventWindowContextFormatter.format(goals: [g])

        XCTAssertTrue(out.contains(iso.string(from: start)), "start date present")
        XCTAssertTrue(out.contains(iso.string(from: end)), "end date present")
    }

    func test_format_recoveryDaysScaleWithDuration() {
        XCTAssertEqual(EventWindowContextFormatter.recoveryDays(for: 2), 1)
        XCTAssertEqual(EventWindowContextFormatter.recoveryDays(for: 3), 2)
        XCTAssertEqual(EventWindowContextFormatter.recoveryDays(for: 5), 3)
        XCTAssertEqual(EventWindowContextFormatter.recoveryDays(for: 10), 3, "capped at 3")
    }

    func test_format_ongoingEvent_stillIncluded() {
        // Started yesterday, 4 days → still ongoing today.
        let g = goal(startOffset: -1, days: 4)
        let out = EventWindowContextFormatter.format(goals: [g])
        XCTAssertTrue(out.contains("EVENT WINDOW"))
    }

    func test_format_justEndedEvent_recoveryTailStillIncluded() {
        // 3-day event that ended yesterday → recovery (2 days) still relevant today.
        let g = goal(startOffset: -3, days: 3)
        let out = EventWindowContextFormatter.format(goals: [g])
        XCTAssertTrue(out.contains("PLAN RECOVERY FIRST"))
    }

    func test_format_multipleEvents_bothBlocksPresentSortedByStart() {
        let later = goal(startOffset: 8, days: 2, title: "Tour B")
        let sooner = goal(startOffset: 1, days: 2, title: "Tour A")
        let out = EventWindowContextFormatter.format(goals: [later, sooner])

        let idxA = out.range(of: "Tour A")
        let idxB = out.range(of: "Tour B")
        XCTAssertNotNil(idxA)
        XCTAssertNotNil(idxB)
        XCTAssertTrue(idxA!.lowerBound < idxB!.lowerBound, "earliest event listed first")
    }

    // MARK: - resolvedFormat / resolvedIntent defensive fix

    func test_resolvedFormat_multiDayWithNilFormat_treatedAsStage() {
        let g = goal(startOffset: 2, days: 5, format: nil, intent: nil)
        XCTAssertEqual(g.resolvedFormat, .multiDayStage, "duration > 1 overrides a missing format")
    }

    func test_resolvedIntent_multiDayWithNilIntent_defaultsToCompletion() {
        let g = goal(startOffset: 2, days: 5, format: nil, intent: nil)
        XCTAssertEqual(g.resolvedIntent, .completion)
    }

    func test_resolvedIntent_explicitIntentRespected() {
        let g = goal(startOffset: 2, days: 5, format: .multiDayStage, intent: .peakPerformance)
        XCTAssertEqual(g.resolvedIntent, .peakPerformance, "an explicit intent is never overridden")
    }

    func test_resolvedFormat_singleDay_unchanged() {
        let g = goal(startOffset: 2, days: 1, format: nil, intent: nil)
        XCTAssertEqual(g.resolvedFormat, .singleDayRace, "single-day still falls back to race")
        XCTAssertEqual(g.resolvedIntent, .peakPerformance)
    }
}
