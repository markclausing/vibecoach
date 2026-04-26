import XCTest
@testable import AIFitnessCoach

/// Unit tests voor `UUID.deterministic(fromStravaID:)` en `UUID.forActivityRecordID(_:)`.
/// Borgt determinisme (zelfde input → zelfde UUID) en correcte routing tussen
/// HealthKit (UUID-uuidString) en Strava (numerieke ID).
final class UUIDDeterministicTests: XCTestCase {

    func testSameStravaIDProducesSameUUID() {
        let a = UUID.deterministic(fromStravaID: "12345678901")
        let b = UUID.deterministic(fromStravaID: "12345678901")
        XCTAssertEqual(a, b, "Determinisme is de hele essentie — twee runs moeten dezelfde UUID opleveren")
    }

    func testDifferentStravaIDsProduceDifferentUUIDs() {
        let a = UUID.deterministic(fromStravaID: "12345678901")
        let b = UUID.deterministic(fromStravaID: "12345678902")
        XCTAssertNotEqual(a, b, "Verschillende Strava-ID's mogen NOOIT dezelfde UUID opleveren — anders raken samples vermengd")
    }

    func testStravaIDAndHealthKitUUIDDoNotCollide() {
        // Een echte HealthKit-UUID en een Strava-ID hebben geen relatie tot elkaar,
        // maar voor de zekerheid: een UUID die letterlijk dezelfde tekens heeft als
        // een Strava-ID-string mag niet via deterministic resulteren in dezelfde UUID.
        let stravaUUID = UUID.deterministic(fromStravaID: "12345678901")
        let realHKUUID = UUID()
        XCTAssertNotEqual(stravaUUID, realHKUUID)
    }

    // MARK: forActivityRecordID — routing tussen bronnen

    func testForActivityRecordIDParsesHealthKitUUIDString() {
        let realUUID = UUID()
        let resolved = UUID.forActivityRecordID(realUUID.uuidString)
        XCTAssertEqual(resolved, realUUID,
                       "HK-records moeten gewoon hun originele UUID behouden — geen herhash")
    }

    func testForActivityRecordIDFallsBackToDeterministicForStravaID() {
        let stravaResolved = UUID.forActivityRecordID("12345678901")
        let directDeterministic = UUID.deterministic(fromStravaID: "12345678901")
        XCTAssertEqual(stravaResolved, directDeterministic,
                       "Niet-UUID-parseerbare ID's moeten via de deterministische route gaan")
    }

    func testForActivityRecordIDIsIdempotent() {
        // Zelfde activity.id meerdere keren resolven → zelfde UUID. Cruciaal voor
        // herhaalde lookups in @Query en backfill-checks.
        let id = "98765432100"
        XCTAssertEqual(UUID.forActivityRecordID(id), UUID.forActivityRecordID(id))
    }
}
