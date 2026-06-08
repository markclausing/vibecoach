import XCTest
@testable import AIFitnessCoach

/// Epic #56 story 56.1: unit tests for multilingual route extraction from goal text.
final class RouteParserTests: XCTestCase {

    private func assertRoute(_ text: String, _ start: String, _ end: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let r = RouteParser.parse(text) else {
            return XCTFail("Expected a route in '\(text)'", file: file, line: line)
        }
        XCTAssertEqual(r.start, start, "start of '\(text)'", file: file, line: line)
        XCTAssertEqual(r.end, end, "end of '\(text)'", file: file, line: line)
    }

    // MARK: - Happy paths (NL/EN/DE/ES)

    func test_dutch_withActivityAndTrailingDays() {
        assertRoute("Fietsen van Arnhem naar Karlsruhe in 5 dagen", "Arnhem", "Karlsruhe")
    }

    func test_dutch_plain() {
        assertRoute("van Amsterdam naar Parijs", "Amsterdam", "Parijs")
    }

    func test_dutch_fietstochtAndStages() {
        assertRoute("Fietstocht van Nijmegen naar Keulen in 3 etappes", "Nijmegen", "Keulen")
    }

    func test_english() {
        assertRoute("from London to Paris", "London", "Paris")
    }

    func test_english_doesNotSplitOnSpanishA() {
        // "to" must win over the greedy Spanish "a".
        assertRoute("Ride from Asten to Berlin", "Asten", "Berlin")
    }

    func test_german() {
        assertRoute("Radtour von Berlin nach München", "Berlin", "München")
    }

    func test_spanish_withDeContext() {
        assertRoute("de Madrid a Sevilla", "Madrid", "Sevilla")
    }

    func test_arrowSeparator() {
        assertRoute("Arnhem → Karlsruhe in 5 dagen", "Arnhem", "Karlsruhe")
    }

    func test_hyphenSeparator() {
        assertRoute("Arnhem - Karlsruhe", "Arnhem", "Karlsruhe")
    }

    // MARK: - Negative paths

    func test_noConnector_returnsNil() {
        XCTAssertNil(RouteParser.parse("Marathon Rotterdam"))
    }

    func test_tourDeFrance_doesNotFalseMatchOnSpanishA() {
        // "de" present but no standalone "a" → no route.
        XCTAssertNil(RouteParser.parse("Tour de France"))
    }

    func test_empty_returnsNil() {
        XCTAssertNil(RouteParser.parse(""))
    }

    func test_multiWordPlaceNames() {
        assertRoute("van Den Haag naar Frankfurt am Main", "Den Haag", "Frankfurt am Main")
    }
}
