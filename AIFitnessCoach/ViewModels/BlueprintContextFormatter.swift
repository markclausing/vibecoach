import Foundation

/// Pure-Swift formatter for the blueprint-status context (Epic 17) injected into the coach prompt.
///
/// Called by `ChatViewModel.cacheActiveBlueprints` and directly testable in tests
/// without an `@AppStorage` or `UserDefaults` fixture.
enum BlueprintContextFormatter {

    /// Formats blueprint results into a multi-line context string for the AI coach.
    /// Per active goal: title + weeks remaining + on-schedule status + per-milestone status with deadlines.
    /// - Parameter results: The blueprint checks per active goal.
    /// - Returns: The formatted context string. Empty string if `results` is empty.
    static func format(results: [BlueprintCheckResult]) -> String {
        guard !results.isEmpty else { return "" }

        var lines: [String] = []
        for result in results {
            let weeksLeft = result.goal.weeksRemaining
            let weeksLeftStr = String(format: "%.1f", weeksLeft)
            let statusLabel = result.isOnTrack ? "On schedule" : "Behind schedule"
            lines.append("• Goal '\(result.goal.title)' (\(weeksLeftStr) weeks remaining) — Blueprint: \(result.blueprint.goalType.displayName), \(statusLabel) (\(result.satisfiedCount)/\(result.totalCount) critical requirements met).")

            for milestone in result.milestones {
                let check = milestone.isSatisfied ? "✅" : "❌"
                let deadlineStr = DateFormatter.localizedString(from: milestone.deadline, dateStyle: .short, timeStyle: .none)
                if milestone.isSatisfied {
                    lines.append("  \(check) \(milestone.description) (met)")
                } else {
                    lines.append("  \(check) \(milestone.description) — deadline: \(deadlineStr) (\(milestone.weeksBefore) weeks before race)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
