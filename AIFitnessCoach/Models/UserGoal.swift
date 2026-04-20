import Foundation

/// Epic #31 — Sprint 31.2: Type-safe fitnessdoelen voor de onboarding-flow.
///
/// Conform CLAUDE.md §2 gebruiken we nooit ruwe strings voor categorieën —
/// deze enum is de enige bron van waarheid voor de doelen die een nieuwe
/// gebruiker tijdens onboarding kan selecteren. Bewaar de rawValue in
/// UserDefaults of een latere SwiftData `UserPreference` record.
enum UserGoal: String, CaseIterable, Codable, Identifiable {
    case generalFitness = "general_fitness"
    case loseWeight     = "lose_weight"
    case buildMuscle    = "build_muscle"
    case runFaster      = "run_faster"
    case enduranceEvent = "endurance_event"
    case stayHealthy    = "stay_healthy"

    var id: String { rawValue }

    /// Nederlands label voor UI-weergave.
    var title: String {
        switch self {
        case .generalFitness: return "Algemene fitheid"
        case .loseWeight:     return "Afvallen"
        case .buildMuscle:    return "Spieropbouw"
        case .runFaster:      return "Sneller hardlopen"
        case .enduranceEvent: return "Klaar voor een event"
        case .stayHealthy:    return "Gezond blijven"
        }
    }

    /// Korte subtitel die het doel verduidelijkt.
    var subtitle: String {
        switch self {
        case .generalFitness: return "Meer energie en een betere conditie in het dagelijks leven"
        case .loseWeight:     return "Gezond vetpercentage omlaag met een duurzaam plan"
        case .buildMuscle:    return "Krachttraining met progressieve overload"
        case .runFaster:      return "Snellere 5 km / 10 km tijden"
        case .enduranceEvent: return "Marathon, triatlon of een stevige fietstocht"
        case .stayHealthy:    return "Preventief bewegen en blessurevrij blijven"
        }
    }

    /// SF Symbol voor een visuele hint in de UI.
    var iconName: String {
        switch self {
        case .generalFitness: return "figure.mixed.cardio"
        case .loseWeight:     return "scalemass"
        case .buildMuscle:    return "dumbbell.fill"
        case .runFaster:      return "figure.run"
        case .enduranceEvent: return "medal.fill"
        case .stayHealthy:    return "heart.fill"
        }
    }
}
