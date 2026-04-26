import Foundation

// MARK: - IntentExecutionContextFormatter
//
// Bouwt het `[ANALYSIS — INTENT vs UITVOERING]`-blok in de coach-prompt op basis
// van een `IntentExecutionVerdict`. Pure Swift, testbaar zonder ChatViewModel-state.
// De coach krijgt zo één compact regel-blok dat hem in staat stelt om proactief te
// reageren ("ik zie dat je tempo-sessie van dinsdag een endurance is geworden — alles
// in orde?") in plaats van pas te reageren als de gebruiker er expliciet om vraagt.

enum IntentExecutionContextFormatter {

    /// Format voor één-shot injectie. Retourneert lege string bij `.insufficientData`
    /// — anders zou de prompt vol staan met loze "kon niet bepalen"-blokken die de
    /// coach zelf zou moeten ignoreren.
    /// - Parameters:
    ///   - verdict: Resultaat uit `IntentExecutionAnalyzer.analyze(...)`.
    ///   - plannedActivity: Gepland-activiteit-naam (bv. "Tempo run") voor humane labels.
    ///   - actualActivityName: Werkelijke activiteit-naam voor humane labels.
    ///   - plannedTRIMP: Optioneel, voor exacte TRIMP-rapportage.
    ///   - actualTRIMP: Optioneel, voor exacte TRIMP-rapportage.
    static func format(verdict: IntentExecutionVerdict,
                       plannedActivity: String,
                       actualActivityName: String,
                       plannedTRIMP: Int?,
                       actualTRIMP: Double?) -> String {
        switch verdict {
        case .insufficientData:
            // Geen blok — coach zou anders met onbruikbare lege state moeten dealen.
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
