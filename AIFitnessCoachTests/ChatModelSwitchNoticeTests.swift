import XCTest
@testable import AIFitnessCoach

/// Epic #51-A2: borgt dat de banner-tekst alleen verschijnt wanneer de gebruiker
/// daadwerkelijk van model wisselt tijdens een actieve request, en dat de tekst
/// de namen van het oude én het nieuwe model noemt zodat de gebruiker weet
/// welke versie het lopende antwoord nog produceert.
final class ChatModelSwitchNoticeTests: XCTestCase {

    func testReturnsNilWhenNoChange() {
        let result = ChatModelSwitchNotice.message(
            activePrimary: "gemini-flash-latest",
            activeFallback: "gemini-flash-lite-latest",
            configuredPrimary: "gemini-flash-latest",
            configuredFallback: "gemini-flash-lite-latest"
        )
        XCTAssertNil(result, "Geen wissel → geen banner.")
    }

    func testReturnsNilWhenSnapshotsEmpty() {
        // Buiten een actieve request zijn de snapshots leeg — dan mag de helper
        // nooit een banner forceren ook al staat er een geconfigureerd model.
        let result = ChatModelSwitchNotice.message(
            activePrimary: "",
            activeFallback: "",
            configuredPrimary: "gemini-flash-latest",
            configuredFallback: "gemini-flash-lite-latest"
        )
        XCTAssertNil(result)
    }

    func testDetectsPrimaryChange() {
        let result = ChatModelSwitchNotice.message(
            activePrimary: "gemini-flash-latest",
            activeFallback: "gemini-flash-lite-latest",
            configuredPrimary: "gemini-2.5-flash",
            configuredFallback: "gemini-flash-lite-latest"
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("gemini-flash-latest"), "Oude modelnaam moet in de tekst staan.")
        XCTAssertTrue(result!.contains("gemini-2.5-flash"), "Nieuwe modelnaam moet in de tekst staan.")
    }

    func testDetectsFallbackChangeOnly() {
        // Alleen de fallback wijzigt — de primary blijft gelijk. Dan moet de
        // tekst expliciet over de fallback gaan, niet over de primary.
        let result = ChatModelSwitchNotice.message(
            activePrimary: "gemini-flash-latest",
            activeFallback: "gemini-flash-lite-latest",
            configuredPrimary: "gemini-flash-latest",
            configuredFallback: "gemini-2.5-flash-lite"
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.lowercased().contains("fallback"), "Fallback-wijziging moet als zodanig benoemd worden.")
        XCTAssertTrue(result!.contains("gemini-flash-lite-latest"))
        XCTAssertTrue(result!.contains("gemini-2.5-flash-lite"))
    }

    func testPrimaryChangeTakesPrecedenceOverFallbackChange() {
        // Beide veranderd: de primary-message is gebruikersrelevanter omdat dat
        // het model is dat het huidige antwoord aan het maken is.
        let result = ChatModelSwitchNotice.message(
            activePrimary: "gemini-flash-latest",
            activeFallback: "gemini-flash-lite-latest",
            configuredPrimary: "gemini-2.5-flash",
            configuredFallback: "gemini-2.5-flash-lite"
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("gemini-flash-latest"))
        XCTAssertTrue(result!.contains("gemini-2.5-flash"))
    }
}
