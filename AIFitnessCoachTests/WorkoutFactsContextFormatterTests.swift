import XCTest
@testable import AIFitnessCoach

/// Epic #70 story 70.5: unit tests voor het [WORKOUT NOTES]-promptblok.
/// Het window/cap/ordening-beleid leeft ín de formatter, dus dat testen we hier;
/// de systemInstruction-kant van de §13-marker wordt afgedekt door
/// `CoachPromptAssemblerTests` (structuralPromptMarkers bevat nu "[WORKOUT NOTES]").
final class WorkoutFactsContextFormatterTests: XCTestCase {

    private let calendar = Calendar.current
    /// Vast referentiemoment (za 4 jul 2026, 12:00 lokale tijd) zodat week-grenzen
    /// deterministisch zijn.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: 12))!
    }

    private func item(daysAgo: Int,
                      category: WorkoutFactCategory = .feel,
                      text: String = "Voelde zwaar",
                      label: String = "Zondagrit") -> WorkoutFactsContextFormatter.Item {
        WorkoutFactsContextFormatter.Item(
            text: text,
            category: category,
            createdAt: calendar.date(byAdding: .day, value: -daysAgo, to: now)!,
            workoutLabel: label
        )
    }

    // MARK: - Window (14 dagen, Calendar-gebaseerd)

    func testEmptyInputGivesEmptyBlock() {
        XCTAssertEqual(WorkoutFactsContextFormatter.format(items: [], now: now), "")
    }

    func testFactInsideWindowIsIncluded_outsideExcluded() {
        let inside  = item(daysAgo: 13, text: "Binnen window")
        let outside = item(daysAgo: 15, text: "Buiten window")
        let block = WorkoutFactsContextFormatter.format(items: [inside, outside], now: now)

        XCTAssertTrue(block.contains("Binnen window"))
        XCTAssertFalse(block.contains("Buiten window"))
    }

    func testAllFactsOutsideWindowGivesEmptyBlock() {
        let block = WorkoutFactsContextFormatter.format(items: [item(daysAgo: 20)], now: now)
        XCTAssertEqual(block, "")
    }

    // MARK: - Structuur & ordening

    func testBlockCarriesTheStructuralMarkerAndClosingInstruction() {
        let block = WorkoutFactsContextFormatter.format(items: [item(daysAgo: 1)], now: now)
        XCTAssertTrue(block.hasPrefix("[WORKOUT NOTES"), "Structurele marker (§13) moet het blok openen")
        XCTAssertTrue(block.contains("Weigh these in plans and feedback"))
    }

    /// dayCondition-feiten van de huidige week krijgen hun eigen kop en staan vóór
    /// de overige feiten — dit is het versgeheugen voor de weekplanning.
    func testCurrentWeekDayConditionLeads() {
        let condition = item(daysAgo: 0, category: .dayCondition, text: "Slecht geslapen deze week")
        let older     = item(daysAgo: 10, category: .route, text: "Mooie route bij het meer")
        let block = WorkoutFactsContextFormatter.format(items: [older, condition], now: now)

        guard let conditionRange = block.range(of: "Slecht geslapen deze week"),
              let routeRange = block.range(of: "Mooie route bij het meer") else {
            return XCTFail("Beide feiten horen in het blok")
        }
        XCTAssertTrue(block.contains("Condition this week:"))
        XCTAssertTrue(block.contains("Workout notes:"))
        XCTAssertLessThan(conditionRange.lowerBound, routeRange.lowerBound)
    }

    /// Een dayCondition-feit van vórige week (wel in het 14-dagen-window) hoort bij
    /// de gewone notes, niet bij "Condition this week".
    func testLastWeekDayConditionIsNotInThisWeekSection() {
        let lastWeek = item(daysAgo: 9, category: .dayCondition, text: "Vorige week verkouden")
        let block = WorkoutFactsContextFormatter.format(items: [lastWeek], now: now)

        XCTAssertTrue(block.contains("Vorige week verkouden"))
        XCTAssertFalse(block.contains("Condition this week:"))
    }

    func testLineFormatContainsCategoryLabelAndDate() {
        let block = WorkoutFactsContextFormatter.format(
            items: [item(daysAgo: 2, category: .route, text: "Rondje plas beviel", label: "Zaterdagrit")],
            now: now
        )
        XCTAssertTrue(block.contains("- [route] Rondje plas beviel (Zaterdagrit, "),
                      "Regel moet categorie, tekst en workout-label dragen")
    }

    func testMissingWorkoutLabelOmitsLabelPrefix() {
        let block = WorkoutFactsContextFormatter.format(
            items: [item(daysAgo: 2, text: "Feit zonder label", label: "")],
            now: now
        )
        XCTAssertTrue(block.contains("Feit zonder label ("))
        XCTAssertFalse(block.contains(", (")) // geen lege label-komma
    }

    // MARK: - Cap

    func testCapsAtTwentyNewestFacts() {
        // 25 feiten, oplopend in leeftijd; nieuwste 20 blijven over.
        let items = (0..<25).map { index in
            item(daysAgo: 0, text: "Feit nummer \(index)")
        }.enumerated().map { offset, base -> WorkoutFactsContextFormatter.Item in
            WorkoutFactsContextFormatter.Item(
                text: base.text,
                category: base.category,
                createdAt: calendar.date(byAdding: .hour, value: -offset, to: now)!,
                workoutLabel: base.workoutLabel
            )
        }
        let block = WorkoutFactsContextFormatter.format(items: items, now: now)

        XCTAssertTrue(block.contains("Feit nummer 0"), "Nieuwste feit moet aanwezig zijn")
        XCTAssertTrue(block.contains("Feit nummer 19"))
        XCTAssertFalse(block.contains("Feit nummer 20"), "Ouder dan de cap van 20 → weggelaten")
        XCTAssertFalse(block.contains("Feit nummer 24"))
    }

    // MARK: - DST-overgang (§3: Calendar-math, geen TimeInterval)

    /// Window-filter over de zomertijd-overgang heen: een feit van 13 dagen terug
    /// over de DST-grens (29 maart 2026) blijft binnen het window.
    func testWindowSurvivesDSTTransition() {
        let dstNow = calendar.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 12))!
        let item13 = WorkoutFactsContextFormatter.Item(
            text: "Voor de klokwissel",
            category: .feel,
            createdAt: calendar.date(byAdding: .day, value: -13, to: dstNow)!,
            workoutLabel: ""
        )
        let block = WorkoutFactsContextFormatter.format(items: [item13], now: dstNow)
        XCTAssertTrue(block.contains("Voor de klokwissel"))
    }
}
