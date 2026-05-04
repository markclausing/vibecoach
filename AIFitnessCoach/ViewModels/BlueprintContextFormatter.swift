import Foundation

/// Pure-Swift formatter voor de blueprint-status-context (Epic 17) die in de coach-prompt geïnjecteerd wordt.
///
/// Wordt aangeroepen door `ChatViewModel.cacheActiveBlueprints` en in tests direct testbaar
/// zonder `@AppStorage` of `UserDefaults`-fixture.
enum BlueprintContextFormatter {

    /// Formatteert blueprint-resultaten naar een meerregelige context-string voor de AI-coach.
    /// Per actief doel: titel + weken-resterend + on-schema-status + per-milestone status met deadlines.
    /// - Parameter results: De blueprint-checks per actief doel.
    /// - Returns: De geformatteerde context-string. Lege string als `results` leeg is.
    static func format(results: [BlueprintCheckResult]) -> String {
        guard !results.isEmpty else { return "" }

        var lines: [String] = []
        for result in results {
            let weeksLeft = result.goal.weeksRemaining
            let weeksLeftStr = String(format: "%.1f", weeksLeft)
            let statusLabel = result.isOnTrack ? "Op schema" : "Achter op schema"
            lines.append("• Doel '\(result.goal.title)' (\(weeksLeftStr) weken resterend) — Blueprint: \(result.blueprint.goalType.displayName), \(statusLabel) (\(result.satisfiedCount)/\(result.totalCount) kritieke eisen behaald).")

            for milestone in result.milestones {
                let check = milestone.isSatisfied ? "✅" : "❌"
                let deadlineStr = DateFormatter.localizedString(from: milestone.deadline, dateStyle: .short, timeStyle: .none)
                if milestone.isSatisfied {
                    lines.append("  \(check) \(milestone.description) (behaald)")
                } else {
                    lines.append("  \(check) \(milestone.description) — deadline: \(deadlineStr) (\(milestone.weeksBefore) weken voor race)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
