import Foundation
import SwiftData

/// Samenvatting van het berekende profiel
struct AthleticProfile {
    var peakDistanceInMeters: Double
    var peakDurationInSeconds: Int
    var averageWeeklyVolumeInSeconds: Int
    var daysSinceLastTraining: Int
}

/// Verantwoordelijk voor het berekenen van het atleetprofiel op basis van historische gegevens in SwiftData.
@MainActor
class AthleticProfileManager {

    /// Berekent het profiel op basis van de aanwezige `ActivityRecord` elementen.
    /// - Parameter context: De `ModelContext` van de app om gegevens uit te lezen.
    /// - Returns: Een berekend `AthleticProfile` of nil als er onvoldoende data is.
    func calculateProfile(context: ModelContext) throws -> AthleticProfile? {
        // Haal alle ActivityRecords op (dit zou ideaal gefilterd en gesorteerd kunnen worden op database-niveau,
        // maar voor dit MVP berekenen we het lokaal).
        let fetchDescriptor = FetchDescriptor<ActivityRecord>()
        let allActivities = try context.fetch(fetchDescriptor)

        guard !allActivities.isEmpty else {
            return nil
        }

        // 1. Piekprestatie (langste afstand en langste tijd over de gehele dataset)
        let peakDistance = allActivities.max(by: { $0.distance < $1.distance })?.distance ?? 0.0
        let peakDuration = allActivities.max(by: { $0.movingTime < $1.movingTime })?.movingTime ?? 0

        // 2. Dagen sinds de laatste training
        let mostRecentActivity = allActivities.max(by: { $0.startDate < $1.startDate })
        let daysSinceLast: Int
        if let recentActivity = mostRecentActivity {
            let components = Calendar.current.dateComponents([.day], from: recentActivity.startDate, to: Date())
            daysSinceLast = components.day ?? 0
        } else {
            daysSinceLast = 0
        }

        // 3. Wekelijks gemiddeld volume van de afgelopen 4 weken
        let now = Date()
        guard let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: now) else {
            return AthleticProfile(peakDistanceInMeters: peakDistance,
                                   peakDurationInSeconds: peakDuration,
                                   averageWeeklyVolumeInSeconds: 0,
                                   daysSinceLastTraining: daysSinceLast)
        }

        let recentActivities = allActivities.filter { $0.startDate >= fourWeeksAgo }
        let totalVolumeRecent = recentActivities.reduce(0) { $0 + $1.movingTime }
        let averageWeeklyVolume = totalVolumeRecent / 4 // we delen door 4 omdat we precies 4 weken terugkijken

        return AthleticProfile(
            peakDistanceInMeters: peakDistance,
            peakDurationInSeconds: peakDuration,
            averageWeeklyVolumeInSeconds: averageWeeklyVolume,
            daysSinceLastTraining: max(0, daysSinceLast) // Voor het geval het in de toekomst staat door tijdzones
        )
    }
}
