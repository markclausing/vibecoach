import XCTest
@testable import AIFitnessCoach

/// Epic 32 Story 32.3b — `WorkoutInsightCache`.
/// Borgt:
///  • Hit/miss-gedrag op fingerprint
///  • Overschrijven bij her-store
///  • Invalidate per activity en globaal
///  • Persistentie via UserDefaults-blob
final class WorkoutInsightCacheTests: XCTestCase {

    private var defaults: UserDefaults!
    private var cache: WorkoutInsightCache!
    private let suiteName = "WorkoutInsightCacheTests"

    override func setUp() {
        super.setUp()
        // Geïsoleerde UserDefaults-suite zodat productie-data niet vervuild raakt.
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
        cache = WorkoutInsightCache(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        cache = nil
        super.tearDown()
    }

    // MARK: Hit/miss

    func testCached_NoEntry_ReturnsNil() {
        XCTAssertNil(cache.cached(for: "act-1", fingerprint: "fp-1"))
    }

    func testStore_ThenCached_ReturnsText() {
        cache.store("Coach-narrative", for: "act-1", fingerprint: "fp-1")
        XCTAssertEqual(cache.cached(for: "act-1", fingerprint: "fp-1"), "Coach-narrative")
    }

    func testCached_DifferentFingerprint_ReturnsNil() {
        cache.store("Oude analyse", for: "act-1", fingerprint: "fp-1")
        // Pattern-fingerprint is gewijzigd na re-classificatie → cache moet missen.
        XCTAssertNil(cache.cached(for: "act-1", fingerprint: "fp-2"),
                     "Andere fingerprint moet cache invalidate triggeren")
    }

    func testCached_DifferentActivity_ReturnsNil() {
        cache.store("Voor activity A", for: "act-1", fingerprint: "fp")
        XCTAssertNil(cache.cached(for: "act-2", fingerprint: "fp"))
    }

    // MARK: Overschrijven

    func testStore_OverwritesPreviousEntry() {
        cache.store("Eerste versie", for: "act-1", fingerprint: "fp-1")
        cache.store("Nieuwe versie", for: "act-1", fingerprint: "fp-1")
        XCTAssertEqual(cache.cached(for: "act-1", fingerprint: "fp-1"), "Nieuwe versie")
    }

    func testStore_NewFingerprintOverwritesOld() {
        cache.store("Oude analyse", for: "act-1", fingerprint: "fp-1")
        cache.store("Nieuwe analyse", for: "act-1", fingerprint: "fp-2")
        XCTAssertNil(cache.cached(for: "act-1", fingerprint: "fp-1"),
                     "Na overschrijven met andere fingerprint mag de oude niet meer hit'en")
        XCTAssertEqual(cache.cached(for: "act-1", fingerprint: "fp-2"), "Nieuwe analyse")
    }

    // MARK: Invalidate

    func testInvalidate_RemovesEntry() {
        cache.store("Analyse", for: "act-1", fingerprint: "fp-1")
        cache.invalidate(activityID: "act-1")
        XCTAssertNil(cache.cached(for: "act-1", fingerprint: "fp-1"))
    }

    func testInvalidate_LeavesOtherEntriesIntact() {
        cache.store("A", for: "act-1", fingerprint: "fp")
        cache.store("B", for: "act-2", fingerprint: "fp")
        cache.invalidate(activityID: "act-1")
        XCTAssertNil(cache.cached(for: "act-1", fingerprint: "fp"))
        XCTAssertEqual(cache.cached(for: "act-2", fingerprint: "fp"), "B")
    }

    func testClearAll_WipesEverything() {
        cache.store("A", for: "act-1", fingerprint: "fp")
        cache.store("B", for: "act-2", fingerprint: "fp")
        cache.clearAll()
        XCTAssertNil(cache.cached(for: "act-1", fingerprint: "fp"))
        XCTAssertNil(cache.cached(for: "act-2", fingerprint: "fp"))
    }

    // MARK: Persistentie

    func testPersistence_SurvivesNewCacheInstance() {
        cache.store("Persistent", for: "act-1", fingerprint: "fp-1")
        // Nieuwe cache-instantie op dezelfde defaults — entry moet door JSON-decode komen.
        let secondInstance = WorkoutInsightCache(defaults: defaults)
        XCTAssertEqual(secondInstance.cached(for: "act-1", fingerprint: "fp-1"), "Persistent")
    }
}
