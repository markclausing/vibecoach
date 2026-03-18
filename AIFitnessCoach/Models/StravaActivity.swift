import Foundation

/// Representatie van een Strava activiteit (enkel de benodigde velden voor de AI coach).
/// Decodeert direct vanuit de Strava API JSON response.
struct StravaActivity: Codable, Equatable {
    let id: Int64
    let name: String
    let distance: Double // Afstand in meters
    let moving_time: Int // Tijd in seconden
    let average_heartrate: Double?

    // Optioneel: voeg enum toe voor activity type (Run, Ride, etc.)
    let type: String

    // ISO8601 string, b.v. "2023-10-12T10:00:00Z"
    let start_date: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case distance
        case moving_time
        case average_heartrate
        case type
        case start_date
    }
}
