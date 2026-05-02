import XCTest
@testable import AIFitnessCoach

/// Epic 45 Story 45.1 — `WorkoutHistoryContextBuilder`.
/// Borgt:
///  • Lege entries → empty string (caller skipt het hele blok)
///  • Sortering nieuwste→oudste, ongeacht input-volgorde
///  • Alle velden komen correct in één regel (datum, sport, sessieType, duur, TRIMP, HR, power, patronen)
///  • Patroon-suffix verschijnt alleen wanneer er patronen zijn
///  • Optionele velden (sessieType, power) worden weggelaten zonder lege separators of crash
final class WorkoutHistoryContextBuilderTests: XCTestCase {

    // MARK: - Helpers

    /// Vaste referentie-datum (1 mei 2026 12:00 UTC) zodat alle tests determinisch
    /// blijven, ongeacht wanneer ze draaien.
    private let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 1
        components.hour = 12
        components.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private func date(daysBefore offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -offset, to: referenceDate)!
    }

    private func makePattern(kind: WorkoutPatternKind,
                             severity: WorkoutPattern.Severity,
                             detail: String) -> WorkoutPattern {
        let now = Date()
        return WorkoutPattern(
            kind: kind,
            severity: severity,
            range: now ... now.addingTimeInterval(60),
            value: 7.0,
            detail: detail
        )
    }

    private func makeEntry(daysAgo: Int = 0,
                           name: String = "Workout",
                           sport: SportCategory = .running,
                           sessionType: SessionType? = .endurance,
                           movingTime: Int = 3600,
                           trimp: Double? = 80,
                           hr: Double? = 150,
                           power: Double? = nil,
                           patterns: [WorkoutPattern] = []) -> WorkoutHistoryContextBuilder.WorkoutEntry {
        WorkoutHistoryContextBuilder.WorkoutEntry(
            startDate: date(daysBefore: daysAgo),
            displayName: name,
            sportCategory: sport,
            sessionType: sessionType,
            movingTime: movingTime,
            trimp: trimp,
            averageHeartrate: hr,
            averagePower: power,
            patterns: patterns
        )
    }

    // MARK: - Tests

    func testEmptyEntriesReturnsEmptyString() {
        XCTAssertEqual(WorkoutHistoryContextBuilder.build(entries: []), "")
    }

    func testSortsNewestFirst() {
        let oldest = makeEntry(daysAgo: 10, name: "Oldest")
        let middle = makeEntry(daysAgo: 5, name: "Middle")
        let newest = makeEntry(daysAgo: 1, name: "Newest")

        let output = WorkoutHistoryContextBuilder.build(entries: [middle, oldest, newest])
        let lines = output.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 3)
        // De builder kent de displayName niet als eigen segment — controle via datum.
        // 1 mei 2026 minus N dagen: -1 = 30 apr, -5 = 26 apr, -10 = 21 apr.
        XCTAssertTrue(lines[0].contains("30 apr"), "Eerste regel moet de meest recente zijn (30 apr): \(lines[0])")
        XCTAssertTrue(lines[1].contains("26 apr"), "Middelste regel: \(lines[1])")
        XCTAssertTrue(lines[2].contains("21 apr"), "Laatste regel moet de oudste zijn: \(lines[2])")
    }

    func testFormatsAllFieldsForEntryWithPatterns() {
        let pattern1 = makePattern(kind: .cardiacDrift, severity: .significant,
                                   detail: "drift 8.2% Z3-Z4")
        let pattern2 = makePattern(kind: .aerobicDecoupling, severity: .moderate,
                                   detail: "Pa:HR 6.1%")
        let entry = makeEntry(
            daysAgo: 2,
            name: "Threshold Ride",
            sport: .cycling,
            sessionType: .threshold,
            movingTime: 3120,    // 52 min
            trimp: 78,
            hr: 162,
            power: 215,
            patterns: [pattern1, pattern2]
        )

        let output = WorkoutHistoryContextBuilder.build(entries: [entry])

        XCTAssertTrue(output.hasPrefix("- "), "Regel moet beginnen met '- '")
        XCTAssertTrue(output.contains("29 apr"), "Datum-segment ontbreekt: \(output)")
        XCTAssertTrue(output.contains("Wielrennen"), "Sport-displayName ontbreekt: \(output)")
        XCTAssertTrue(output.contains("Drempel"), "SessieType-displayName ontbreekt: \(output)")
        XCTAssertTrue(output.contains("52 min"), "Duur-segment ontbreekt: \(output)")
        XCTAssertTrue(output.contains("TRIMP 78"), "TRIMP-segment ontbreekt: \(output)")
        XCTAssertTrue(output.contains("gem-HR 162"), "HR-segment ontbreekt: \(output)")
        XCTAssertTrue(output.contains("gem-W 215"), "Power-segment ontbreekt: \(output)")
        XCTAssertTrue(output.contains("[SIGNIFICANT] cardiac_drift"), "Eerste patroon-token ontbreekt: \(output)")
        XCTAssertTrue(output.contains("[MODERATE] aerobic_decoupling"), "Tweede patroon-token ontbreekt: \(output)")
        XCTAssertTrue(output.contains(" — "), "Patroon-suffix-separator (em-dash) ontbreekt: \(output)")
        XCTAssertTrue(output.contains(" / "), "Patroon-inline-separator ontbreekt: \(output)")
    }

    func testEntryWithoutPatternsHasNoSuffix() {
        let entry = makeEntry(daysAgo: 3, patterns: [])
        let output = WorkoutHistoryContextBuilder.build(entries: [entry])

        XCTAssertFalse(output.contains(" — "), "Regel zonder patronen mag geen em-dash-suffix hebben: \(output)")
        XCTAssertFalse(output.contains("["), "Regel zonder patronen mag geen severity-token bevatten: \(output)")
    }

    func testNilSessionTypeAndNilPowerOmitsBothSegments() {
        let entry = makeEntry(
            daysAgo: 4,
            sessionType: nil,
            movingTime: 1800,
            trimp: 40,
            hr: 130,
            power: nil,
            patterns: []
        )
        let output = WorkoutHistoryContextBuilder.build(entries: [entry])

        XCTAssertFalse(output.contains("Onbepaald"), "SessieType-fallback 'Onbepaald' mag niet verschijnen: \(output)")
        XCTAssertFalse(output.contains("gem-W"), "Power-segment mag niet verschijnen bij nil: \(output)")
        XCTAssertFalse(output.contains("··"), "Lege segment-separator (dubbele middle-dot) mag niet voorkomen: \(output)")
        // Sanity: de regel moet nog steeds wél de overige velden bevatten.
        XCTAssertTrue(output.contains("Hardlopen"))
        XCTAssertTrue(output.contains("30 min"))
        XCTAssertTrue(output.contains("TRIMP 40"))
        XCTAssertTrue(output.contains("gem-HR 130"))
    }
}
