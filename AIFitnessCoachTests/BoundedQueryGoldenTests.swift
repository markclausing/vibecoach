import XCTest
@testable import AIFitnessCoach

/// Golden-value tests for the bounded `@Query` windows (Epic #65 story 65.2).
///
/// The views themselves aren't unit-testable (§6), so these tests exercise the pure
/// calculation seams: they assert that filtering the activity history to
/// `QueryWindows.activityHistoryCutoff` yields **identical aggregates** to the full,
/// unbounded set for the in-window data — i.e. the out-of-window records never
/// contributed to the numbers the dashboard/goals views show, so bounding is safe.
final class BoundedQueryGoldenTests: XCTestCase {

    private let calendar = Calendar.current

    private func makeRun(weeksAgo: Int, trimp: Double) -> ActivityRecord {
        let date = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date())!
        return ActivityRecord(
            id: UUID().uuidString,
            name: "Duurloop",
            distance: 12_000,
            movingTime: 3600,
            averageHeartrate: 150,
            sportCategory: .running,
            startDate: date,
            trimp: trimp
        )
    }

    // MARK: - Dashboard TRIMP aggregates

    /// The dashboard's `chronicTRIMPPerSession` (14d) and `currentWeekTRIMP` (7d) filters
    /// live well inside the 26-week window, so windowing must not change their inputs.
    func testActivityWindowPreservesRecentTrimpAggregates() {
        let now = Date()
        let inWindow = [
            makeRun(weeksAgo: 1, trimp: 80),
            makeRun(weeksAgo: 2, trimp: 100),
            makeRun(weeksAgo: 10, trimp: 60)
        ]
        let outOfWindow = [
            makeRun(weeksAgo: 40, trimp: 500),
            makeRun(weeksAgo: 60, trimp: 300)
        ]
        let all = inWindow + outOfWindow

        let cutoff = QueryWindows.activityHistoryCutoff(from: now, calendar: calendar)
        let windowed = all.filter { $0.startDate >= cutoff }

        // The 26-week window drops exactly the two ancient records.
        XCTAssertEqual(windowed.count, inWindow.count)

        func trimpSum(_ records: [ActivityRecord], daysBack: Int) -> Double {
            let c = calendar.date(byAdding: .day, value: -daysBack, to: now)!
            return records.filter { $0.startDate >= c }.compactMap { $0.trimp }.reduce(0, +)
        }

        XCTAssertEqual(trimpSum(all, daysBack: 14), trimpSum(windowed, daysBack: 14),
                       "14-day chronic-load sum unchanged by windowing")
        XCTAssertEqual(trimpSum(all, daysBack: 7), trimpSum(windowed, daysBack: 7),
                       "7-day weekly-load sum unchanged by windowing")
    }

    // MARK: - PeriodizationEngine

    /// `PeriodizationEngine` only looks back ≤ 4 weeks (+ its session window), all inside
    /// the 26-week bound, so its output must be byte-identical for full vs windowed input.
    func testPeriodizationOutputUnchangedByWindowing() {
        let target = calendar.date(byAdding: .weekOfYear, value: 8, to: Date())!
        let goal = FitnessGoal(
            title: "Marathon",
            targetDate: target,
            sportCategory: .running,
            format: .singleDayRace,
            intent: .peakPerformance
        )

        let recent = (1...3).map { makeRun(weeksAgo: $0, trimp: 90) }
        let ancient = (40...42).map { makeRun(weeksAgo: $0, trimp: 400) }
        let full = recent + ancient

        let cutoff = QueryWindows.activityHistoryCutoff()
        let windowed = full.filter { $0.startDate >= cutoff }
        XCTAssertEqual(windowed.count, recent.count, "Ancient records fall outside the window")

        let fullResult = PeriodizationEngine.evaluateAllGoals([goal], activities: full)
        let windowedResult = PeriodizationEngine.evaluateAllGoals([goal], activities: windowed)

        XCTAssertEqual(fullResult.count, windowedResult.count)
        XCTAssertEqual(fullResult.first?.coachingContext, windowedResult.first?.coachingContext,
                       "Periodization coaching context identical before/after windowing")
        XCTAssertEqual(fullResult.first?.isOnTrack, windowedResult.first?.isOnTrack)
    }
}
