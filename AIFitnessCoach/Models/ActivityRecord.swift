import Foundation
import SwiftData

/// Een historisch verslag van een activiteit (gesynchroniseerd met externe bronnen zoals Strava of HealthKit).
/// Dit wordt lokaal opgeslagen met SwiftData voor snelle toegang en offline analyses,
/// zoals het berekenen van het atletisch profiel.
@Model
final class ActivityRecord {
    /// De unieke identificatie van de activiteit, vaak afkomstig van de externe provider (zoals Strava ID of HealthKit UUID).
    @Attribute(.unique)
    var id: String

    var name: String
    var distance: Double // Afstand in meters
    var movingTime: Int // Tijd in seconden
    var averageHeartrate: Double?
    var sportCategory: SportCategory // Epic 12 Refactor: Gebruik van type-veilige enum
    var startDate: Date

    /// Berekende Trainingsbelasting (TRIMP) voor deze specifieke activiteit.
    var trimp: Double?

    // Epic 18: Subjectieve Feedback — Rate of Perceived Exertion (1-10) en stemming
    var rpe: Int?    // 1 = heel makkelijk, 10 = maximale inspanning
    var mood: String? // Bijv. "😌", "🟢", "🚀", "🤕", "🥵"

    // Epic 33 Story 33.1: Sessie-Type Taxonomie. Optioneel zodat bestaande records zonder
    // type valide blijven (lightweight migration). Wordt door `SessionClassifier` voorgesteld
    // bij ingest en kan door de gebruiker handmatig worden overruled vanuit `WorkoutAnalysisView`.
    var sessionType: SessionType?

    // Epic 41: True wanneer de bron-activity met een powermeter is gemeten. Voor Strava-records
    // gevuld via `StravaActivity.device_watts`; voor HealthKit-records meestal nil (HK heeft
    // geen device-meta-info). Gebruikt door `ActivityDeduplicator` als sterk signal — een
    // record met power-meter wint van eenzelfde rit zonder.
    var deviceWatts: Bool?

    // Epic 40 Story 40.4: True zodra de gebruiker via `WorkoutAnalysisView` zelf een
    // sessionType heeft gekozen. Beschermt deze keuze tegen `SessionReclassifier`, die
    // anders na een latere stream-backfill (Strava 40.3 / HK DeepSync 32.1) het type
    // automatisch zou herclassificeren op basis van zone-distributie.
    var manualSessionTypeOverride: Bool?

    /// Menselijke naam voor UI en AI-context.
    /// Legacy HealthKit-records bevatten soms 'HealthKit <rawValue>' (bijv. 'HealthKit 52') —
    /// deze property vervangt dat altijd door de leesbare naam van de SportCategory.
    var displayName: String {
        if name.hasPrefix("HealthKit") {
            return sportCategory.workoutName.prefix(1).uppercased() + sportCategory.workoutName.dropFirst()
        }
        return name
    }

    init(id: String, name: String, distance: Double, movingTime: Int, averageHeartrate: Double?, sportCategory: SportCategory, startDate: Date, trimp: Double? = nil, rpe: Int? = nil, mood: String? = nil, sessionType: SessionType? = nil, deviceWatts: Bool? = nil, manualSessionTypeOverride: Bool? = nil) {
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
    }
}

/// Een meting van de hartslag op een specifiek tijdstip
struct HeartRateSample: Codable, Equatable {
    let timestamp: Date
    let bpm: Double
}

/// Details van een voltooide workout inclusief fysiologische data
struct WorkoutDetails: Codable, Equatable {
    let name: String
    let startDate: Date
    let duration: Double
    let averageHeartRate: Double
    let maxHeartRate: Double
    let restingHeartRate: Double
    let heartRateSamples: [HeartRateSample]
}
