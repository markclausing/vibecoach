import Foundation

/// Pure-Swift formatter for the Goal-Intents block injected into the coach prompt.
///
/// Called by `ChatViewModel.cacheIntentContext` and directly testable in tests
/// without an `@AppStorage` or `UserDefaults` fixture.
enum IntentContextFormatter {

    /// Formats per-goal coaching instructions into a context string. Adds explicit
    /// tour context for `multiDayStage`/`singleDayTour` formats and — when present —
    /// a human-readable `stretchGoalTime`.
    /// - Parameter results: PeriodizationResults per active goal.
    /// - Returns: The formatted context string. Empty string if all instructions are empty.
    static func format(results: [PeriodizationResult]) -> String {
        let instructions = results
            .filter { !$0.intentModifier.coachingInstruction.isEmpty }
            .map { result -> String in
                var text = "• \(result.goal.title):\n\(result.intentModifier.coachingInstruction)"

                // Explicit tour context: the coach must NOT reason as for a race
                let format = result.goal.resolvedFormat
                if format == .multiDayStage || format == .singleDayTour {
                    text += "\n⚠️ LET OP: Dit is een TOERTOCHT, geen race. Beoordeel de voortgang op basis van rustig touren, comfort en meerdaags duurvermogen, NIET op race-snelheid."
                }

                // Explicit stretch-goal target time in readable format
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
