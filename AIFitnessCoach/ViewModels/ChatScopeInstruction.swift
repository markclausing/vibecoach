import Foundation

/// Epic #51-A1: scope restriction placed explicitly at the top of the system
/// instruction so the coach consistently refuses off-topic questions.
///
/// Gemini's safety filters catch extreme content, but everyday off-topic
/// questions ("what is the capital of France", "write code for X", "give medical
/// advice about drug X") were previously just answered — conflicting with the
/// coach positioning and with liability risk for medical advice outside sport.
///
/// Pure-Swift constant so the text is testable independently of `ChatViewModel`
/// (no MainActor dependencies, no Gemini-SDK types in scope).
enum ChatScopeInstruction {

    /// The scope instruction is prepended by `ChatViewModel.buildGenerativeModel()`
    /// to the existing `systemInstruction` string so it's evaluated by the model
    /// before all other KRITIEKE REGEL sections.
    /// Epic #37 story 37.3: computed so the reply-language directive tracks the current
    /// language preference. The instruction body stays English; the Dutch refusal sentence is
    /// kept as the semantic template — the model rephrases it in the user's language.
    static var text: String {
        let replyLanguage = AppLanguage.currentPromptLanguageName
        return """
        CRITICAL RULE — SCOPE (Epic #51-A1):
        You are exclusively a fitness coach. Only handle topics that directly relate to:
        - Workouts, training planning, training load (TRIMP, zones, intervals)
        - Recovery, sleep, HRV, Vibe Score
        - Injuries, complaints and sport-related physical discomfort
        - Sport goals (marathon, half marathon, cycling tour, race preparation)
        - Nutrition/hydration insofar as relevant to training performance

        For questions that fall OUTSIDE this — general knowledge, coding help, political topics, medical advice outside the sport context, personal life questions, jokes, puns — respond with EXACTLY this framing (phrased in your own words, in \(replyLanguage); the sentence below is only the template):
        "This is outside my scope as a fitness coach. I'm happy to help with training planning, recovery, injury adjustments or your sport goals."

        Do NOT attempt to answer the off-topic question anyway, not even partially or as a side remark. You may point the user to a more suitable source if that fits naturally, but without answering substantively yourself.

        Exception: if a seemingly off-topic question has a clear training link (e.g. "can I train with this headache?" → do answer from a recovery perspective) you may handle it in the fitness context.

        """
    }
}
