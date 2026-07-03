import XCTest
@testable import AIFitnessCoach

/// Unit tests for `QueryWindows` (Epic #65 story 65.2).
///
/// Verifies the rolling cutoffs are Calendar-based (§3) and sized as documented, so the
/// three bounded `@Query`s stay wide enough for their real consumers.
final class QueryWindowsTests: XCTestCase {

    private let calendar = Calendar.current
    // Fixed reference so the assertions don't depend on "now".
    private let reference = Date(timeIntervalSince1970: 1_750_000_000) // 2025-06-15

    // MARK: Sizes

    func testWindowSizesMatchDocumentedConsumers() {
        // The activity window must cover the widest consumer (the 16-week burndown block).
        XCTAssertGreaterThanOrEqual(QueryWindows.activityHistoryWeeks, 16)
        XCTAssertEqual(QueryWindows.activityHistoryWeeks, 26)
        XCTAssertEqual(QueryWindows.readinessHistoryDays, 90)
        XCTAssertEqual(QueryWindows.symptomHistoryDays, 30)
    }

    // MARK: Cutoffs

    func testActivityCutoffIs26WeeksBack() {
        let cutoff = QueryWindows.activityHistoryCutoff(from: reference, calendar: calendar)
        let expected = calendar.date(byAdding: .weekOfYear, value: -26, to: reference)!
        XCTAssertEqual(cutoff, expected)
        // 26 weeks == 182 days back.
        let days = calendar.dateComponents([.day], from: cutoff, to: reference).day
        XCTAssertEqual(days, 182)
    }

    func testReadinessCutoffIs90DaysBack() {
        let cutoff = QueryWindows.readinessHistoryCutoff(from: reference, calendar: calendar)
        let expected = calendar.date(byAdding: .day, value: -90, to: reference)!
        XCTAssertEqual(cutoff, expected)
    }

    func testSymptomCutoffIs30DaysBack() {
        let cutoff = QueryWindows.symptomHistoryCutoff(from: reference, calendar: calendar)
        let expected = calendar.date(byAdding: .day, value: -30, to: reference)!
        XCTAssertEqual(cutoff, expected)
    }

    /// All cutoffs must lie strictly in the past relative to the reference.
    func testCutoffsAreInThePast() {
        XCTAssertLessThan(QueryWindows.activityHistoryCutoff(from: reference), reference)
        XCTAssertLessThan(QueryWindows.readinessHistoryCutoff(from: reference), reference)
        XCTAssertLessThan(QueryWindows.symptomHistoryCutoff(from: reference), reference)
    }
}
