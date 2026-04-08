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

// MARK: - Epic 16: Dynamische Periodisering

/// De vier klassieke trainingsperioden van een macrocyclus.
/// Bepaalt welke AI-instructies de coach gebruikt bij het plannen van trainingen.
enum TrainingPhase: String, CaseIterable {
    case baseBuilding = "Base Building"
    case buildPhase   = "Build Phase"
    case peakPhase    = "Peak Phase"
    case tapering     = "Tapering"

    /// Korte beschrijving die zichtbaar is als badge in de UI.
    var displayName: String { rawValue }

    /// Kleur voor de UI-badge
    var color: String {
        switch self {
        case .baseBuilding: return "blue"
        case .buildPhase:   return "orange"
        case .peakPhase:    return "red"
        case .tapering:     return "purple"
        }
    }

    /// Sprint 16.2: Fase-multiplier voor de wekelijkse TRIMP-target.
    /// De lineaire baseline (resterend TRIMP / resterende weken) wordt hiermee gecorrigeerd
    /// zodat de trainingsintensiteit overeenkomt met de fysiologische fase.
    var multiplier: Double {
        switch self {
        case .baseBuilding: return 1.00  // Gewone lineaire baseline
        case .buildPhase:   return 1.15  // 15% meer belasting opbouwen
        case .peakPhase:    return 1.30  // 30% meer — maximale adaptatiefase
        case .tapering:     return 0.60  // 40% minder — rust is de training
        }
    }

    /// Harde AI-instructie die de coach krijgt voor deze fase.
    var aiInstruction: String {
        switch self {
        case .baseBuilding:
            return "Huidige fase: Base Building (>12 weken tot evenement). Instructie: Focus uitsluitend op laag-intensief volume (Zone 1-2). Geen intervaltraining. Bouw de wekelijkse TRIMP geleidelijk op met max. 10% per week. Leg het aerobe fundament."
        case .buildPhase:
            return "Huidige fase: Build Phase (4-12 weken tot evenement). Instructie: Verhoog zowel volume als intensiteit. Introduceer gecontroleerde intervaltraining (Zone 3-4). Wekelijkse TRIMP-stijging max. 12%. Afwisselen tussen belastingsweken en hersteldagen."
        case .peakPhase:
            return "Huidige fase: Peak Phase (2-4 weken tot evenement). Instructie: Maximale trainingsbelasting. Race-specifieke trainingen: tempo's op wedstrijdintensiteit. Hoge TRIMP, maar wel gecontroleerde hersteldagen inplannen. Dit is de laatste kans voor adaptatie."
        case .tapering:
            return "Huidige fase: Tapering (<2 weken tot evenement). KRITIEKE INSTRUCTIE: Verlaag het wekelijkse TRIMP-volume met minimaal 40%. Geen lange zware trainingen meer. Alleen korte, lichte sessies (max. 45 min) om de benen scherp te houden. De atleet is klaar — rust is nu de training."
        }
    }

    /// Berekent de fase op basis van het aantal weken tot de doeldatum.
    static func calculate(weeksRemaining: Double) -> TrainingPhase {
        switch weeksRemaining {
        case ..<2:    return .tapering
        case 2..<4:   return .peakPhase
        case 4..<12:  return .buildPhase
        default:      return .baseBuilding
        }
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
    var sportCategory: SportCategory?
    var targetTRIMP: Double? // Sprint 12.1: Benodigde belasting om dit doel te halen.

    init(id: UUID = UUID(),
         title: String,
         details: String? = nil,
         targetDate: Date,
         createdAt: Date = Date(),
         isCompleted: Bool = false,
         sportCategory: SportCategory? = nil,
         targetTRIMP: Double? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.targetDate = targetDate
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.sportCategory = sportCategory
        self.targetTRIMP = targetTRIMP
    }

    /// Huidige trainingsfase van dit doel op basis van weken resterend (Epic 16).
    /// Retourneert nil als het doel is afgerond of al verlopen.
    var currentPhase: TrainingPhase? {
        guard !isCompleted, Date() < targetDate else { return nil }
        let weeksRemaining = targetDate.timeIntervalSince(Date()) / (7 * 86400)
        return TrainingPhase.calculate(weeksRemaining: weeksRemaining)
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
    var sportCategory: SportCategory // Epic 12 Refactor: Gebruik van type-veilige enum
    var startDate: Date

    /// Berekende Trainingsbelasting (TRIMP) voor deze specifieke activiteit.
    var trimp: Double?

    // Epic 18: Subjectieve Feedback — Rate of Perceived Exertion (1-10) en stemming
    var rpe: Int?    // 1 = heel makkelijk, 10 = maximale inspanning
    var mood: String? // Bijv. "😌", "🟢", "🚀", "🤕", "🥵"

    init(id: String, name: String, distance: Double, movingTime: Int, averageHeartrate: Double?, sportCategory: SportCategory, startDate: Date, trimp: Double? = nil, rpe: Int? = nil, mood: String? = nil) {
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

/// Gestandaardiseerde sportcategorieën voor de applicatie (Epic 12 Refactor).
enum SportCategory: String, Codable, CaseIterable, Identifiable {
    case running = "running"
    case cycling = "cycling"
    case swimming = "swimming"
    case strength = "strength"
    case walking = "walking"
    case triathlon = "triathlon"
    case other = "other"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .running: return "Hardlopen"
        case .cycling: return "Wielrennen"
        case .swimming: return "Zwemmen"
        case .strength: return "Krachttraining"
        case .walking: return "Wandelen"
        case .triathlon: return "Triatlon"
        case .other: return "Anders"
        }
    }

    /// Mapt direct vanaf een HealthKit type voor robuustheid in plaats van string beschrijvingen
    static func from(hkType: UInt) -> SportCategory {
        // We gebruiken UInt omdat we HealthKit hier wellicht niet expliciet willen importeren op elke plek
        // 13 = cycling, 37 = running, 52 = walking, 16 = elliptical, 50 = traditionalStrengthTraining, 82 = swimming
        switch hkType {
        case 13: return .cycling
        case 37: return .running
        case 46, 82: return .swimming
        case 50, 59: return .strength
        case 52: return .walking
        case 83: return .triathlon
        default: return .other
        }
    }

    /// Factory methode om ruwe externe API strings (zoals "Ride")
    /// robuust te mappen naar de gestandaardiseerde `SportCategory`.
    static func from(rawString: String?) -> SportCategory {
        guard let raw = rawString?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .other
        }

        if raw.contains("run") || raw.contains("hardlopen") || raw == "hkworkoutactivitytyperunning" {
            return .running
        }

        if raw.contains("ride") || raw.contains("cycl") || raw.contains("fiets") || raw.contains("wielrennen") || raw == "hkworkoutactivitytypecycling" {
            return .cycling
        }

        if raw.contains("swim") || raw.contains("zwem") || raw == "hkworkoutactivitytypeswimming" {
            return .swimming
        }

        if raw.contains("strength") || raw.contains("weight") || raw.contains("kracht") || raw == "hkworkoutactivitytypetraditionalstrengthtraining" {
            return .strength
        }

        if raw.contains("walk") || raw.contains("wandelen") || raw == "hkworkoutactivitytypewalking" {
            return .walking
        }

        if raw.contains("triathlon") || raw.contains("triatlon") {
            return .triathlon
        }

        return .other
    }
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
        // Gemini stuurt null voor rustdagen — decodeIfPresent met fallback naar 0
        suggestedDurationMinutes = (try? container.decodeIfPresent(Int.self, forKey: .suggestedDurationMinutes)) ?? 0
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

/// Slaat de dagelijkse Readiness Score op, berekend op basis van slaap en HRV (Epic 14).
/// Er wordt maximaal één record per dag bewaard — upsert via de ReadinessService.
@Model
final class DailyReadiness {
    /// Genormaliseerd naar het begin van de dag (00:00:00) voor consistente opslag en queries.
    var date: Date
    var sleepHours: Double
    /// Gemiddelde HRV van de afgelopen nacht in milliseconden.
    var hrv: Double
    /// De berekende Vibe/Readiness Score, 0 (volledig overtraind/uitgeput) t/m 100 (optimaal).
    var readinessScore: Int

    init(date: Date, sleepHours: Double, hrv: Double, readinessScore: Int) {
        self.date = Calendar.current.startOfDay(for: date)
        self.sleepHours = sleepHours
        self.hrv = hrv
        self.readinessScore = readinessScore
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
