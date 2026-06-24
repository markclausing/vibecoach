import XCTest
@testable import AIFitnessCoach

/// Story 61.3 (security-review follow-up) — `PHIContextCache`.
/// Verifies that the central purge:
///  • removes every listed cleartext PHI context-cache key,
///  • also clears the per-workout `WorkoutInsightCache` blob,
///  • leaves unrelated keys untouched,
///  • is idempotent (safe to call on an already-empty store).
final class PHIContextCacheTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "PHIContextCacheTests"

    override func setUp() {
        super.setUp()
        // Isolated suite so production preferences are never touched.
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testPurge_RemovesEveryListedKey() {
        // Seed every PHI key with a non-empty marker value.
        for key in PHIContextCache.keys {
            defaults.set("phi-\(key)", forKey: key)
        }
        // Sanity: all present before purge.
        for key in PHIContextCache.keys {
            XCTAssertNotNil(defaults.object(forKey: key), "expected \(key) seeded")
        }

        PHIContextCache.purge(defaults)

        for key in PHIContextCache.keys {
            XCTAssertNil(defaults.object(forKey: key), "expected \(key) cleared after purge")
        }
    }

    func testPurge_ClearsWorkoutInsightCache() {
        let insightCache = WorkoutInsightCache(defaults: defaults)
        insightCache.store("Coach narrative", for: "act-1", fingerprint: "fp-1")
        XCTAssertEqual(insightCache.cached(for: "act-1", fingerprint: "fp-1"), "Coach narrative")

        PHIContextCache.purge(defaults)

        XCTAssertNil(insightCache.cached(for: "act-1", fingerprint: "fp-1"),
                     "WorkoutInsightCache should be cleared by the purge")
    }

    func testPurge_LeavesUnrelatedKeysUntouched() {
        defaults.set("keep-me", forKey: "vibecoach_appLanguage")
        defaults.set(true, forKey: "hasCompletedOnboarding")

        PHIContextCache.purge(defaults)

        XCTAssertEqual(defaults.string(forKey: "vibecoach_appLanguage"), "keep-me")
        XCTAssertTrue(defaults.bool(forKey: "hasCompletedOnboarding"))
    }

    func testPurge_IsIdempotentOnEmptyStore() {
        // No seeded values — must not crash and must leave the store empty.
        PHIContextCache.purge(defaults)
        for key in PHIContextCache.keys {
            XCTAssertNil(defaults.object(forKey: key))
        }
    }
}
