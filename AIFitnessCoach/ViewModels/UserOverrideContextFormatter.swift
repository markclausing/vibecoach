import Foundation

// MARK: - UserOverrideContextFormatter
//
// Builds the `[USER_OVERRIDE]` block in the coach context. Pure Swift, testable
// without ChatViewModel state. Story 33.2a — if the user manually moved a session
// (`isSwapped == true`), the coach must respect that and not force the original date
// back on the next suggestion. Without this block the coach behaviour would conflict
// with the user's intent and frustrate the UX.

enum UserOverrideContextFormatter {

    /// Formats moved workouts into a prompt block. Returns an empty string if no
    /// workouts were moved (then the block also doesn't appear in the prompt — the
    /// AI doesn't have to guess at a presumably-empty state).
    /// - Parameters:
    ///   - workouts: The full active plan (all workouts; we filter on `isSwapped`).
    static func format(workouts: [SuggestedWorkout]) -> String {
        let swapped = workouts.filter { $0.isSwapped }
        guard !swapped.isEmpty else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM"
        formatter.locale = Locale(identifier: "nl_NL")

        let lines = swapped.map { workout -> String in
            let dayLabel = formatter.string(from: workout.displayDate)
            let capitalized = dayLabel.prefix(1).uppercased() + dayLabel.dropFirst()
            return "- '\(workout.activityType)' is now on \(capitalized) (manually moved by the user)"
        }.joined(separator: "\n")

        return """
        [USER_OVERRIDE — manual schedule adjustments:
        \(lines)

        CRITICAL INSTRUCTION: The user deliberately moved these sessions to another day. Do NOT shift them back in a future schedule suggestion. Respect the new schedule as given and adjust your advice accordingly.]


        """
    }
}
