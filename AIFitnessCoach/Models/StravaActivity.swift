import Foundation

/// Representation of a Strava activity (only the fields needed for the AI coach).
/// Decodes directly from the Strava API JSON response.
struct StravaActivity: Codable, Equatable {
    let id: Int64
    let name: String
    let distance: Double // Distance in metres
    let moving_time: Int // Time in seconds
    let average_heartrate: Double?

    // Optional: add an enum for activity type (Run, Ride, etc.)
    let type: String

    // ISO8601 string, e.g. "2023-10-12T10:00:00Z"
    let start_date: String

    /// Epic 40: Strava flag indicating whether the activity was measured with a power meter.
    /// Optional + decodeIfPresent → backwards-compat with existing caches/fixtures.
    /// Filter for the `fetchActivityStreams` trigger: only rides with `device_watts == true`.
    let device_watts: Bool?

    /// Epic #50: GPS start coordinates as `[lat, lng]`. Strava provides this field for
    /// all outdoor activities with GPS — empty array or nil for indoor/manual.
    /// Used to fetch historical weather data via the Open-Meteo archive API
    /// for rides without iPhone presence (Garmin/bike-computer-only).
    let start_latlng: [Double]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case distance
        case moving_time
        case average_heartrate
        case type
        case start_date
        case device_watts
        case start_latlng
    }

    init(id: Int64,
         name: String,
         distance: Double,
         moving_time: Int,
         average_heartrate: Double?,
         type: String,
         start_date: String,
         device_watts: Bool? = nil,
         start_latlng: [Double]? = nil) {
        self.id = id
        self.name = name
        self.distance = distance
        self.moving_time = moving_time
        self.average_heartrate = average_heartrate
        self.type = type
        self.start_date = start_date
        self.device_watts = device_watts
        self.start_latlng = start_latlng
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(Int64.self, forKey: .id)
        name              = try c.decode(String.self, forKey: .name)
        distance          = try c.decode(Double.self, forKey: .distance)
        moving_time       = try c.decode(Int.self, forKey: .moving_time)
        average_heartrate = try c.decodeIfPresent(Double.self, forKey: .average_heartrate)
        type              = try c.decode(String.self, forKey: .type)
        start_date        = try c.decode(String.self, forKey: .start_date)
        device_watts      = try c.decodeIfPresent(Bool.self, forKey: .device_watts)
        // Strava returns an empty array `[]` for indoor — normalise to nil so
        // callers have one coherent "no location" signal.
        let raw = try c.decodeIfPresent([Double].self, forKey: .start_latlng)
        start_latlng = (raw?.count == 2) ? raw : nil
    }
}

// MARK: - Epic 40: Strava Streams API
//
// `/activities/{id}/streams?keys=watts,cadence,heartrate,velocity_smooth,time&key_by_type=true`
// returns a dictionary of stream name to `StravaStream`. Not all streams are
// always present — e.g. `watts` is missing if the ride was not measured with a power meter.

/// One stream from the Strava Streams API. Contains a linear `data` array whose
/// index aligns with the `time` stream.
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
        original_size = try c.decodeIfPresent(Int.self, forKey: .original_size)
        resolution    = try c.decodeIfPresent(String.self, forKey: .resolution)
    }
}

/// Full stream set for one Strava activity. `time` is always needed for
/// timestamp mapping; the other streams are optional.
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
