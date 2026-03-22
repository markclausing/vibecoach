import Foundation

/// De individuele suggestie voor een specifieke dag in de komende week.
struct SuggestedWorkout: Codable, Identifiable, Equatable {
    var id: UUID = UUID()

    /// De dag, bijv. "Maandag" of een specifieke datum "2023-11-01"
    let dateOrDay: String

    /// Type activiteit: e.g. "Hardlopen", "Fietsen", of "Rust"
    let activityType: String

    /// Voorgestelde duur in minuten (0 voor rust)
    let suggestedDurationMinutes: Int

    /// Beoogde belasting (TRIMP), 0 voor rust
    let targetTRIMP: Int

    /// Korte toelichting, bijv. "Zone 2 herstelrit" of "Intervaltraining: 5x1000m"
    let description: String

    enum CodingKeys: String, CodingKey {
        case dateOrDay
        case activityType
        case suggestedDurationMinutes
        case targetTRIMP
        case description
    }
}

/// De gestructureerde JSON-output (vanuit Gemini) voor een compleet weekschema.
struct SuggestedTrainingPlan: Codable, Equatable {
    let motivation: String
    let workouts: [SuggestedWorkout]
}
