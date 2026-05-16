import XCTest
@testable import AIFitnessCoach

/// Epic #51-H: borgt het persistente flag-mechanisme dat de UI-banner aandrijft
/// nadat de SwiftData-migratie tijdens een app-launch faalde en de fresh-DB-
/// fallback (CLAUDE.md §12) is geactiveerd.
final class MigrationFallbackStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "MigrationFallbackStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFallbackDateIsNilByDefault() {
        let store = MigrationFallbackStore(defaults: defaults)
        XCTAssertNil(store.fallbackDate, "Een verse store heeft geen actieve fallback.")
    }

    func testRecordFallbackPersistsTheGivenDate() {
        let store = MigrationFallbackStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        store.recordFallback(at: date)

        XCTAssertEqual(store.fallbackDate, date)
    }

    func testRecordFallbackDefaultsToNow() throws {
        let store = MigrationFallbackStore(defaults: defaults)
        let before = Date()

        store.recordFallback()

        let after = Date()
        let stored = try XCTUnwrap(store.fallbackDate)
        XCTAssertGreaterThanOrEqual(stored, before)
        XCTAssertLessThanOrEqual(stored, after)
    }

    /// Dismiss-knop in de banner moet de flag permanent wissen tot een volgende
    /// fallback. Anders blijft de melding bij elke app-launch terugkomen.
    func testClearRemovesFallbackDate() {
        let store = MigrationFallbackStore(defaults: defaults)
        store.recordFallback()
        XCTAssertNotNil(store.fallbackDate)

        store.clear()

        XCTAssertNil(store.fallbackDate)
    }

    /// Verifieert dat de UserDefaults-key niet stilletjes hernoemd is — de
    /// container-init in `AIFitnessCoachApp.makeModelContainer()` referenceert
    /// hem via `AIFitnessCoachApp.migrationFallbackKey`.
    @MainActor
    func testKeyMatchesAppLevelConstant() {
        XCTAssertEqual(MigrationFallbackStore.key, AIFitnessCoachApp.migrationFallbackKey)
    }
}
