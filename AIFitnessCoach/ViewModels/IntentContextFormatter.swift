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
                    text += "\n⚠️ NOTE: This is a TOUR, not a race. Judge progress on relaxed touring, comfort and multi-day endurance, NOT on race speed."
                }

                // Explicit stretch-goal target time in readable format
                if let stretchTime = result.goal.stretchGoalTime {
                    let totalSec = Int(stretchTime)
                    let hours    = totalSec / 3600
                    let minutes  = (totalSec % 3600) / 60
                    let timeStr  = hours > 0 ? "\(hours) hours and \(minutes) minutes" : "\(minutes) minutes"
                    text += "\n✅ Stretch Goal target time: \(timeStr). Occasionally build tempo sessions into the schedule to develop this speed, provided the current Vibe Score / recovery allows it."
                }

                return text
            }
        return instructions.isEmpty ? "" : instructions.joined(separator: "\n\n")
    }
}
