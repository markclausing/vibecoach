import Foundation
import SwiftData

/// Represents a user's fitness goal.
/// Dit model wordt opgeslagen in SwiftData om lokale doelen bij te houden.
@Model
final class FitnessGoal {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String?
    var targetDate: Date
    var createdAt: Date
    var isCompleted: Bool
    var sportType: String?

    init(id: UUID = UUID(),
         title: String,
         details: String? = nil,
         targetDate: Date,
         createdAt: Date = Date(),
         isCompleted: Bool = false,
         sportType: String? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.targetDate = targetDate
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.sportType = sportType
    }
}

/// Een historisch verslag van een activiteit (gesynchroniseerd met externe bronnen zoals Strava).
/// Dit wordt lokaal opgeslagen met SwiftData voor snelle toegang en offline analyses,
/// zoals het berekenen van het atletisch profiel.
@Model
final class ActivityRecord {
    /// De unieke identificatie van de activiteit, vaak afkomstig van de externe provider (zoals Strava ID).
    @Attribute(.unique)
    var id: Int64

    var name: String
    var distance: Double // Afstand in meters
    var movingTime: Int // Tijd in seconden
    var averageHeartrate: Double?
    var type: String
    var startDate: Date

    init(id: Int64, name: String, distance: Double, movingTime: Int, averageHeartrate: Double?, type: String, startDate: Date) {
        self.id = id
        self.name = name
        self.distance = distance
        self.movingTime = movingTime
        self.averageHeartrate = averageHeartrate
        self.type = type
        self.startDate = startDate
    }
}

/// Een meting van de hartslag op een specifiek tijdstip
struct HeartRateSample: Codable, Equatable {
    let timestamp: Date
    let bpm: Double
}

/// Details van een voltooide workout inclusief fysiologische data
struct WorkoutDetails: Codable, Equatable {
    let duration: Double
    let averageHeartRate: Double
    let maxHeartRate: Double
    let restingHeartRate: Double
    let heartRateSamples: [HeartRateSample]
}
