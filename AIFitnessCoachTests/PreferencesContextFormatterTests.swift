import XCTest
@testable import AIFitnessCoach

/// Unit tests voor `PreferencesContextFormatter`. Borgen dat tijdelijke voorkeuren
/// (met expirationDate) en vastgepinde voorkeuren (zonder) als aparte blokken in de
/// coach-context belanden, mét expliciete priority-instructie.
final class PreferencesContextFormatterTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func tomorrow() -> Date { now.addingTimeInterval(86_400) }
    private func yesterday() -> Date { now.addingTimeInterval(-86_400) }

    // MARK: - Lege staten

    func testEmptyInputProducesEmptyString() {
        let result = PreferencesContextFormatter.format(activePreferences: [], now: now)
        XCTAssertEqual(result, "")
    }

    func testExpiredTemporaryPreferencesAreFilteredOut() {
        let expired = UserPreference(preferenceText: "oude tijdelijke regel", expirationDate: yesterday())
        let result = PreferencesContextFormatter.format(activePreferences: [expired], now: now)
        XCTAssertEqual(result, "", "Verlopen tijdelijke voorkeuren mogen de prompt niet vervuilen")
    }

    // MARK: - Alleen één type

    func testOnlyPermanentProducesPinnedBlockWithoutCriticalInstruction() {
        let permanent = UserPreference(preferenceText: "Krachttraining elke di/do in de gym", expirationDate: nil)
        let result = PreferencesContextFormatter.format(activePreferences: [permanent], now: now)

        XCTAssertTrue(result.contains("PINNED RULES"),
                      "Permanente voorkeuren moeten in het VASTGEPINDE-blok staan")
        XCTAssertTrue(result.contains("Krachttraining elke di/do in de gym"))
        XCTAssertFalse(result.contains("CRITICAL INSTRUCTION"),
                       "Zonder tijdelijke voorkeur is een prioriteit-instructie overbodig — anders zwaait de coach met een loze waarschuwing")
        XCTAssertFalse(result.contains("TEMPORARY PREFERENCES"))
    }

    func testOnlyTemporaryProducesTemporaryBlockWithCriticalInstruction() {
        let temp = UserPreference(preferenceText: "Op vakantie in Rome: geen sport, alleen wandelen",
                                  expirationDate: tomorrow())
        let result = PreferencesContextFormatter.format(activePreferences: [temp], now: now)

        XCTAssertTrue(result.contains("TEMPORARY PREFERENCES"))
        XCTAssertTrue(result.contains("Op vakantie in Rome"))
        XCTAssertTrue(result.contains("CRITICAL INSTRUCTION"),
                      "Tijdelijke voorkeuren moeten altijd vergezeld zijn van de override-instructie")
        XCTAssertTrue(result.contains("(temporary, valid until"),
                      "De einddatum moet zichtbaar zijn voor de coach")
        XCTAssertFalse(result.contains("PINNED RULES"))
    }

    // MARK: - Beide

    func testBothProducesTwoSeparateBlocksAndCriticalInstruction() {
        let permanent = UserPreference(preferenceText: "Krachttraining elke di/do in de gym",
                                       expirationDate: nil)
        let temp = UserPreference(preferenceText: "Op vakantie in Rome: geen sport, alleen wandelen",
                                  expirationDate: tomorrow())

        let result = PreferencesContextFormatter.format(activePreferences: [permanent, temp], now: now)

        XCTAssertTrue(result.contains("PINNED RULES"))
        XCTAssertTrue(result.contains("TEMPORARY PREFERENCES"))
        XCTAssertTrue(result.contains("CRITICAL INSTRUCTION"))
        XCTAssertTrue(result.contains("Krachttraining elke di/do"))
        XCTAssertTrue(result.contains("Op vakantie in Rome"))

        // Volgorde: vastgepind eerst, daarna tijdelijk + instructie. Dat zorgt dat het
        // laatste wat de coach 'leest' over preferences de override-regel is — meest
        // recente context weegt sterker in LLM-attention.
        let pinnedRange = result.range(of: "PINNED RULES")!
        let temporaryRange = result.range(of: "TEMPORARY PREFERENCES")!
        XCTAssertLessThan(pinnedRange.lowerBound, temporaryRange.lowerBound,
                          "Vastgepind moet vóór tijdelijk staan zodat de override-regel de laatste boodschap is")
    }

    // MARK: - Mix met verlopen items

    func testMixOfValidAndExpiredFiltersOnlyExpired() {
        let validPermanent = UserPreference(preferenceText: "Geen hardlopen na 21:00",
                                            expirationDate: nil)
        let validTemporary = UserPreference(preferenceText: "Lichte kuit-blessure",
                                            expirationDate: tomorrow())
        let expiredTemporary = UserPreference(preferenceText: "Verkoudheid vorige week",
                                              expirationDate: yesterday())

        let result = PreferencesContextFormatter.format(
            activePreferences: [validPermanent, validTemporary, expiredTemporary],
            now: now
        )

        XCTAssertTrue(result.contains("Geen hardlopen na 21:00"))
        XCTAssertTrue(result.contains("Lichte kuit-blessure"))
        XCTAssertFalse(result.contains("Verkoudheid"),
                       "Verlopen items mogen niet in de prompt belanden, ook niet als de lijst meerdere geldige items bevat")
    }
}
