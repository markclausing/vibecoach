import Foundation
import SwiftData

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
