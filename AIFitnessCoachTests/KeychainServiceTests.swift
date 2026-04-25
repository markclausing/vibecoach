import XCTest
@testable import AIFitnessCoach

/// Epic #36 sub-task 36.6 — integratietests voor `KeychainService`.
///
/// In tegenstelling tot andere services kunnen we hier níet via een protocol-mock
/// werken: het hele punt van `KeychainService` is precies de wrapper rond
/// `SecItem*`-calls te valideren. iOS Simulator-keychains zijn echter wél
/// aanroepbaar in het test-target, dus we draaien tegen de echte Keychain met
/// **UUID-namespaced service-namen** zodat:
///   1. Concurrent tests elkaar niet beïnvloeden.
///   2. Lekken naar productie-runs onmogelijk is (UUIDs zitten niet in de
///      "echte" service-namen die de app gebruikt).
///   3. `tearDown` elke entry expliciet kan opruimen.
final class KeychainServiceTests: XCTestCase {

    private var sut: KeychainService!
    private var serviceName: String!

    override func setUpWithError() throws {
        sut = KeychainService.shared
        serviceName = "vibecoach.test.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        // Probeer altijd op te ruimen — ook als de test halverwege faalde
        // mag er geen test-token in de simulator-keychain blijven hangen.
        try? sut.deleteToken(forService: serviceName)
        sut = nil
        serviceName = nil
    }

    // MARK: - Save + Get roundtrip

    func testSaveAndGet_RoundtripsToken() throws {
        let token = "secret-token-\(UUID().uuidString)"
        try sut.saveToken(token, forService: serviceName)

        let retrieved = try sut.getToken(forService: serviceName)
        XCTAssertEqual(retrieved, token)
    }

    func testSave_OverwritesExistingToken() throws {
        // Twee saves achter elkaar mogen GEEN duplicate-item error geven.
        // De interne deleteQuery in saveToken hoort het oude record op te
        // ruimen voor de nieuwe SecItemAdd.
        try sut.saveToken("first-value", forService: serviceName)
        try sut.saveToken("second-value", forService: serviceName)

        let retrieved = try sut.getToken(forService: serviceName)
        XCTAssertEqual(retrieved, "second-value",
                       "De tweede save moet de eerste hebben overschreven (geen duplicate-error).")
    }

    func testSave_HandlesUnicodeAndSpecialCharacters() throws {
        let token = "🔐 token-with émoji & special chars: \"quotes\" + \\backslash"
        try sut.saveToken(token, forService: serviceName)

        let retrieved = try sut.getToken(forService: serviceName)
        XCTAssertEqual(retrieved, token,
                       "Unicode + speciale karakters moeten via UTF-8 round-trippen zonder data-corruptie.")
    }

    func testSave_AllowsEmptyString() throws {
        // Een lege string is geldige UTF-8 → moet round-trippen.
        // (Een lege token is wel inhoudelijk onlogisch; de service mag dat niet
        // zelf afkeuren — dat is aan de caller. Hier valideren we het contract.)
        try sut.saveToken("", forService: serviceName)

        let retrieved = try sut.getToken(forService: serviceName)
        XCTAssertEqual(retrieved, "",
                       "Een lege string is een geldige UTF-8 byte-string en moet roundtrippen.")
    }

    // MARK: - Get bij ontbrekende sleutel

    func testGet_NonExistentService_ReturnsNil() throws {
        // Geen save vóór de get → moet nil teruggeven (errSecItemNotFound),
        // GEEN throw. De caller mag een nil-return als "geen token" interpreteren.
        let retrieved = try sut.getToken(forService: serviceName)
        XCTAssertNil(retrieved,
                     "Onbekende service moet nil retourneren — geen throw, geen sentinel-string.")
    }

    // MARK: - Delete

    func testDelete_RemovesToken() throws {
        try sut.saveToken("to-be-deleted", forService: serviceName)
        try sut.deleteToken(forService: serviceName)

        let retrieved = try sut.getToken(forService: serviceName)
        XCTAssertNil(retrieved, "Na delete moet de get nil teruggeven.")
    }

    func testDelete_IsIdempotent() throws {
        // Twee deletes achter elkaar — de tweede mag GEEN throw geven omdat
        // errSecItemNotFound expliciet wordt geaccepteerd.
        try sut.saveToken("temp", forService: serviceName)
        XCTAssertNoThrow(try sut.deleteToken(forService: serviceName))
        XCTAssertNoThrow(
            try sut.deleteToken(forService: serviceName),
            "Een tweede delete op dezelfde service mag NIET throwen (idempotency contract)."
        )
    }

    func testDelete_NonExistentService_DoesNotThrow() throws {
        // Direct een delete zonder voorafgaande save — moet schoon doorlopen.
        XCTAssertNoThrow(
            try sut.deleteToken(forService: serviceName),
            "Delete op een nooit-opgeslagen service mag niet throwen."
        )
    }

    // MARK: - Multiple services isolatie

    func testMultipleServices_AreIsolated() throws {
        let secondService = "vibecoach.test.second.\(UUID().uuidString)"
        defer { try? sut.deleteToken(forService: secondService) }

        try sut.saveToken("alpha", forService: serviceName)
        try sut.saveToken("beta", forService: secondService)

        XCTAssertEqual(try sut.getToken(forService: serviceName), "alpha")
        XCTAssertEqual(try sut.getToken(forService: secondService), "beta",
                       "Tokens in verschillende services mogen elkaar nooit overschrijven.")
    }

    func testDelete_LeavesOtherServicesIntact() throws {
        let otherService = "vibecoach.test.other.\(UUID().uuidString)"
        defer { try? sut.deleteToken(forService: otherService) }

        try sut.saveToken("keep-me", forService: otherService)
        try sut.saveToken("delete-me", forService: serviceName)

        try sut.deleteToken(forService: serviceName)

        XCTAssertNil(try sut.getToken(forService: serviceName))
        XCTAssertEqual(try sut.getToken(forService: otherService), "keep-me",
                       "Delete mag alleen de doel-service raken — andere entries blijven staan.")
    }

    // MARK: - TokenStore protocol-conformance smoke

    func testKeychainService_ConformsToTokenStoreProtocol() {
        let asProtocol: TokenStore = sut
        XCTAssertNotNil(asProtocol,
                        "KeychainService.shared moet als TokenStore inzetbaar zijn — dat is de hele reden waarom MockTokenStore bestaat.")
    }
}
