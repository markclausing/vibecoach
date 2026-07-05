import Foundation

/// Epic #70 story 70.2: scope restriction for the per-workout chat ("Discuss this
/// workout"), the narrower sibling of `ChatScopeInstruction` (Epic #51-A1).
///
/// The main Coach tab handles the full coaching scope; this chat is anchored to ONE
/// workout. Allowed topics are exactly (a) that workout and (b) the user's condition
/// today/this week insofar as it explains or affects it. Everything else — including
/// general training-plan questions that *are* in scope on the Coach tab — gets a
/// redirect there, so plan changes keep flowing through one place.
///
/// The same constant also carries the JSON response contract (`reply` +
/// `workoutFacts`): instruction and parser (`WorkoutChatResponseParser`) are two
/// sides of one contract, so they are tested against the same literals
/// (CLAUDE.md §13 structural-marker rule).
///
/// Pure Swift and parameter-injected (no AppStorage reads beyond the shared
/// `AppLanguage` accessor, mirroring `ChatScopeInstruction`) so the text is
/// unit-testable without a view model.
enum WorkoutChatScopeInstruction {

    /// Category literals of the JSON contract. Single source shared with the parser
    /// tests so a rename here fails a test instead of silently breaking distillation.
    static let categoryLiterals = "feel|route|dayCondition"

    /// Builds the full system instruction for one workout's chat.
    /// - Parameters:
    ///   - workoutName: Display name of the workout (e.g. "Zondagrit").
    ///   - workoutDate: Start date; formatted with the prompt formatter (stays `nl_NL`, §13).
    ///   - sportRaw: `SportCategory.rawValue` — the prompt term convention (§13 prompt-vs-UI split).
    ///   - sessionTypeLabel: Optional session-type label (e.g. "Recovery"), appended when known.
    static func text(workoutName: String,
                     workoutDate: Date,
                     sportRaw: String,
                     sessionTypeLabel: String?) -> String {
        let replyLanguage = AppLanguage.currentPromptLanguageName
        let dateStr = AppDateFormatters.promptStyle(.medium).string(from: workoutDate)
        let sessionStr = sessionTypeLabel.map { ", session type: \($0)" } ?? ""
        return """
        CRITICAL RULE — SCOPE (Epic #70):
        You are the user's fitness coach, discussing ONE specific workout:
        "\(workoutName)" (\(sportRaw), \(dateStr)\(sessionStr)).

        Only handle topics that directly relate to:
        - THIS workout: how it felt, execution and pacing, the route/course, weather and conditions, equipment used, comparison with similar sessions
        - The user's physical or mental condition today or this week insofar as it explains or affects this workout (sleep, stress, energy, niggles, soreness)

        For EVERYTHING else — general training plans, goal changes, plan resets, other workouts, general knowledge, coding help, medical advice outside the sport context — respond with EXACTLY this framing (phrased in your own words, in \(replyLanguage); the sentence below is only the template):
        "Dit gesprek gaat over deze workout en hoe je je vandaag of deze week voelt. Voor je trainingsplan en andere coachvragen kun je terecht op het Coach-tabblad."

        Do NOT attempt to answer the off-topic question anyway, not even partially or as a side remark.

        Exception: a seemingly off-topic remark with a clear link to this workout or to the user's current condition (e.g. new shoes that felt odd, a stressful work week weighing on the legs) may be handled in this workout's context.

        RESPONSE FORMAT — respond with ONLY a JSON object, no markdown fences, matching exactly:
        {"reply": "<your coaching reply, in \(replyLanguage)>", "workoutFacts": [{"text": "<durable fact>", "category": "\(categoryLiterals)"}]}

        Rules for workoutFacts:
        - Distil ONLY durable, plan-relevant facts the USER stated: how the workout felt relative to its load (category "feel"), route/course feedback (category "route"), or a condition of the day/week that explains a deviation (category "dayCondition").
        - Write each fact as one short self-contained sentence in \(replyLanguage), understandable months later without this conversation.
        - No chit-chat, no restated metrics, never invent facts the user did not state.
        - Use an empty array when nothing is worth remembering: "workoutFacts": []
        """
    }
}
