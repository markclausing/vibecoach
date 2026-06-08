import XCTest
@testable import AIFitnessCoach

/// Epic #56 story 56.2: unit tests for great-circle per-stage interpolation.
final class StageLocationInterpolatorTests: XCTestCase {

    private let arnhem    = GeoCoordinate(latitude: 51.98, longitude: 5.91)
    private let karlsruhe = GeoCoordinate(latitude: 49.01, longitude: 8.40)

    func test_firstStage_isStart() {
        let c = StageLocationInterpolator.coordinate(forStage: 1, totalStages: 5, start: arnhem, end: karlsruhe)
        XCTAssertEqual(c.latitude, arnhem.latitude, accuracy: 1e-9)
        XCTAssertEqual(c.longitude, arnhem.longitude, accuracy: 1e-9)
    }

    func test_lastStage_isEnd() {
        let c = StageLocationInterpolator.coordinate(forStage: 5, totalStages: 5, start: arnhem, end: karlsruhe)
        XCTAssertEqual(c.latitude, karlsruhe.latitude, accuracy: 1e-9)
        XCTAssertEqual(c.longitude, karlsruhe.longitude, accuracy: 1e-9)
    }

    func test_middleStage_isRoughlyHalfway() {
        // Stage 3 of 5 → fraction 0.5. Great-circle ≈ linear midpoint over this short route.
        let c = StageLocationInterpolator.coordinate(forStage: 3, totalStages: 5, start: arnhem, end: karlsruhe)
        XCTAssertEqual(c.latitude, 50.495, accuracy: 0.1)
        XCTAssertEqual(c.longitude, 7.155, accuracy: 0.1)
    }

    func test_stagesAreMonotonicAlongRoute() {
        // Latitude decreases Arnhem→Karlsruhe; longitude increases.
        let lats = (1...5).map {
            StageLocationInterpolator.coordinate(forStage: $0, totalStages: 5, start: arnhem, end: karlsruhe).latitude
        }
        let lons = (1...5).map {
            StageLocationInterpolator.coordinate(forStage: $0, totalStages: 5, start: arnhem, end: karlsruhe).longitude
        }
        XCTAssertEqual(lats, lats.sorted(by: >), "latitude should decrease each stage")
        XCTAssertEqual(lons, lons.sorted(by: <), "longitude should increase each stage")
    }

    func test_singleStage_returnsStart() {
        let c = StageLocationInterpolator.coordinate(forStage: 1, totalStages: 1, start: arnhem, end: karlsruhe)
        XCTAssertEqual(c.latitude, arnhem.latitude, accuracy: 1e-9)
    }

    func test_stageClampedToRange() {
        let over  = StageLocationInterpolator.coordinate(forStage: 99, totalStages: 5, start: arnhem, end: karlsruhe)
        let under = StageLocationInterpolator.coordinate(forStage: -3, totalStages: 5, start: arnhem, end: karlsruhe)
        XCTAssertEqual(over.latitude, karlsruhe.latitude, accuracy: 1e-9, "stage above range → end")
        XCTAssertEqual(under.latitude, arnhem.latitude, accuracy: 1e-9, "stage below range → start")
    }

    func test_coincidentPoints_returnsSamePoint() {
        let c = StageLocationInterpolator.coordinate(forStage: 2, totalStages: 3, start: arnhem, end: arnhem)
        XCTAssertEqual(c.latitude, arnhem.latitude, accuracy: 1e-6)
        XCTAssertEqual(c.longitude, arnhem.longitude, accuracy: 1e-6)
    }
}
