import Foundation

/// Epic #70 story 70.5: builds the `[WORKOUT NOTES]` prompt block from the facts
/// the coach distilled in per-workout chats (`WorkoutChatFact`).
///
/// Pure and model-free like its formatter siblings: the caller (ChatView) maps the
/// SwiftData facts to `Item` values (adding the workout label) and this type only
/// filters, orders and formats. Returns `""` when nothing qualifies — the caller
/// interprets an empty string as "no block in the prompt"
/// (the `LastWorkoutContextFormatter` convention).
///
/// Policy (part of the formatter so it is unit-tested):
/// - Window: trailing 14 days, computed via `Calendar.date(byAdding:)` (§3).
/// - `.dayCondition` facts from the *current week* lead under their own sub-line —
///   they explain this week's deviations, which is exactly what plan feedback needs.
/// - Cap: 20 facts, newest first, to bound prompt size.
enum WorkoutFactsContextFormatter {

    /// One fact, flattened to values (no SwiftData dependency).
    struct Item: Equatable {
        let text: String
        let category: WorkoutFactCategory
        let createdAt: Date
        /// Display label of the source workout (e.g. "Zondagrit"); empty is allowed.
        let workoutLabel: String
    }

    /// Maximum number of facts in the block (newest first).
    static let maxFacts = 20
    /// Trailing window in days.
    static let windowDays = 14

    static func format(items: [Item],
                       now: Date = Date(),
                       calendar: Calendar = .current) -> String {
        guard let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: now) else { return "" }

        let recent = items
            .filter { $0.createdAt >= cutoff && $0.createdAt <= now }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(maxFacts)
        guard !recent.isEmpty else { return "" }

        // Current-week day-condition facts lead; everything else follows.
        let conditionThisWeek = recent.filter {
            $0.category == .dayCondition
                && calendar.isDate($0.createdAt, equalTo: now, toGranularity: .weekOfYear)
        }
        let otherFacts = recent.filter { fact in !conditionThisWeek.contains(fact) }

        let dateFormatter = AppDateFormatters.promptStyle(.medium)
        func line(_ item: Item) -> String {
            let label = item.workoutLabel.isEmpty ? "" : "\(item.workoutLabel), "
            return "- [\(item.category.rawValue)] \(item.text) (\(label)\(dateFormatter.string(from: item.createdAt)))"
        }

        var block = "[WORKOUT NOTES — subjective notes the user shared in workout chats (last \(windowDays) days):\n"
        if !conditionThisWeek.isEmpty {
            block += "Condition this week:\n"
            block += conditionThisWeek.map(line).joined(separator: "\n") + "\n"
        }
        if !otherFacts.isEmpty {
            if !conditionThisWeek.isEmpty { block += "Workout notes:\n" }
            block += otherFacts.map(line).joined(separator: "\n") + "\n"
        }
        block += "Weigh these in plans and feedback — they can explain deviations the sensor data cannot.]\n\n"
        return block
    }
}
