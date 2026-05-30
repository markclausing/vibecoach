import Foundation
import CryptoKit

// MARK: - Epic 40: Deterministic UUIDs for external IDs
//
// `WorkoutSample.workoutUUID` is a `UUID`, designed for HealthKit's UUIDs.
// Strava activities have an `Int64` ID that is not a UUID. To store both sources in
// the same table without a schema change, we derive a **deterministic** UUID for Strava
// records: the same Strava ID always yields the same UUID. That gives type-safe lookup
// without a dual-key path.
//
// Approach: SHA-256 hash of a namespace + the Strava ID, first 16 bytes formatted
// as a UUID. This is conceptually a UUIDv5-like variant — not an RFC 4122 compliant
// UUIDv5 (which requires a specific namespace UUID), but for our internal lookup
// this pragmatic variant is fully sufficient and collision-resistant.

extension UUID {

    /// Derives a deterministic UUID from a Strava activity ID.
    /// Same input → always the same UUID, app-restart-resilient.
    /// - Parameter stravaID: The Strava activity ID as a string (e.g. `"12345678901"`).
    /// - Returns: A UUID serving as a foreign key to this Strava activity.
    static func deterministic(fromStravaID stravaID: String) -> UUID {
        let namespacedInput = "vibecoach.strava.\(stravaID)"
        let data = Data(namespacedInput.utf8)
        let hash = SHA256.hash(data: data)
        let bytes = Array(hash).prefix(16)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// For `ActivityRecord.id`: first try a real UUID parse (HealthKit), otherwise
    /// fall back to the deterministic Strava derivation. One place for the
    /// mapping so all callers (UI query, ingest linking) are consistent.
    static func forActivityRecordID(_ activityID: String) -> UUID {
        if let parsed = UUID(uuidString: activityID) {
            return parsed
        }
        return .deterministic(fromStravaID: activityID)
    }
}
