import XCTest
@testable import AIFitnessCoach

/// Epic #55 story 55.2: unit tests for the app-side synthesis of multi-day event
/// stage entries in the week schedule. Pure-Swift, no AppStorage — the builder takes
/// the week days, plan workouts and goals as parameters (CLAUDE.md §6).
final class WeekScheduleBuilderTests: XCTestCase {

    private let cal = Calendar.current

    /// Start-of-day for `today + offset`.
    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))!
    }

    /// The 7-day window the dashboard shows, starting today.
    private var weekDays: [Date] { (0..<7).map { day($0) } }

    /// A workout pinned to an exact day via `scheduledDate` (so `displayDate` is deterministic).
    private func workout(on offset: Int, type: String = "Hardlopen") -> SuggestedWorkout {
        SuggestedWorkout(
            dateOrDay: "pinned",
            activityType: type,
            suggestedDurationMinutes: 45,
            targetTRIMP: 60,
            description: "Zone 2",
            scheduledDate: day(offset)
        )
    }

    private func multiDayGoal(startOffset: Int, days: Int, title: String = "Arnhem → Karlsruhe",
                              completed: Bool = false) -> FitnessGoal {
        FitnessGoal(
            title: title,
            targetDate: day(startOffset),
            isCompleted: completed,
            format: .multiDayStage,
            eventDurationDays: days
        )
    }

    // MARK: - No events

    func test_entries_noEventGoals_returnsOnlyMatchingWorkouts() {
        let workouts = [workout(on: 0), workout(on: 2)]

        let entries = WeekScheduleBuilder.entries(for: weekDays, workouts: workouts,
                                                  eventGoals: [], calendar: cal)

        XCTAssertEqual(entries.count, 2, "Only the two days with a workout produce an entry")
        XCTAssertTrue(cal.isDate(entries[0].date, inSameDayAs: day(0)))
        XCTAssertTrue(cal.isDate(entries[1].date, inSameDayAs: day(2)))
        XCTAssertNotNil(entries[0].entry.workout)
        XCTAssertNil(entries[0].entry.stage)
    }

    // MARK: - Multi-day synthesis

    func test_entries_multiDayEvent_synthesizesStagesAcrossWindow() {
        let goal = multiDayGoal(startOffset: 1, days: 3) // days 1,2,3 are the event

        let entries = WeekScheduleBuilder.entries(for: weekDays, workouts: [],
                                                  eventGoals: [goal], calendar: cal)

        XCTAssertEqual(entries.count, 3)
        let stages = entries.compactMap { $0.entry.stage }
        XCTAssertEqual(stages.map(\.stageIndex), [1, 2, 3])
        XCTAssertTrue(stages.allSatisfy { $0.totalStages == 3 })
        XCTAssertTrue(stages.allSatisfy { $0.goalTitle == "Arnhem → Karlsruhe" })
        XCTAssertTrue(cal.isDate(entries[0].date, inSameDayAs: day(1)))
    }

    func test_entries_stageReplacesWorkoutOnEventDay() {
        // A coach workout AND an event both fall on day 1 → the stage wins (suppression).
        let goal = multiDayGoal(startOffset: 1, days: 2)
        let workouts = [workout(on: 1, type: "Krachttraining")]

        let entries = WeekScheduleBuilder.entries(for: weekDays, workouts: workouts,
                                                  eventGoals: [goal], calendar: cal)

        let day1 = entries.first { cal.isDate($0.date, inSameDayAs: day(1)) }
        XCTAssertNotNil(day1?.entry.stage, "Event day must render as a stage, not the workout")
        XCTAssertNil(day1?.entry.workout)
        XCTAssertEqual(day1?.entry.stage?.stageIndex, 1)
    }

    // MARK: - Single-day events are NOT stages

    func test_entries_singleDayEvent_notTreatedAsStage() {
        // A single-day "multiDayStage" (duration 1) is effectively a race — no stage entry.
        let goal = multiDayGoal(startOffset: 1, days: 1)
        let workouts = [workout(on: 1)]

        let entries = WeekScheduleBuilder.entries(for: weekDays, workouts: workouts,
                                                  eventGoals: [goal], calendar: cal)

        let day1 = entries.first { cal.isDate($0.date, inSameDayAs: day(1)) }
        XCTAssertNil(day1?.entry.stage, "Single-day event must not synthesize a stage")
        XCTAssertNotNil(day1?.entry.workout, "The normal workout still renders")
    }

    // MARK: - Event partially overlapping the window

    func test_entries_eventStartingBeforeWindow_keepsGlobalStageIndex() {
        // Event started yesterday (offset -1), lasts 4 days: -1, 0, 1, 2.
        // Within the visible week (today…+6) we see global stages 2, 3, 4.
        let goal = multiDayGoal(startOffset: -1, days: 4)

        let entries = WeekScheduleBuilder.entries(for: weekDays, workouts: [],
                                                  eventGoals: [goal], calendar: cal)

        let stages = entries.compactMap { $0.entry.stage }
        XCTAssertEqual(stages.map(\.stageIndex), [2, 3, 4])
        XCTAssertTrue(stages.allSatisfy { $0.totalStages == 4 })
    }

    // MARK: - Completed events are ignored

    func test_entries_completedEvent_ignored() {
        let goal = multiDayGoal(startOffset: 1, days: 3, completed: true)
        let workouts = [workout(on: 1)]

        let entries = WeekScheduleBuilder.entries(for: weekDays, workouts: workouts,
                                                  eventGoals: [goal], calendar: cal)

        XCTAssertTrue(entries.allSatisfy { $0.entry.stage == nil },
                      "A completed event must not produce stage entries")
        XCTAssertEqual(entries.count, 1, "Only the day-1 workout remains")
    }

    // MARK: - Earliest event wins on overlap

    func test_entries_overlappingEvents_earliestWins() {
        let early = multiDayGoal(startOffset: 0, days: 3, title: "Tour A")
        let late  = multiDayGoal(startOffset: 1, days: 3, title: "Tour B")

        let entries = WeekScheduleBuilder.entries(for: weekDays, workouts: [],
                                                  eventGoals: [late, early], calendar: cal)

        // Day 1 is covered by both; the earlier-starting event (Tour A) takes it.
        let day1 = entries.first { cal.isDate($0.date, inSameDayAs: day(1)) }
        XCTAssertEqual(day1?.entry.stage?.goalTitle, "Tour A")
        XCTAssertEqual(day1?.entry.stage?.stageIndex, 2, "Day 1 is Tour A's stage 2")
    }
}
