import Foundation

// MARK: - Epic #70 story 70.3: JSON contract of the per-workout chat

/// One fact the model proposes to remember, as it appears on the wire. `category`
/// stays a raw `String` here — the mapping to `WorkoutFactCategory` happens at the
/// front door in `WorkoutChatResponseParser` (§2), where unknown categories are
/// dropped instead of failing the whole decode.
///
/// Mirror of `ExtractedPreference` (main-chat `newPreferences` contract).
struct ExtractedWorkoutFact: Codable, Equatable {
    let text: String
    let category: String
}

/// The full response object the workout chat expects from the model, per the
/// contract in `WorkoutChatScopeInstruction`.
struct WorkoutChatResponse: Codable, Equatable {
    let reply: String
    let workoutFacts: [ExtractedWorkoutFact]?

    // Defensive decode, same pattern as `SuggestedTrainingPlan`: a response with only
    // {"reply": "..."} or a malformed facts array must not crash the decode — the
    // coach reply always wins over the memory side-channel.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reply        = try c.decode(String.self, forKey: .reply)
        workoutFacts = (try? c.decodeIfPresent([ExtractedWorkoutFact].self, forKey: .workoutFacts)) ?? nil
    }

    init(reply: String, workoutFacts: [ExtractedWorkoutFact]? = nil) {
        self.reply = reply
        self.workoutFacts = workoutFacts
    }
}
