import Foundation

// MARK: - IntentExecutionContextFormatter
//
// Builds the `[ANALYSIS — INTENT vs EXECUTION]` block in the coach prompt based on
// an `IntentExecutionVerdict`. Pure Swift, testable without ChatViewModel state.
// This gives the coach one compact line block that lets it react proactively
// ("I see your Tuesday tempo session became an endurance — everything ok?")
// instead of only reacting when the user explicitly asks.

enum IntentExecutionContextFormatter {

    /// Format for one-shot injection. Returns an empty string on `.insufficientData`
    /// — otherwise the prompt would be full of empty "couldn't determine" blocks the
    /// coach would have to ignore itself.
    /// - Parameters:
    ///   - verdict: Result from `IntentExecutionAnalyzer.analyze(...)`.
    ///   - plannedActivity: Planned activity name (e.g. "Tempo run") for human labels.
    ///   - actualActivityName: Actual activity name for human labels.
    ///   - plannedTRIMP: Optional, for exact TRIMP reporting.
    ///   - actualTRIMP: Optional, for exact TRIMP reporting.
    static func format(verdict: IntentExecutionVerdict,
                       plannedActivity: String,
                       actualActivityName: String,
                       plannedTRIMP: Int?,
                       actualTRIMP: Double?) -> String {
        switch verdict {
        case .insufficientData:
            // No block — otherwise the coach would have to deal with unusable empty state.
            return ""

        case .match:
            return """
            [ANALYSIS — INTENT vs EXECUTION (last workout):
            Planned: \(plannedActivity)\(trimpSuffix(plannedTRIMP)) → Executed: \(actualActivityName)\(trimpSuffix(actualTRIMP)).
            Result: MATCH — type and load within margin. Compliment the user on their discipline.]


            """

        case .typeMismatch(let planned, let actual):
            let actualLabel = actual?.displayName ?? "undetermined type"
            return """
            [ANALYSIS — INTENT vs EXECUTION (last workout):
            Planned: \(plannedActivity) (session type: \(planned.displayName)\(trimpSuffix(plannedTRIMP))) → Executed: \(actualActivityName) (session type: \(actualLabel)\(trimpSuffix(actualTRIMP))).
            Result: TYPE-MISMATCH — planned session was \(planned.displayName) but \(actualLabel) was done. Coach: only flag this if it becomes structural over the past 7 days. One deviation is normal (group pace, fatigue, weather); only on repetition is it time to reconsider the schedule.]


            """

        case .overload(let deltaPercent):
            let pct = String(format: "%+.0f", deltaPercent)
            return """
            [ANALYSIS — INTENT vs EXECUTION (last workout):
            Planned: \(plannedActivity)\(trimpSuffix(plannedTRIMP)) → Executed: \(actualActivityName)\(trimpSuffix(actualTRIMP)).
            Result: OVERLOAD (\(pct)% TRIMP above plan). Coach: mention this cautiously — overload combined with a low Vibe Score becomes a risk factor. If needed, propose a light recovery day in the next 48 hours.]


            """

        case .underload(let deltaPercent):
            let pct = String(format: "%+.0f", deltaPercent)
            return """
            [ANALYSIS — INTENT vs EXECUTION (last workout):
            Planned: \(plannedActivity)\(trimpSuffix(plannedTRIMP)) → Executed: \(actualActivityName)\(trimpSuffix(actualTRIMP)).
            Result: UNDERLOAD (\(pct)% TRIMP below plan). Coach: ask whether it was a deliberate choice (fatigue, lack of time) or whether the user feels unsure about the intensity. If needed, offer an adjusted compensation session during the week.]


            """
        }
    }

    private static func trimpSuffix(_ trimp: Int?) -> String {
        guard let trimp, trimp > 0 else { return "" }
        return " (TRIMP \(trimp))"
    }

    private static func trimpSuffix(_ trimp: Double?) -> String {
        guard let trimp, trimp > 0 else { return "" }
        return " (TRIMP \(Int(trimp.rounded())))"
    }
}
