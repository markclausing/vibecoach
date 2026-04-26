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

    /// Epic 40: Strava-vlag die aangeeft of de activity met een powermeter gemeten is.
    /// Optioneel + decodeIfPresent → backwards-compat met bestaande caches/fixtures.
    /// Filter voor `fetchActivityStreams`-trigger: alleen ritten met `device_watts == true`.
    let device_watts: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case distance
        case moving_time
        case average_heartrate
        case type
        case start_date
        case device_watts
    }

    init(id: Int64,
         name: String,
         distance: Double,
         moving_time: Int,
         average_heartrate: Double?,
         type: String,
         start_date: String,
         device_watts: Bool? = nil) {
        self.id = id
        self.name = name
        self.distance = distance
        self.moving_time = moving_time
        self.average_heartrate = average_heartrate
        self.type = type
        self.start_date = start_date
        self.device_watts = device_watts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(Int64.self,    forKey: .id)
        name              = try c.decode(String.self,   forKey: .name)
        distance          = try c.decode(Double.self,   forKey: .distance)
        moving_time       = try c.decode(Int.self,      forKey: .moving_time)
        average_heartrate = try c.decodeIfPresent(Double.self, forKey: .average_heartrate)
        type              = try c.decode(String.self,   forKey: .type)
        start_date        = try c.decode(String.self,   forKey: .start_date)
        device_watts      = try c.decodeIfPresent(Bool.self, forKey: .device_watts)
    }
}

// MARK: - Epic 40: Strava Streams API
//
// `/activities/{id}/streams?keys=watts,cadence,heartrate,velocity_smooth,time&key_by_type=true`
// retourneert een dictionary van stream-naam naar `StravaStream`. Niet alle streams zijn
// altijd aanwezig — bv. `watts` ontbreekt als de rit niet met een powermeter gemeten is.

/// Eén stream uit de Strava Streams API. Bevat een lineaire `data`-array waarvan de
/// index aansluit op de `time`-stream.
struct StravaStream: Codable, Equatable {
    let data: [Double]
    let series_type: String?
    let original_size: Int?
    let resolution: String?

    enum CodingKeys: String, CodingKey {
        case data, series_type, original_size, resolution
    }

    init(data: [Double], series_type: String? = nil, original_size: Int? = nil, resolution: String? = nil) {
        self.data = data
        self.series_type = series_type
        self.original_size = original_size
        self.resolution = resolution
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data          = try c.decode([Double].self, forKey: .data)
        series_type   = try c.decodeIfPresent(String.self, forKey: .series_type)
        original_size = try c.decodeIfPresent(Int.self,    forKey: .original_size)
        resolution    = try c.decodeIfPresent(String.self, forKey: .resolution)
    }
}

/// Volledige stream-set voor één Strava-activity. `time` is altijd nodig voor
/// timestamp-mapping; de andere streams zijn optioneel.
struct StravaStreamSet: Codable, Equatable {
    let time: StravaStream?
    let watts: StravaStream?
    let cadence: StravaStream?
    let heartrate: StravaStream?
    let velocity_smooth: StravaStream?

    enum CodingKeys: String, CodingKey {
        case time, watts, cadence, heartrate, velocity_smooth
    }
}
