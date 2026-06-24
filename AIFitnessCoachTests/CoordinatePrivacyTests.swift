import XCTest
@testable import AIFitnessCoach

/// Story 61.6 (L-5) — `CoordinatePrivacy`.
/// Verifies the shared 0.1° rounding used by every weather path.
final class CoordinatePrivacyTests: XCTestCase {

    func testRounds_ToNearestTenthDegree() {
        XCTAssertEqual(CoordinatePrivacy.round(52.3712), 52.4, accuracy: 0.0001)
        XCTAssertEqual(CoordinatePrivacy.round(4.8945), 4.9, accuracy: 0.0001)
    }

    func testRounds_NegativeCoordinates() {
        XCTAssertEqual(CoordinatePrivacy.round(-33.8688), -33.9, accuracy: 0.0001)
    }

    func testRounds_DownWhenCloserToLowerTenth() {
        XCTAssertEqual(CoordinatePrivacy.round(52.3212), 52.3, accuracy: 0.0001)
    }

    func testAlreadyRounded_IsStable() {
        XCTAssertEqual(CoordinatePrivacy.round(52.4), 52.4, accuracy: 0.0001)
        XCTAssertEqual(CoordinatePrivacy.round(0.0), 0.0, accuracy: 0.0001)
    }

    func testMatchesHistoricalWeatherServiceHelper() {
        // The legacy entry point must stay equivalent (it now delegates here).
        XCTAssertEqual(
            HistoricalWeatherService.roundForPrivacy(48.8566),
            CoordinatePrivacy.round(48.8566),
            accuracy: 0.0001
        )
    }
}
