import Foundation


import SwiftData

/// Representeert een opgeslagen langetermijnvoorkeur of 'harde regel' van de gebruiker.
@Model
final class UserPreference {
    @Attribute(.unique) var id: UUID
    var preferenceText: String
    var createdAt: Date
    var isActive: Bool
    var expirationDate: Date?

    init(id: UUID = UUID(), preferenceText: String, createdAt: Date = Date(), isActive: Bool = true, expirationDate: Date? = nil) {
        self.id = id
        self.preferenceText = preferenceText
        self.createdAt = createdAt
        self.isActive = isActive
        self.expirationDate = expirationDate
    }
}

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
    var targetTRIMP: Double? // Sprint 12.1: Benodigde belasting om dit doel te halen.

    init(id: UUID = UUID(),
         title: String,
         details: String? = nil,
         targetDate: Date,
         createdAt: Date = Date(),
         isCompleted: Bool = false,
         sportType: String? = nil,
         targetTRIMP: Double? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.targetDate = targetDate
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.sportType = sportType
        self.targetTRIMP = targetTRIMP
    }

    /// Berekent of retourneert de Target TRIMP veilig, inclusief fail-safe fallback formule
    var computedTargetTRIMP: Double {
        if let trimp = targetTRIMP, trimp > 0 {
            return trimp
        }
        let days = max(1.0, targetDate.timeIntervalSince(createdAt) / 86400)
        return (days / 7.0) * 350.0
    }
}

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
    var type: String
    var startDate: Date

    /// Berekende Trainingsbelasting (TRIMP) voor deze specifieke activiteit.
    var trimp: Double?

    init(id: String, name: String, distance: Double, movingTime: Int, averageHeartrate: Double?, type: String, startDate: Date, trimp: Double? = nil) {
        self.id = id
        self.name = name
        self.distance = distance
        self.movingTime = movingTime
        self.averageHeartrate = averageHeartrate
        self.type = type
        self.startDate = startDate
        self.trimp = trimp
    }

    /// Vergelijkt robuust of deze activiteit past bij een opgegeven doel-sport (Sprint 12.4).
    /// Dit koppelt Engelse Strava/HealthKit types (zoals "Ride", "VirtualRide") aan Nederlandse doelen (zoals "Fietsen").
    func matchesSportType(_ targetSport: String?) -> Bool {
        guard let target = targetSport?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
            return true // Als er geen specifiek doel is ingesteld, telt elke activiteit mee
        }

        let currentType = type.lowercased()
        let currentName = name.lowercased()

        // Hardlopen Mapping
        if target.contains("hardlopen") || target.contains("run") {
            return currentType.contains("run") || currentType.contains("hardlopen") || currentName.contains("run") || currentName.contains("hardlopen") || currentType == "hkworkoutactivitytyperunning"
        }

        // Fietsen Mapping
        if target.contains("fietsen") || target.contains("wielrennen") || target.contains("ride") || target.contains("cycl") {
            return currentType.contains("ride") || currentType.contains("cycl") || currentType.contains("fiets") || currentName.contains("ride") || currentName.contains("fiets") || currentType == "hkworkoutactivitytypecycling"
        }

        // Zwemmen Mapping
        if target.contains("zwemmen") || target.contains("swim") {
            return currentType.contains("swim") || currentType.contains("zwem") || currentName.contains("swim") || currentName.contains("zwem") || currentType == "hkworkoutactivitytypeswimming"
        }

        // Krachttraining Mapping
        if target.contains("kracht") || target.contains("strength") || target.contains("weight") {
            return currentType.contains("strength") || currentType.contains("weight") || currentType.contains("kracht") || currentName.contains("kracht") || currentType == "hkworkoutactivitytypetraditionalstrengthtraining"
        }

        // Triatlon Mapping (Telt Hardlopen, Fietsen én Zwemmen mee)
        if target.contains("triatlon") || target.contains("triathlon") {
            return matchesSportType("hardlopen") || matchesSportType("fietsen") || matchesSportType("zwemmen")
        }

        // Fallback: generieke string matching
        return currentType.contains(target) || target.contains(currentType) || currentName.contains(target)
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

/// De databron die door de gebruiker is gekozen voor de fysiologische analyses en historie.
enum DataSource: String, CaseIterable, Identifiable {
    case healthKit = "Apple HealthKit"
    case strava = "Strava API"

    var id: String { self.rawValue }
}


/// De individuele suggestie voor een specifieke dag in de komende week.
struct SuggestedWorkout: Codable, Identifiable, Equatable {
    var id: UUID = UUID()

    /// De dag, bijv. "Maandag" of een specifieke datum "2023-11-01"
    let dateOrDay: String

    /// Type activiteit: e.g. "Hardlopen", "Fietsen", of "Rust"
    let activityType: String

    /// Voorgestelde duur in minuten (0 voor rust)
    let suggestedDurationMinutes: Int

    /// Beoogde belasting (TRIMP), 0 voor rust. Soms stuurt Gemini dit als String, of laat hij het weg.
    let targetTRIMP: Int?

    /// Korte toelichting, bijv. "Zone 2 herstelrit" of "Intervaltraining: 5x1000m"
    let description: String

    /// Doel hartslagzone, bijv. "Zone 2"
    let heartRateZone: String?

    /// Doel tempo, bijv. "5:30 min/km"
    let targetPace: String?

    enum CodingKeys: String, CodingKey {
        case dateOrDay
        case activityType
        case suggestedDurationMinutes
        case targetTRIMP
        case description
        case heartRateZone
        case targetPace
    }

    init(id: UUID = UUID(), dateOrDay: String, activityType: String, suggestedDurationMinutes: Int, targetTRIMP: Int?, description: String, heartRateZone: String? = nil, targetPace: String? = nil) {
        self.id = id
        self.dateOrDay = dateOrDay
        self.activityType = activityType
        self.suggestedDurationMinutes = suggestedDurationMinutes
        self.targetTRIMP = targetTRIMP
        self.description = description
        self.heartRateZone = heartRateZone
        self.targetPace = targetPace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateOrDay = try container.decode(String.self, forKey: .dateOrDay)
        activityType = try container.decode(String.self, forKey: .activityType)
        suggestedDurationMinutes = try container.decode(Int.self, forKey: .suggestedDurationMinutes)
        description = try container.decode(String.self, forKey: .description)
        heartRateZone = try container.decodeIfPresent(String.self, forKey: .heartRateZone)
        targetPace = try container.decodeIfPresent(String.self, forKey: .targetPace)

        // Probeer targetTRIMP te decoderen als Int, en anders als String en parse naar Int
        if let intTRIMP = try? container.decodeIfPresent(Int.self, forKey: .targetTRIMP) {
            targetTRIMP = intTRIMP
        } else if let stringTRIMP = try? container.decodeIfPresent(String.self, forKey: .targetTRIMP), let parsedInt = Int(stringTRIMP) {
            targetTRIMP = parsedInt
        } else {
            targetTRIMP = nil
        }
    }
}

/// Structuur om via JSON een nieuw geheugen inclusief optionele verloopdatum te ontvangen.
struct ExtractedPreference: Codable, Equatable {
    let text: String
    let expirationDate: String? // Verwacht formaat: "YYYY-MM-DD"
}

/// De gestructureerde JSON-output (vanuit Gemini) voor een compleet weekschema.
struct SuggestedTrainingPlan: Codable, Equatable {
    let motivation: String
    let workouts: [SuggestedWorkout]
    let newPreferences: [ExtractedPreference]?
}

import SwiftUI

/// Shared state manager for the active training plan.
/// It acts as the single source of truth for both DashboardView and ChatView.
@MainActor
class TrainingPlanManager: ObservableObject {
    @Published var activePlan: SuggestedTrainingPlan?
    @AppStorage("latestSuggestedPlanData") private var latestSuggestedPlanData: Data = Data()

    init() {
        loadPlan()
    }

    /// Loads the plan from AppStorage.
    private func loadPlan() {
        if let decodedPlan = try? JSONDecoder().decode(SuggestedTrainingPlan.self, from: latestSuggestedPlanData) {
            self.activePlan = decodedPlan
        }
    }

    /// Updates the plan, publishes the change, and persists it to AppStorage.
    func updatePlan(_ newPlan: SuggestedTrainingPlan) {
        self.activePlan = newPlan
        if let encoded = try? JSONEncoder().encode(newPlan) {
            latestSuggestedPlanData = encoded
        }
    }
}
