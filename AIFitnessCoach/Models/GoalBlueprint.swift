import Foundation

// MARK: - Epic 17: Goal-Specific Blueprints — Data Types

/// Ondersteunde blueprint-typen — gedetecteerd via sleutelwoorden in de doeltitel.
enum GoalBlueprintType: String, CaseIterable {
    case marathon     = "marathon"
    case halfMarathon = "half_marathon"
    case cyclingTour  = "cycling_tour"

    /// Sleutelwoorden die in de doeltitel moeten voorkomen voor automatische detectie (lowercase).
    var detectionKeywords: [String] {
        switch self {
        case .marathon:
            return ["marathon"]
        case .halfMarathon:
            return ["halve marathon", "half marathon", "21km", "21 km", "21,1"]
        case .cyclingTour:
            return ["arnhem", "karlsruhe", "cycling tour", "fietstocht", "fietsdoel", "gran fondo", "sportieve rit"]
        }
    }

    var displayName: String {
        switch self {
        case .marathon:     return "Marathon"
        case .halfMarathon: return "Halve Marathon"
        case .cyclingTour:  return "Fietstocht"
        }
    }
}

/// Een kritieke trainingseis die vóór een bepaald moment behaald moet zijn.
/// Onderdeel van een GoalBlueprint — één openstaande eis houdt de milestone rood.
struct EssentialWorkout: Equatable {
    /// Stabiele identifier voor de milestone-check (bijv. "marathon_long_run_32")
    let id: String
    /// Leesbare beschrijving voor UI en AI-context (bijv. "32 km duurloop")
    let description: String
    /// Minimale afstand in meters voor deze eis, of nil als duur leidend is
    let minimumDistanceMeters: Double?
    /// Vereiste sportsoort (type-veilig via SportCategory)
    let requiredSportCategory: SportCategory
    /// Aantal weken vóór de einddatum waarbinnen deze workout voltooid moet zijn
    let mustCompleteByWeeksBefore: Int
}

/// Sportwetenschappelijk trainingsplan voor een specifiek doeltype.
/// Bevat harde regels die — ongeacht AI-output — altijd van toepassing zijn.
struct GoalBlueprint {
    let goalType: GoalBlueprintType
    /// Minimale afstand van de langste duurtraining in meters (bijv. 32.000 voor marathon)
    let minLongRunDistance: Double
    /// Weken vóór de race dat de afbouwperiode (taper) start
    let taperPeriodWeeks: Int
    /// Wekelijkse TRIMP-doelstelling tijdens de opbouwfase
    let weeklyTrimpTarget: Double
    /// Kritieke trainingen die verplicht in het schema moeten voorkomen
    let essentialWorkouts: [EssentialWorkout]
}

/// Voortgangsstatus van één kritieke trainingseis t.o.v. de deadline.
struct MilestoneStatus: Identifiable, Equatable {
    let id: String
    let description: String
    /// True als er een passende activiteit gevonden is die aan de eis voldoet
    let isSatisfied: Bool
    /// Datum waarop de eis behaald werd (alleen ingevuld als isSatisfied == true)
    let satisfiedByDate: Date?
    /// Uiterste datum waarop deze workout gedaan moet zijn (berekend vanuit targetDate)
    let deadline: Date
    /// Aantal weken vóór de race dat deze eis uiterlijk voltooid moet zijn
    let weeksBefore: Int
}

/// Volledige blauwdrukcheck voor één doel: blueprint + alle milestone statussen.
struct BlueprintCheckResult {
    let blueprint: GoalBlueprint
    let goal: FitnessGoal
    let milestones: [MilestoneStatus]

    /// True als alle kritieke eisen waarvan de deadline al verstreken is ook behaald zijn.
    var isOnTrack: Bool {
        milestones
            .filter { $0.deadline < Date() }
            .allSatisfy { $0.isSatisfied }
    }

    var satisfiedCount: Int { milestones.filter { $0.isSatisfied }.count }
    var totalCount: Int { milestones.count }
}
