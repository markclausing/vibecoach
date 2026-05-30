import Foundation
import SwiftData

/// A historical record of an activity (synced with external sources like Strava or HealthKit).
/// This is stored locally with SwiftData for fast access and offline analyses,
/// such as computing the athletic profile.
@Model
final class ActivityRecord {
    /// The unique identifier of the activity, often from the external provider (such as a Strava ID or HealthKit UUID).
    @Attribute(.unique)
    var id: String

    var name: String
    var distance: Double // Distance in metres
    var movingTime: Int // Time in seconds
    var averageHeartrate: Double?
    var sportCategory: SportCategory // Epic 12 refactor: use of a type-safe enum
    var startDate: Date

    /// Computed Training Load (TRIMP) for this specific activity.
    var trimp: Double?

    // Epic 18: subjective feedback — Rate of Perceived Exertion (1-10) and mood
    var rpe: Int?    // 1 = very easy, 10 = maximal effort
    var mood: String? // e.g. "😌", "🟢", "🚀", "🤕", "🥵"

    // Epic 33 Story 33.1: session-type taxonomy. Optional so existing records without
    // a type stay valid (lightweight migration). Proposed by `SessionClassifier`
    // at ingest and can be manually overridden by the user from `WorkoutAnalysisView`.
    var sessionType: SessionType?

    // Epic 41: true when the source activity was measured with a power meter. For Strava records
    // filled via `StravaActivity.device_watts`; for HealthKit records usually nil (HK has
    // no device meta-info). Used by `ActivityDeduplicator` as a strong signal — a
    // record with a power meter beats the same ride without one.
    var deviceWatts: Bool?

    // Epic 40 Story 40.4: true once the user has chosen a sessionType themselves via
    // `WorkoutAnalysisView`. Protects this choice from `SessionReclassifier`, which
    // would otherwise reclassify the type automatically based on zone distribution
    // after a later stream backfill (Strava 40.3 / HK DeepSync 32.1).
    var manualSessionTypeOverride: Bool?

    // Epic 49: ambient temperature and humidity at the time of the workout.
    // Filled from `HKMetadataKeyWeatherTemperature` / `HKMetadataKeyWeatherHumidity`
    // if HealthKit has them (iPhone present during the workout). Nil for records without
    // metadata or for Strava-only rides. Passed by `WorkoutInsightService` as
    // context to the coach so heat/humidity explains heat-related
    // patterns (drift, decoupling) without the coach having to ask.
    var temperatureCelsius: Double?
    var humidityPercent: Double?

    // Epic #52: GPS start coordinates. Filled from `StravaActivity.start_latlng`
    // at ingest (see `HistoricalWeatherService.enrichRecord`); for HK-only rides
    // currently nil — the Coach analysis then falls back to the single-point snapshot
    // above. Needed to be able to fetch the hourly weather range at later Coach calls
    // (peak/avg over [start, end]) without querying the Strava API again.
    // Pure addition schema V3 → V4 (lightweight migration).
    var startLatitude: Double?
    var startLongitude: Double?

    /// Human-readable name for UI and AI context.
    /// Legacy HealthKit records sometimes contain 'HealthKit <rawValue>' (e.g. 'HealthKit 52') —
    /// this property always replaces that with the readable name of the SportCategory.
    var displayName: String {
        if name.hasPrefix("HealthKit") {
            return sportCategory.workoutName.prefix(1).uppercased() + sportCategory.workoutName.dropFirst()
        }
        return name
    }

    init(id: String, name: String, distance: Double, movingTime: Int, averageHeartrate: Double?, sportCategory: SportCategory, startDate: Date, trimp: Double? = nil, rpe: Int? = nil, mood: String? = nil, sessionType: SessionType? = nil, deviceWatts: Bool? = nil, manualSessionTypeOverride: Bool? = nil, temperatureCelsius: Double? = nil, humidityPercent: Double? = nil, startLatitude: Double? = nil, startLongitude: Double? = nil) {
        self.id = id
        self.name = name
        self.distance = distance
        self.movingTime = movingTime
        self.averageHeartrate = averageHeartrate
        self.sportCategory = sportCategory
        self.startDate = startDate
        self.trimp = trimp
        self.rpe = rpe
        self.mood = mood
        self.sessionType = sessionType
        self.deviceWatts = deviceWatts
        self.manualSessionTypeOverride = manualSessionTypeOverride
        self.temperatureCelsius = temperatureCelsius
        self.humidityPercent = humidityPercent
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
    }
}

/// A measurement of heart rate at a specific moment.
struct HeartRateSample: Codable, Equatable {
    let timestamp: Date
    let bpm: Double
}

/// Details of a completed workout including physiological data.
struct WorkoutDetails: Codable, Equatable {
    let name: String
    let startDate: Date
    let duration: Double
    let averageHeartRate: Double
    let maxHeartRate: Double
    let restingHeartRate: Double
    let heartRateSamples: [HeartRateSample]
}
