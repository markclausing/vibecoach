import XCTest
@testable import AIFitnessCoach

/// Unit tests voor `WorkoutAnalysisHelpers` (Epic 32 Story 32.2).
final class WorkoutAnalysisHelpersTests: XCTestCase {

    private struct TestSample {
        let timestamp: Date
        let label: String
    }

    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - nearestSample

    func testNearestSamplePicksClosestTimestamp() {
        let samples = [
            TestSample(timestamp: baseDate.addingTimeInterval(0),  label: "a"),
            TestSample(timestamp: baseDate.addingTimeInterval(10), label: "b"),
            TestSample(timestamp: baseDate.addingTimeInterval(20), label: "c"),
        ]

        // 4s na start → dichtstbij is 'a' (delta 4 vs 6 vs 16)
        let near0 = WorkoutAnalysisHelpers.nearestSample(at: baseDate.addingTimeInterval(4),
                                                        in: samples,
                                                        timestamp: \.timestamp)
        XCTAssertEqual(near0?.label, "a")

        // 13s na start → dichtstbij is 'b' (delta 3 vs 7 vs 7)
        let nearMid = WorkoutAnalysisHelpers.nearestSample(at: baseDate.addingTimeInterval(13),
                                                          in: samples,
                                                          timestamp: \.timestamp)
        XCTAssertEqual(nearMid?.label, "b")
    }

    func testNearestSampleHandlesTimestampBeforeFirstAndAfterLast() {
        let samples = [
            TestSample(timestamp: baseDate.addingTimeInterval(0),  label: "first"),
            TestSample(timestamp: baseDate.addingTimeInterval(60), label: "last"),
        ]

        // Ver vóór eerste sample → klemt naar 'first'
        let before = WorkoutAnalysisHelpers.nearestSample(at: baseDate.addingTimeInterval(-1000),
                                                         in: samples,
                                                         timestamp: \.timestamp)
        XCTAssertEqual(before?.label, "first")

        // Ver na laatste sample → klemt naar 'last'
        let after = WorkoutAnalysisHelpers.nearestSample(at: baseDate.addingTimeInterval(10_000),
                                                        in: samples,
                                                        timestamp: \.timestamp)
        XCTAssertEqual(after?.label, "last")
    }

    func testNearestSampleEmptyArrayReturnsNil() {
        let result = WorkoutAnalysisHelpers.nearestSample(at: baseDate,
                                                          in: [TestSample](),
                                                          timestamp: \.timestamp)
        XCTAssertNil(result)
    }

    // MARK: - chooseSecondarySeries

    func testCyclingWithPowerPrefersPower() {
        let result = WorkoutAnalysisHelpers.chooseSecondarySeries(sportCategory: "cycling",
                                                                  hasSpeed: true,
                                                                  hasPower: true)
        XCTAssertEqual(result, .power)
    }

    func testRunningWithSpeedPrefersSpeed() {
        let result = WorkoutAnalysisHelpers.chooseSecondarySeries(sportCategory: "running",
                                                                  hasSpeed: true,
                                                                  hasPower: false)
        XCTAssertEqual(result, .speed)
    }

    func testCyclingWithoutPowerFallsBackToSpeed() {
        let result = WorkoutAnalysisHelpers.chooseSecondarySeries(sportCategory: "cycling",
                                                                  hasSpeed: true,
                                                                  hasPower: false)
        XCTAssertEqual(result, .speed)
    }

    func testNoDataReturnsNone() {
        let result = WorkoutAnalysisHelpers.chooseSecondarySeries(sportCategory: "running",
                                                                  hasSpeed: false,
                                                                  hasPower: false)
        XCTAssertEqual(result, .none)
    }

    func testStrengthWithOnlyPowerStillReturnsPower() {
        // Edge: een powermeter buiten cycling — we tonen liever íets dan niets.
        let result = WorkoutAnalysisHelpers.chooseSecondarySeries(sportCategory: "strength",
                                                                  hasSpeed: false,
                                                                  hasPower: true)
        XCTAssertEqual(result, .power)
    }
}
