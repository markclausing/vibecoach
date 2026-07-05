import Foundation

/// Epic #70 story 70.3: pure parsing of the workout-chat model response.
///
/// Mirror of `CoachResponseParser` (story 65.3): markdown/brace cleanup is reused
/// from there, the decode targets `WorkoutChatResponse`, and the raw `category`
/// strings are mapped to `WorkoutFactCategory` at the front door (§2) — an unknown
/// category drops that fact, never the reply.
///
/// Fallback contract: when the response is no decodable JSON at all, the whole
/// (trimmed) raw text becomes the reply with zero facts. The coach reply must never
/// be lost to a JSON hiccup; worst case the user sees unpolished text and no fact
/// is remembered.
enum WorkoutChatResponseParser {

    /// One fact that survived the front-door mapping — typed, ready for insertion
    /// as a `WorkoutChatFact` by the SwiftData-owning view.
    struct DistilledFact: Equatable {
        let text: String
        let category: WorkoutFactCategory
    }

    /// The outcome of parsing one raw model response.
    struct ParsedResponse: Equatable {
        let reply: String
        let facts: [DistilledFact]
    }

    /// - Parameters:
    ///   - rawResponse: The raw model output (may be nil/empty or markdown-fenced).
    ///   - fallbackMessage: Shown when the model returned nothing usable at all.
    static func parse(rawResponse: String?, fallbackMessage: String) -> ParsedResponse {
        guard let raw = rawResponse?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return ParsedResponse(reply: fallbackMessage, facts: [])
        }

        let cleaned = CoachResponseParser.extractCleanJSON(from: raw)
        guard let data = cleaned.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(WorkoutChatResponse.self, from: data) else {
            // Not the contract JSON — keep the full raw text as the reply (see above).
            AppLoggers.coach.debug("Workout-chat response not decodable as contract JSON (\(raw.count, privacy: .public) chars) — falling back to plain reply")
            return ParsedResponse(reply: raw, facts: [])
        }

        let facts: [DistilledFact] = (decoded.workoutFacts ?? []).compactMap { fact in
            let text = fact.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            guard let category = WorkoutFactCategory(rawValue: fact.category) else {
                // §2 front door: unknown category → fact dropped, reply unaffected.
                AppLoggers.coach.debug("Workout-chat fact dropped: unknown category '\(fact.category, privacy: .public)'")
                return nil
            }
            return DistilledFact(text: text, category: category)
        }

        let reply = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedResponse(reply: reply.isEmpty ? fallbackMessage : reply, facts: facts)
    }
}
