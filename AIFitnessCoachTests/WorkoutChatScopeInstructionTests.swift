import XCTest
@testable import AIFitnessCoach

/// Epic #70 story 70.2: borgt dat de workout-chat-scope-instructie aanwezig blijft
/// en het JSON-contract met `WorkoutChatResponseParser` niet stilletjes wijzigt.
/// Net als bij `ChatScopeInstructionTests` valideren we tekst-aanwezigheid; de
/// feitelijke gehoorzaamheid van het model is on-device-validatie (PR-checklist).
final class WorkoutChatScopeInstructionTests: XCTestCase {

    private func makeText(sessionTypeLabel: String? = "Recovery") -> String {
        WorkoutChatScopeInstruction.text(
            workoutName: "Zondagrit",
            workoutDate: Date(timeIntervalSince1970: 1_751_200_000), // 29 jun 2025
            sportRaw: "cycling",
            sessionTypeLabel: sessionTypeLabel
        )
    }

    // MARK: - Workout anchoring

    /// De instructie moet het model aan déze workout verankeren — naam, sport en
    /// datum geïnterpoleerd, anders drijft het gesprek af naar algemene coaching.
    func testInterpolatesWorkoutIdentity() {
        let text = makeText()
        XCTAssertTrue(text.contains("Zondagrit"))
        XCTAssertTrue(text.contains("cycling"))
        XCTAssertTrue(text.contains("Recovery"))
        // Prompt date formatter is nl_NL (§13): month name "jun"/"juni" expected.
        XCTAssertTrue(text.lowercased().contains("jun"), "Prompt-datum (nl_NL) moet geïnterpoleerd zijn")
    }

    func testOmitsSessionTypeWhenUnknown() {
        let text = makeText(sessionTypeLabel: nil)
        XCTAssertFalse(text.contains("session type:"))
    }

    // MARK: - Scope & redirect

    /// De redirect naar het Coach-tabblad is de kern van de guardrail: plan- en
    /// doelvragen moeten via één plek blijven lopen.
    func testIncludesRedirectTemplateToCoachTab() {
        let text = makeText()
        XCTAssertTrue(text.contains("Coach-tabblad"), "Redirect-template naar de Coach-tab ontbreekt")
        XCTAssertTrue(text.contains("Do NOT attempt to answer the off-topic question"))
    }

    /// Beide toegestane scopes moeten expliciet benoemd zijn: deze workout én de
    /// gesteldheid van vandaag/deze week.
    func testListsBothAllowedScopes() {
        let text = makeText()
        XCTAssertTrue(text.contains("THIS workout"))
        XCTAssertTrue(text.contains("today or this week"))
    }

    /// De uitzonderingsclausule voorkomt dat de coach te streng wordt voor
    /// indirect relevante opmerkingen (schoenen, werkstress).
    func testIncludesExceptionClause() {
        XCTAssertTrue(makeText().contains("Exception:"))
    }

    // MARK: - JSON contract (the parser is the other side — keep in sync)

    /// Het JSON-contract moet beide sleutels + alle drie categorie-literals bevatten.
    /// `WorkoutChatResponseParser` decodeert exact dit formaat; een rename hier
    /// zonder parser-update is een stille distillatie-breuk (§13 both-sides-regel).
    func testJSONContractKeysAndCategoriesPresent() {
        let text = makeText()
        XCTAssertTrue(text.contains("\"reply\""))
        XCTAssertTrue(text.contains("\"workoutFacts\""))
        for category in WorkoutFactCategory.allCases {
            XCTAssertTrue(text.contains(category.rawValue),
                          "Categorie-literal '\(category.rawValue)' ontbreekt in het contract")
        }
        XCTAssertTrue(text.contains("\"workoutFacts\": []"), "Leeg-array-instructie ontbreekt")
    }

    /// De categorie-literals in de instructie moeten 1-op-1 sporen met het enum —
    /// dit vangt zowel een enum-hernoeming als een contract-tekstwijziging.
    func testCategoryLiteralsMatchEnum() {
        let expected = WorkoutFactCategory.allCases.map(\.rawValue).joined(separator: "|")
        XCTAssertEqual(WorkoutChatScopeInstruction.categoryLiterals, expected)
    }
}
