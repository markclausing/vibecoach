import XCTest
@testable import AIFitnessCoach

/// C-02: verifieert de eenmalige migratie van de user API-sleutel vanuit
/// `UserDefaults` naar de Keychain (`UserAPIKeyStore.migrateFromUserDefaultsIfNeeded`).
final class UserAPIKeyStoreMigrationTests: XCTestCase {

    private var store: MockTokenStore!
    private var defaults: UserDefaults!
    private let suiteName = "UserAPIKeyStoreMigrationTests"

    override func setUp() {
        super.setUp()
        store = MockTokenStore()
        // Een losse suite zodat de tests de echte standardUserDefaults niet raken.
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    /// De happy path: een legacy-sleutel in UserDefaults wordt verplaatst en
    /// de originele entry wordt gewist.
    func testMigratesLegacyKeyFromUserDefaultsToKeychain() {
        defaults.set("legacy-user-key", forKey: UserAPIKeyStore.legacyUserDefaultsKey)

        UserAPIKeyStore.migrateFromUserDefaultsIfNeeded(store: store, defaults: defaults)

        XCTAssertEqual(
            UserAPIKeyStore.read(using: store),
            "legacy-user-key",
            "De sleutel moet na migratie beschikbaar zijn via de Keychain-wrapper."
        )
        XCTAssertNil(
            defaults.string(forKey: UserAPIKeyStore.legacyUserDefaultsKey),
            "De UserDefaults-entry moet na een succesvolle migratie gewist zijn."
        )
    }

    /// Zonder legacy-sleutel is de migratie een no-op — Keychain blijft leeg.
    func testNoOpWhenNoLegacyKeyPresent() {
        UserAPIKeyStore.migrateFromUserDefaultsIfNeeded(store: store, defaults: defaults)

        XCTAssertEqual(UserAPIKeyStore.read(using: store), "")
    }

    /// Een lege string telt niet als een migreerbare sleutel — voorkomt dat we
    /// een lege entry in de Keychain pushen wat later misleidend kan zijn.
    func testSkipsEmptyLegacyValue() {
        defaults.set("", forKey: UserAPIKeyStore.legacyUserDefaultsKey)

        UserAPIKeyStore.migrateFromUserDefaultsIfNeeded(store: store, defaults: defaults)

        XCTAssertEqual(UserAPIKeyStore.read(using: store), "")
    }

    /// Bij herhaalde aanroepen blijft het resultaat stabiel (idempotent).
    /// Tweede run vindt niks meer te migreren.
    func testIdempotentSecondRunIsNoOp() {
        defaults.set("first-run-key", forKey: UserAPIKeyStore.legacyUserDefaultsKey)
        UserAPIKeyStore.migrateFromUserDefaultsIfNeeded(store: store, defaults: defaults)

        // Tweede run: geen legacy-data meer, dus ook geen overschrijving.
        UserAPIKeyStore.migrateFromUserDefaultsIfNeeded(store: store, defaults: defaults)

        XCTAssertEqual(UserAPIKeyStore.read(using: store), "first-run-key")
        XCTAssertNil(defaults.string(forKey: UserAPIKeyStore.legacyUserDefaultsKey))
    }

    /// `write` met een lege string hoort de entry te wissen — zo kan de gebruiker
    /// zijn sleutel vergeten door het veld leeg te maken zonder dat er een ghost
    /// achterblijft.
    func testWriteEmptyStringDeletesStoredKey() {
        UserAPIKeyStore.write("abc123", using: store)
        XCTAssertEqual(UserAPIKeyStore.read(using: store), "abc123")

        UserAPIKeyStore.write("", using: store)
        XCTAssertEqual(UserAPIKeyStore.read(using: store), "")
    }

    /// `write` trimt whitespace — gebruikers plakken vaak een sleutel met een
    /// per ongeluk meegenomen spatie of newline.
    func testWriteTrimsWhitespace() {
        UserAPIKeyStore.write("  padded-key  \n", using: store)
        XCTAssertEqual(UserAPIKeyStore.read(using: store), "padded-key")
    }
}
