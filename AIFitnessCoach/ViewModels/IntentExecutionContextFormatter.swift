import Foundation

// MARK: - IntentExecutionContextFormatter
//
// Builds the `[ANALYSIS — INTENT vs UITVOERING]` block in the coach prompt based on
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
            [ANALYSIS — INTENT vs UITVOERING (laatste workout):
            Gepland: \(plannedActivity)\(trimpSuffix(plannedTRIMP)) → Uitgevoerd: \(actualActivityName)\(trimpSuffix(actualTRIMP)).
            Resultaat: MATCH — type en belasting binnen marge. Geef de gebruiker een compliment over de discipline.]


            """

        case .typeMismatch(let planned, let actual):
            let actualLabel = actual?.displayName ?? "onbepaald type"
            return """
            [ANALYSIS — INTENT vs UITVOERING (laatste workout):
            Gepland: \(plannedActivity) (sessie-type: \(planned.displayName)\(trimpSuffix(plannedTRIMP))) → Uitgevoerd: \(actualActivityName) (sessie-type: \(actualLabel)\(trimpSuffix(actualTRIMP))).
            Resultaat: TYPE-MISMATCH — geplande sessie was \(planned.displayName) maar er is \(actualLabel) gedaan. Coach: signaleer dit alleen als het structureel wordt over de afgelopen 7 dagen. Eén afwijking is normaal (groep-tempo, vermoeidheid, weer); pas bij herhaling is het tijd om het schema te heroverwegen.]


            """

        case .overload(let deltaPercent):
            let pct = String(format: "%+.0f", deltaPercent)
            return """
            [ANALYSIS — INTENT vs UITVOERING (laatste workout):
            Gepland: \(plannedActivity)\(trimpSuffix(plannedTRIMP)) → Uitgevoerd: \(actualActivityName)\(trimpSuffix(actualTRIMP)).
            Resultaat: OVERLOAD (\(pct)% TRIMP boven plan). Coach: benoem dit voorzichtig — overload wordt in combinatie met lage Vibe Score een risicofactor. Stel zo nodig een lichte hersteldag voor in de komende 48 uur.]


            """

        case .underload(let deltaPercent):
            let pct = String(format: "%+.0f", deltaPercent)
            return """
            [ANALYSIS — INTENT vs UITVOERING (laatste workout):
            Gepland: \(plannedActivity)\(trimpSuffix(plannedTRIMP)) → Uitgevoerd: \(actualActivityName)\(trimpSuffix(actualTRIMP)).
            Resultaat: UNDERLOAD (\(pct)% TRIMP onder plan). Coach: vraag of het een bewuste keuze was (vermoeidheid, tijdgebrek) of dat de gebruiker zich onzeker voelt over de intensiteit. Bied indien nodig een aangepaste compensatie-sessie aan in de week.]


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
