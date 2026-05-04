import Foundation

/// Pure-Swift formatter voor het Doel-Intenties-blok dat in de coach-prompt geïnjecteerd wordt.
///
/// Wordt aangeroepen door `ChatViewModel.cacheIntentContext` en in tests direct testbaar
/// zonder `@AppStorage` of `UserDefaults`-fixture.
enum IntentContextFormatter {

    /// Formatteert per-doel coaching-instructies naar een context-string. Voegt expliciete
    /// toertocht-context toe bij `multiDayStage`/`singleDayTour`-formaten en — indien
    /// aanwezig — een leesbaar weergegeven `stretchGoalTime`.
    /// - Parameter results: PeriodizationResults per actief doel.
    /// - Returns: De geformatteerde context-string. Lege string als alle instructies leeg zijn.
    static func format(results: [PeriodizationResult]) -> String {
        let instructions = results
            .filter { !$0.intentModifier.coachingInstruction.isEmpty }
            .map { result -> String in
                var text = "• \(result.goal.title):\n\(result.intentModifier.coachingInstruction)"

                // Expliciete toertocht-context: de coach mag NIET redeneren als bij een wedstrijd
                let format = result.goal.resolvedFormat
                if format == .multiDayStage || format == .singleDayTour {
                    text += "\n⚠️ LET OP: Dit is een TOERTOCHT, geen race. Beoordeel de voortgang op basis van rustig touren, comfort en meerdaags duurvermogen, NIET op race-snelheid."
                }

                // Expliciete stretch goal doeltijd in leesbaar formaat
                if let stretchTime = result.goal.stretchGoalTime {
                    let totalSec = Int(stretchTime)
                    let hours    = totalSec / 3600
                    let minutes  = (totalSec % 3600) / 60
                    let timeStr  = hours > 0 ? "\(hours) uur en \(minutes) minuten" : "\(minutes) minuten"
                    text += "\n✅ Stretch Goal Doeltijd: \(timeStr). Bouw af en toe tempo-oefeningen in het schema in om deze snelheid op te bouwen, mits de actuele VibeScore / herstel dit toelaat."
                }

                return text
            }
        return instructions.isEmpty ? "" : instructions.joined(separator: "\n\n")
    }
}
