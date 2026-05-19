import XCTest
@testable import AIFitnessCoach

final class WeatherRetryStoreTests: XCTestCase {

    private func freshStore(_ function: String = #function) -> (WeatherRetryStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "weatherRetryTests-\(function)-\(UUID().uuidString)")!
        return (WeatherRetryStore(defaults: defaults), defaults)
    }

    func testMarkFailedStoresTimestamp() {
        let (store, _) = freshStore()
        let now = Date()
        store.markFailed(activityID: "abc", at: now)

        let recorded = store.failedSince(activityID: "abc")
        XCTAssertEqual(recorded?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testFailedSinceReturnsNilForUnknownID() {
        let (store, _) = freshStore()
        XCTAssertNil(store.failedSince(activityID: "missing"))
    }

    func testClearRemovesMarker() {
        let (store, _) = freshStore()
        store.markFailed(activityID: "abc")
        XCTAssertNotNil(store.failedSince(activityID: "abc"))

        store.clear(activityID: "abc")
        XCTAssertNil(store.failedSince(activityID: "abc"))
    }

    func testCandidatesReadyForRetry_UnmarkedIDsAreAlwaysReady() {
        let (store, _) = freshStore()
        let ready = store.candidatesReadyForRetry(from: ["a", "b", "c"])
        XCTAssertEqual(Set(ready), Set(["a", "b", "c"]))
    }

    func testCandidatesReadyForRetry_RecentFailuresExcluded() {
        let (store, _) = freshStore()
        let now = Date()
        // Eén marker net 5 minuten geleden — binnen 1u cooldown, niet ready.
        store.markFailed(activityID: "recent", at: now.addingTimeInterval(-300))
        // Eén marker 2 uur geleden — buiten 1u cooldown, ready.
        store.markFailed(activityID: "stale", at: now.addingTimeInterval(-7_200))

        let ready = store.candidatesReadyForRetry(
            from: ["recent", "stale", "fresh"],
            now: now,
            cooldown: 3_600
        )
        XCTAssertEqual(Set(ready), Set(["stale", "fresh"]))
    }

    func testCandidatesReadyForRetry_CustomCooldown() {
        let (store, _) = freshStore()
        let now = Date()
        store.markFailed(activityID: "x", at: now.addingTimeInterval(-30))

        // Met 10s-cooldown is "x" wel ready, met 60s-cooldown niet.
        XCTAssertEqual(store.candidatesReadyForRetry(from: ["x"], now: now, cooldown: 10), ["x"])
        XCTAssertEqual(store.candidatesReadyForRetry(from: ["x"], now: now, cooldown: 60), [])
    }

    func testMarkerCountTracksEntries() {
        let (store, _) = freshStore()
        XCTAssertEqual(store.markerCount, 0)

        store.markFailed(activityID: "a")
        store.markFailed(activityID: "b")
        XCTAssertEqual(store.markerCount, 2)

        store.clear(activityID: "a")
        XCTAssertEqual(store.markerCount, 1)
    }

    func testWritingEmptyMapRemovesKey() {
        let (store, defaults) = freshStore()
        store.markFailed(activityID: "a")
        XCTAssertNotNil(defaults.object(forKey: WeatherRetryStore.key))

        store.clear(activityID: "a")
        XCTAssertNil(defaults.object(forKey: WeatherRetryStore.key))
    }

    func testRemarkOverwritesTimestamp() {
        let (store, _) = freshStore()
        let firstFailure = Date(timeIntervalSince1970: 1_000_000)
        let secondFailure = Date(timeIntervalSince1970: 2_000_000)

        store.markFailed(activityID: "id", at: firstFailure)
        store.markFailed(activityID: "id", at: secondFailure)

        XCTAssertEqual(
            store.failedSince(activityID: "id")?.timeIntervalSince1970 ?? 0,
            secondFailure.timeIntervalSince1970,
            accuracy: 0.001
        )
    }
}
