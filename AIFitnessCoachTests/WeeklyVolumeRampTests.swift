import XCTest
@testable import AIFitnessCoach

/// Epic #72 story 72.6 — full coverage for `WeeklyVolumeRamp`: the linear ramp from the
/// athlete's actual volume at plan start toward the blueprint's peak weekly volume, plus the
/// taper cutover and the exact trapezoid-based cumulative integral. Fixed epoch so every
/// expectation is a precomputed, pinned number.
final class WeeklyVolumeRampTests: XCTestCase {

    // MARK: - Helpers

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let calendar = Calendar.current

    private func date(days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: epoch) ?? epoch
    }

    private func date(weeks: Int) -> Date {
        date(days: weeks * 7)
    }

    // MARK: - trailingWeeklyAverage

    func testTrailingWeeklyAverage_FourValuesInsideWindow_ReturnsTotalOverFour() {
        let ref = date(days: 0)
        let values: [(date: Date, value: Double)] = [
            (date(days: -3), 10.0),
            (date(days: -10), 10.0),
            (date(days: -17), 10.0),
            (date(days: -24), 10.0)
        ]
        let result = WeeklyVolumeRamp.trailingWeeklyAverage(values: values, reference: ref, calendar: calendar)
        XCTAssertEqual(result, 10.0, accuracy: 0.01)
    }

    func testTrailingWeeklyAverage_ExcludesValueOnReferenceAndOutsideWindow() {
        let ref = date(days: 0)
        let values: [(date: Date, value: Double)] = [
            (date(days: -3), 10.0),
            (ref, 999.0),               // on reference — excluded (window is strictly before)
            (date(weeks: -5), 999.0)    // 5 weeks old — excluded (outside 4-week window)
        ]
        let result = WeeklyVolumeRamp.trailingWeeklyAverage(values: values, reference: ref, calendar: calendar)
        XCTAssertEqual(result, 2.5, accuracy: 0.01, "Alleen -3 dagen telt mee: 10 / 4 = 2.5")
    }

    func testTrailingWeeklyAverage_EmptyReturnsZero() {
        let result = WeeklyVolumeRamp.trailingWeeklyAverage(values: [], reference: date(days: 0), calendar: calendar)
        XCTAssertEqual(result, 0, accuracy: 0.01)
    }

    // MARK: - weeklyTarget

    func testWeeklyTarget_LinearRampFromStartToPeak() {
        let model = WeeklyVolumeRamp.Model(
            planStart: epoch, taperStart: date(weeks: 12),
            startWeekly: 20, peakWeekly: 55, taperFactor: 0.6
        )
        XCTAssertEqual(WeeklyVolumeRamp.weeklyTarget(at: epoch, model: model, calendar: calendar),
                       20.0, accuracy: 0.01)
        XCTAssertEqual(WeeklyVolumeRamp.weeklyTarget(at: date(weeks: 6), model: model, calendar: calendar),
                       37.5, accuracy: 0.01)
        XCTAssertEqual(WeeklyVolumeRamp.weeklyTarget(at: date(weeks: 12), model: model, calendar: calendar),
                       33.0, accuracy: 0.01, "Op taperStart geldt al peak * taperFactor")
        XCTAssertEqual(WeeklyVolumeRamp.weeklyTarget(at: date(weeks: 13), model: model, calendar: calendar),
                       33.0, accuracy: 0.01)
    }

    func testWeeklyTarget_StartAbovePeak_StaysFlatBeforeTaper() {
        let model = WeeklyVolumeRamp.Model(
            planStart: epoch, taperStart: date(weeks: 12),
            startWeekly: 60, peakWeekly: 55, taperFactor: 0.6
        )
        XCTAssertEqual(WeeklyVolumeRamp.weeklyTarget(at: epoch, model: model, calendar: calendar),
                       55.0, accuracy: 0.01, "Nooit afbouwen: flat op peakWeekly vóór de taper")
        XCTAssertEqual(WeeklyVolumeRamp.weeklyTarget(at: date(weeks: 6), model: model, calendar: calendar),
                       55.0, accuracy: 0.01)
        XCTAssertEqual(WeeklyVolumeRamp.weeklyTarget(at: date(weeks: 12), model: model, calendar: calendar),
                       33.0, accuracy: 0.01, "In de taper geldt nog steeds peak * taperFactor")
    }

    func testWeeklyTarget_DegenerateWindow_TaperStartEqualsPlanStart() {
        let model = WeeklyVolumeRamp.Model(
            planStart: epoch, taperStart: epoch,
            startWeekly: 20, peakWeekly: 55, taperFactor: 0.6
        )
        // date == planStart == taperStart: the >= taperStart check wins, so this is already taper.
        XCTAssertEqual(WeeklyVolumeRamp.weeklyTarget(at: epoch, model: model, calendar: calendar),
                       33.0, accuracy: 0.01)
    }

    // MARK: - cumulativeTarget

    func testCumulativeTarget_LinearSegmentTrapezoid() {
        let model = WeeklyVolumeRamp.Model(
            planStart: epoch, taperStart: date(weeks: 12),
            startWeekly: 20, peakWeekly: 55, taperFactor: 0.6
        )
        let result = WeeklyVolumeRamp.cumulativeTarget(from: epoch, to: date(weeks: 2), model: model, calendar: calendar)
        XCTAssertEqual(result, 45.83, accuracy: 0.01,
                       "avg(20, 25.8333) * 2 weeks = 22.9167 * 2 = 45.83")
    }

    func testCumulativeTarget_StraddlesTaperStart() {
        let model = WeeklyVolumeRamp.Model(
            planStart: epoch, taperStart: date(weeks: 12),
            startWeekly: 20, peakWeekly: 55, taperFactor: 0.6
        )
        let result = WeeklyVolumeRamp.cumulativeTarget(
            from: date(weeks: 11), to: date(weeks: 13), model: model, calendar: calendar
        )
        XCTAssertEqual(result, 86.54, accuracy: 0.01,
                       "linear avg(52.0833, 55) * 1w = 53.5417 + taper 33 * 1w = 86.54")
    }

    func testCumulativeTarget_FromNotBeforeTo_ReturnsZero() {
        let model = WeeklyVolumeRamp.Model(
            planStart: epoch, taperStart: date(weeks: 12),
            startWeekly: 20, peakWeekly: 55, taperFactor: 0.6
        )
        XCTAssertEqual(WeeklyVolumeRamp.cumulativeTarget(from: date(weeks: 2), to: date(weeks: 2), model: model, calendar: calendar),
                       0, accuracy: 0.01)
        XCTAssertEqual(WeeklyVolumeRamp.cumulativeTarget(from: date(weeks: 3), to: date(weeks: 2), model: model, calendar: calendar),
                       0, accuracy: 0.01)
    }
}
