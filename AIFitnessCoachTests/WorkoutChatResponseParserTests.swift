import XCTest
@testable import AIFitnessCoach

/// Epic #70 story 70.3: unit tests for the workout-chat response parser — de
/// andere kant van het JSON-contract in `WorkoutChatScopeInstruction`.
final class WorkoutChatResponseParserTests: XCTestCase {

    private let fallback = "Kon het niet verwerken."

    // MARK: - Happy path

    func testParsesReplyAndFacts() {
        let raw = """
        {"reply": "Logisch dat het zwaar voelde na zo'n nacht.", "workoutFacts": [
            {"text": "Slecht geslapen voor deze rit", "category": "dayCondition"},
            {"text": "Route om de plas beviel goed", "category": "route"}
        ]}
        """
        let parsed = WorkoutChatResponseParser.parse(rawResponse: raw, fallbackMessage: fallback)

        XCTAssertEqual(parsed.reply, "Logisch dat het zwaar voelde na zo'n nacht.")
        XCTAssertEqual(parsed.facts.count, 2)
        XCTAssertEqual(parsed.facts.first?.category, .dayCondition)
        XCTAssertEqual(parsed.facts.last?.category, .route)
        XCTAssertEqual(parsed.facts.last?.text, "Route om de plas beviel goed")
    }

    /// Het model verpakt JSON geregeld in markdown-fences — de cleanup uit
    /// `CoachResponseParser.extractCleanJSON` moet hergebruikt zijn.
    func testParsesMarkdownFencedJSON() {
        let raw = """
        ```json
        {"reply": "Goed gedaan!", "workoutFacts": []}
        ```
        """
        let parsed = WorkoutChatResponseParser.parse(rawResponse: raw, fallbackMessage: fallback)
        XCTAssertEqual(parsed.reply, "Goed gedaan!")
        XCTAssertTrue(parsed.facts.isEmpty)
    }

    func testMissingFactsArrayIsEmptyFacts() {
        let parsed = WorkoutChatResponseParser.parse(rawResponse: #"{"reply": "Prima sessie."}"#,
                                                     fallbackMessage: fallback)
        XCTAssertEqual(parsed.reply, "Prima sessie.")
        XCTAssertTrue(parsed.facts.isEmpty)
    }

    // MARK: - Front door (§2)

    /// Onbekende categorie → dat feit valt weg, de reply en de overige feiten blijven.
    func testUnknownCategoryDropsOnlyThatFact() {
        let raw = """
        {"reply": "Oké!", "workoutFacts": [
            {"text": "Geldig feit", "category": "feel"},
            {"text": "Vreemd feit", "category": "weather"}
        ]}
        """
        let parsed = WorkoutChatResponseParser.parse(rawResponse: raw, fallbackMessage: fallback)
        XCTAssertEqual(parsed.facts.count, 1)
        XCTAssertEqual(parsed.facts.first?.text, "Geldig feit")
        XCTAssertEqual(parsed.facts.first?.category, .feel)
    }

    func testEmptyFactTextIsDropped() {
        let raw = #"{"reply": "Oké!", "workoutFacts": [{"text": "   ", "category": "feel"}]}"#
        let parsed = WorkoutChatResponseParser.parse(rawResponse: raw, fallbackMessage: fallback)
        XCTAssertTrue(parsed.facts.isEmpty)
    }

    // MARK: - Fallbacks

    /// Geen decodebare JSON → de volledige ruwe tekst wordt de reply (de coach-reply
    /// mag nooit sneuvelen op een JSON-hikje), zonder feiten.
    func testNonJSONFallsBackToPlainReply() {
        let raw = "Gewoon een tekstueel antwoord zonder JSON."
        let parsed = WorkoutChatResponseParser.parse(rawResponse: raw, fallbackMessage: fallback)
        XCTAssertEqual(parsed.reply, raw)
        XCTAssertTrue(parsed.facts.isEmpty)
    }

    func testNilResponseUsesFallbackMessage() {
        let parsed = WorkoutChatResponseParser.parse(rawResponse: nil, fallbackMessage: fallback)
        XCTAssertEqual(parsed.reply, fallback)
        XCTAssertTrue(parsed.facts.isEmpty)
    }

    func testEmptyReplyUsesFallbackMessage() {
        let parsed = WorkoutChatResponseParser.parse(rawResponse: #"{"reply": "  "}"#,
                                                     fallbackMessage: fallback)
        XCTAssertEqual(parsed.reply, fallback)
    }
}
