import XCTest
@testable import AIFitnessCoach

/// Epic #62 story 62.2 — the validated-key verdict persists per provider across switch/restart.
final class APIKeyTestStatusStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: APIKeyTestStatusStore!

    override func setUp() {
        super.setUp()
        suiteName = "APIKeyTestStatusStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = APIKeyTestStatusStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testUnseenKeyIsNotValidated() {
        XCTAssertFalse(store.isValidated(key: "sk-abc", for: .openAI))
    }

    func testMarkedKeyIsValidated() {
        store.markValidated(key: "sk-abc", for: .openAI)
        XCTAssertTrue(store.isValidated(key: "sk-abc", for: .openAI))
    }

    func testValidationIsPerProvider() {
        store.markValidated(key: "AIzaSyABC", for: .gemini)
        XCTAssertTrue(store.isValidated(key: "AIzaSyABC", for: .gemini))
        XCTAssertFalse(store.isValidated(key: "AIzaSyABC", for: .openAI))
    }

    func testADifferentKeyForSameProviderIsNotValidated() {
        store.markValidated(key: "sk-old", for: .openAI)
        XCTAssertFalse(store.isValidated(key: "sk-new", for: .openAI))
    }

    func testWhitespaceVariantsOfTheSameKeyMatch() {
        // The verdict survives a re-load where the field was sanitised differently.
        store.markValidated(key: "sk-abc", for: .openAI)
        XCTAssertTrue(store.isValidated(key: "  sk-abc\n", for: .openAI))
    }

    func testClearRemovesVerdict() {
        store.markValidated(key: "sk-abc", for: .openAI)
        store.clear(for: .openAI)
        XCTAssertFalse(store.isValidated(key: "sk-abc", for: .openAI))
    }

    func testEmptyKeyIsNeverValidated() {
        XCTAssertFalse(store.isValidated(key: "   ", for: .openAI))
    }

    func testFingerprintIsStableAndNonReversible() {
        let fp = APIKeyTestStatusStore.fingerprint("sk-abc")
        XCTAssertEqual(fp, APIKeyTestStatusStore.fingerprint("sk-abc"))
        XCTAssertEqual(fp.count, 64)               // SHA256 hex
        XCTAssertFalse(fp.contains("sk-abc"))      // the raw key is not present
    }

    /// Persistence across "restart" — a fresh store over the same backing store still sees it.
    func testVerdictSurvivesNewStoreInstance() {
        store.markValidated(key: "sk-abc", for: .openAI)
        let reloaded = APIKeyTestStatusStore(defaults: defaults)
        XCTAssertTrue(reloaded.isValidated(key: "sk-abc", for: .openAI))
    }
}
