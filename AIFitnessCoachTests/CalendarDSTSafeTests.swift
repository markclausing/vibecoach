import XCTest
@testable import AIFitnessCoach

/// CLAUDE.md §3 — borgt dat datum-/weken-berekeningen DST-veilig zijn.
///
/// Achtergrond: zomertijd-overgangen maken een dag 23 of 25 uur, en een week dus
/// 167 of 169 uur. Ruwe `TimeInterval`-wiskunde (delen door 86 400 of 7 × 86 400)
/// produceert dan off-by-one fouten in weken/dagen-tellers. Deze tests gebruiken
/// een Europe/Amsterdam Calendar om beide DST-grenzen (eind oktober en eind maart)
/// te valideren.
final class CalendarDSTSafeTests: XCTestCase {

    private var amsterdamCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return cal
    }

    // MARK: - DST-grens eind oktober (zomertijd → wintertijd, dag = 25 uur)

    func test_fractionalDays_overOctoberDSTBoundary_returnsExactInteger() {
        // Span: 2026-10-20 12:00 → 2026-10-27 12:00 (kruist 2026-10-25 DST-eind)
        let cal = amsterdamCalendar
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        let end   = cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!

        let days = cal.fractionalDays(from: start, to: end)

        // Ruwe TimeInterval / 86 400 zou ~7.0417 geven (7 dagen + 1 extra uur).
        // Calendar-gebaseerd moet exact 7 dagen zijn.
        XCTAssertEqual(days, 7.0, accuracy: 0.001,
                       "fractionalDays moet kalender-dagen tellen, geen 86400-seconden-blokken.")
    }

    func test_fractionalWeeks_overOctoberDSTBoundary_returnsExactOne() {
        let cal = amsterdamCalendar
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9))!
        let end   = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 9))!

        let weeks = cal.fractionalWeeks(from: start, to: end)

        XCTAssertEqual(weeks, 1.0, accuracy: 0.001,
                       "Een kalender-week over DST-eind moet exact 1.0 weken zijn (niet 1.006).")
    }

    func test_wholeDays_overOctoberDSTBoundary_isExact() {
        let cal = amsterdamCalendar
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 0))!
        let end   = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 0))!

        XCTAssertEqual(cal.wholeDays(from: start, to: end), 14)
    }

    // MARK: - DST-grens eind maart (wintertijd → zomertijd, dag = 23 uur)

    func test_fractionalDays_overMarchDSTBoundary_returnsExactInteger() {
        let cal = amsterdamCalendar
        let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 25, hour: 12))!
        let end   = cal.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 12))!

        let days = cal.fractionalDays(from: start, to: end)

        // Ruwe TimeInterval / 86 400 zou ~6.958 geven (7 dagen − 1 uur).
        XCTAssertEqual(days, 7.0, accuracy: 0.001,
                       "fractionalDays mag niet onder 7 zakken bij overgang naar zomertijd.")
    }

    func test_fractionalWeeks_overMarchDSTBoundary_returnsExactOne() {
        let cal = amsterdamCalendar
        let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 22, hour: 9))!
        let end   = cal.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 9))!

        let weeks = cal.fractionalWeeks(from: start, to: end)

        XCTAssertEqual(weeks, 1.0, accuracy: 0.001)
    }

    // MARK: - Negatief / nul-spans

    func test_fractionalDays_endBeforeStart_isNegative() {
        let cal = amsterdamCalendar
        let later  = cal.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let earlier = cal.date(from: DateComponents(year: 2026, month: 5, day: 3))!

        XCTAssertEqual(cal.fractionalDays(from: later, to: earlier), -7.0, accuracy: 0.001)
    }

    func test_fractionalDays_sameMoment_isZero() {
        let cal = amsterdamCalendar
        let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14))!
        XCTAssertEqual(cal.fractionalDays(from: date, to: date), 0.0)
    }

    // MARK: - FitnessGoal-integratie

    func test_fitnessGoal_weeksRemaining_overOctoberDST_isExact() {
        let cal = amsterdamCalendar
        let now    = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        let target = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!

        let goal = FitnessGoal(title: "DST-test", targetDate: target, createdAt: now)

        // Met `Calendar.current` is dit timezone-afhankelijk; we testen daarom via de helper direct.
        let weeks = cal.fractionalWeeks(from: now, to: goal.targetDate)
        XCTAssertEqual(weeks, 2.0, accuracy: 0.001,
                       "Twee kalenderweken over DST-eind mogen geen 2.006 worden.")
    }
}
