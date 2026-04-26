import Foundation
import CryptoKit

// MARK: - Epic 40: Deterministische UUID's voor externe ID's
//
// `WorkoutSample.workoutUUID` is een `UUID`, ontworpen voor HealthKit's UUID's.
// Strava-activities hebben een `Int64`-ID die geen UUID is. Om beide bronnen in
// dezelfde tabel te kunnen opslaan zonder schema-wijziging, leiden we voor Strava-
// records een **deterministische** UUID af: zelfde Strava-ID levert altijd dezelfde
// UUID op. Dat geeft type-veilige lookup zonder dual-key-pad.
//
// Aanpak: SHA-256 hash van een namespace + de Strava-ID, eerste 16 bytes geformatteerd
// als UUID. Dit is conceptueel een UUIDv5-achtige variant — geen RFC 4122 compliant
// UUIDv5 (die vereist een specifieke namespace-UUID), maar voor onze interne lookup
// is deze pragmatische variant volledig sufficient en collision-resistant.

extension UUID {

    /// Leidt een deterministische UUID af van een Strava-activity-ID.
    /// Zelfde input → altijd zelfde UUID, app-restart-bestendig.
    /// - Parameter stravaID: De Strava-activity-ID als string (bv. `"12345678901"`).
    /// - Returns: UUID die als foreign key naar deze Strava-activity dient.
    static func deterministic(fromStravaID stravaID: String) -> UUID {
        let namespacedInput = "vibecoach.strava.\(stravaID)"
        let data = Data(namespacedInput.utf8)
        let hash = SHA256.hash(data: data)
        let bytes = Array(hash).prefix(16)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2],  bytes[3],
            bytes[4], bytes[5], bytes[6],  bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Voor `ActivityRecord.id`: probeer eerst echte UUID-parse (HealthKit), val
    /// anders terug op de deterministische Strava-afleiding. Eén plek voor de
    /// mapping zodat alle callers (UI-query, ingest-koppeling) consistent zijn.
    static func forActivityRecordID(_ activityID: String) -> UUID {
        if let parsed = UUID(uuidString: activityID) {
            return parsed
        }
        return .deterministic(fromStravaID: activityID)
    }
}
