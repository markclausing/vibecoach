import XCTest
@testable import AIFitnessCoach

/// Epic #51-A1: borgt dat de scope-instructie in de system-prompt blijft staan.
/// De feitelijke gehoorzaamheid van het AI-model laten we aan integratie-testen
/// op device — deze unit-tests valideren alleen dat de tekst aanwezig is, de
/// kernregels noemt, en niet stilletjes wordt weggehaald in een toekomstige
/// refactor van het prompt-blok.
final class ChatScopeInstructionTests: XCTestCase {

    func testScopeInstructionIsNonEmpty() {
        XCTAssertFalse(ChatScopeInstruction.text.isEmpty)
    }

    /// Verifieert dat de scope-regel expliciet "fitness-coach"-positionering
    /// noemt — dit is het kernsignaal voor het model.
    func testScopeMentionsFitnessCoach() {
        XCTAssertTrue(ChatScopeInstruction.text.lowercased().contains("fitness-coach"))
    }

    /// De instructie moet een EXPLICIETE weigerings-framing bevatten. Zonder
    /// dit zou het model off-topic-vragen alsnog beantwoorden — precies de
    /// situatie die we willen voorkomen.
    func testScopeIncludesRefusalFramingForOffTopic() {
        let text = ChatScopeInstruction.text.lowercased()
        XCTAssertTrue(
            text.contains("buiten mijn scope") || text.contains("scope"),
            "Scope-framing moet expliciet zijn — anders glipt off-topic alsnog door."
        )
    }

    /// De toegestane onderwerpen-lijst moet de kern-coaching-categorieën
    /// noemen zodat het model weet wat WEL onder scope valt.
    func testScopeLisstInScopeCategories() {
        // Epic #37 deel 5: the scope instruction is now in English; the user-facing
        // refusal phrase + exception example stay Dutch. Assert on the English category labels.
        let text = ChatScopeInstruction.text.lowercased()
        for keyword in ["workouts", "recovery", "injuries", "sport goals"] {
            XCTAssertTrue(text.contains(keyword), "Scope moet '\(keyword)' expliciet toelaten als coaching-onderwerp.")
        }
    }

    /// De uitzonderingsclausule voor sport-gerelateerde "off-topic" vragen
    /// (bijv. "kan ik trainen met deze hoofdpijn?") moet erin staan zodat
    /// de coach niet te streng wordt en relevante vragen alsnog beantwoordt.
    func testScopeIncludesTrainingContextException() {
        XCTAssertTrue(ChatScopeInstruction.text.lowercased().contains("exception"))
    }
}
