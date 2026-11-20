import XCTest
@testable import AIFitnessCoach

/// Regression guard for Strava's switch to 64-bit activity identifiers
/// (announced for June 1, 2027). Strava warns that languages which cannot
/// safely hold 64-bit integers should switch to `id_str`; Swift's `Int64`
/// + `JSONDecoder` already handle the full range exactly, so we keep reading
/// the numeric `id`. These tests pin that: if anyone ever narrows the type
/// (`Int32`) or routes it through a `Double` (precision loss above 2^53),
/// they fail instead of silently corrupting IDs on device.
final class StravaActivityDecodingTests: XCTestCase {

    /// 2^53 + 1 — the first integer a `Double` cannot represent exactly.
    private let beyondDoublePrecision: Int64 = 9_007_199_254_740_993

    private func activityJSON(id: String) -> Data {
        Data("""
        {
          "id": \(id),
          "id_str": "\(id)",
          "name": "Long run",
          "distance": 30000.0,
          "moving_time": 10800,
          "type": "Run",
          "start_date": "2027-06-02T07:00:00Z"
        }
        """.utf8)
    }

    func testDecodesIDBeyondDoublePrecisionExactly() throws {
        let activity = try JSONDecoder().decode(
            StravaActivity.self,
            from: activityJSON(id: String(beyondDoublePrecision))
        )
        XCTAssertEqual(activity.id, beyondDoublePrecision,
                       "A 64-bit Strava ID must survive decoding without rounding")
    }

    func testDecodesInt64MaxExactly() throws {
        let activity = try JSONDecoder().decode(
            StravaActivity.self,
            from: activityJSON(id: String(Int64.max))
        )
        XCTAssertEqual(activity.id, Int64.max)
    }

    /// Mirrors the production path: `AutoSyncCoordinator` stores the ID as
    /// `String(activity.id)` in `ActivityRecord.id`, and `DashboardMaintenanceRunner`
    /// parses it back with `Int64(_:)` for the streams backfill.
    func testStoredStringIDRoundTripsToSameInt64() throws {
        let activity = try JSONDecoder().decode(
            StravaActivity.self,
            from: activityJSON(id: String(beyondDoublePrecision))
        )
        let storedID = String(activity.id)
        XCTAssertEqual(storedID, "9007199254740993")
        XCTAssertEqual(Int64(storedID), beyondDoublePrecision)
    }

    /// Two IDs one apart beyond 2^53 collapse to the same `Double`; they must
    /// still map to distinct deterministic UUIDs, or samples of two activities mix.
    func testAdjacent64BitIDsYieldDistinctDeterministicUUIDs() throws {
        let a = try JSONDecoder().decode(
            StravaActivity.self, from: activityJSON(id: String(beyondDoublePrecision - 1)))
        let b = try JSONDecoder().decode(
            StravaActivity.self, from: activityJSON(id: String(beyondDoublePrecision)))
        XCTAssertNotEqual(
            UUID.deterministic(fromStravaID: String(a.id)),
            UUID.deterministic(fromStravaID: String(b.id))
        )
    }
}
