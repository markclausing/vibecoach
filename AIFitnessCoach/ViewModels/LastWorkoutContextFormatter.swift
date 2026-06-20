import Foundation

// MARK: - LastWorkoutContextFormatter
//
// Builds the prompt string for the 'last workout' block in the coach context. Pure
// Swift, no ChatViewModel state — so it's unit-testable without a real model.
// When a `sessionType` is present the helper adds the physiological intent so the
// coach can calibrate feedback ("well recovered" for a Recovery session with low HR
// instead of "you were too slow"). That's exactly what Epic 33 Story 33.1b solves.

enum LastWorkoutContextFormatter {

    /// Formats the feedback block for injection into the Gemini system context.
    /// Returns an empty string if there's insufficient data (no rpe or mood) —
    /// the caller should interpret that empty string as "no block in the prompt".
    /// - Parameters:
    ///   - rpe: RPE score (1-10), optional.
    ///   - mood: Mood emoji or word, optional.
    ///   - workoutName: Name of the workout, fallback "Training".
    ///   - trimp: TRIMP score, optional ("onbekend" if nil).
    ///   - startDate: Date of the workout, for the "[Type] from [Date]" format.
    ///   - sessionType: Optional — when present the label + intent is added.
    static func format(rpe: Int?,
                       mood: String?,
                       workoutName: String?,
                       trimp: Double?,
                       startDate: Date?,
                       sessionType: SessionType?) -> String {
        guard let rpe, let mood else { return "" }

        let baseName = workoutName ?? "Training"
        let nameStr: String
        if let date = startDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.locale = Locale(identifier: "nl_NL")
            nameStr = "\(baseName) van \(formatter.string(from: date))"
        } else {
            nameStr = baseName
        }

        let trimpStr = trimp.map { String(format: "%.0f", $0) } ?? "unknown"
        let rpeLabel: String
        switch rpe {
        case 1...3: rpeLabel = "light (1-3)"
        case 4...6: rpeLabel = "moderate (4-6)"
        case 7...8: rpeLabel = "hard (7-8)"
        default:    rpeLabel = "maximal (9-10)"
        }

        var line = "Last workout: '\(nameStr)', TRIMP: \(trimpStr), RPE: \(rpe)/10 (\(rpeLabel)), Mood: \(readableMood(mood))."

        // Story 33.1b: add session type + intent so the coach can tune its tone.
        // We pass the textual intent — not just the label — because 'recovery' on
        // its own offers less context than "active recovery, <65% HRmax". The
        // architect note on this was explicit.
        if let sessionType {
            let intent = sessionType.intent
            line += " Session type: \(sessionType.displayName) — \(intent.coachingSummary)"
        }

        return line
    }

    /// Epic #57 follow-up: the mood is persisted on `ActivityRecord` as the SF Symbol
    /// name of the chosen check-in option (e.g. "bandage.fill"). For the coach prompt we
    /// translate it to a readable English word so the AI gets "Mood: in pain" instead of
    /// the raw icon name. Unknown / legacy values (older emoji moods) pass through
    /// unchanged so no historical data is lost.
    private static func readableMood(_ raw: String) -> String {
        switch raw {
        case "checkmark.circle.fill": return "good"
        case "bolt.fill":             return "strong"
        case "zzz":                   return "exhausted"
        case "bandage.fill":          return "in pain"
        case "moon.fill":             return "calm"     // legacy mood option
        default:                      return raw
        }
    }
}
