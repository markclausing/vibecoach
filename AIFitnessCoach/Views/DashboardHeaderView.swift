import SwiftUI

/// V2.0 Sprint 1: Aangepaste header voor het dashboard.
/// Vervangt de standaard navigationTitle met een contextuele begroeting + dag/fase-indicator.
struct DashboardHeaderView: View {
    let periodizationResults: [PeriodizationResult]
    let goals: [FitnessGoal]

    @AppStorage("vibecoach_userName") private var userName: String = ""

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let firstName = userName.isEmpty ? nil : userName.components(separatedBy: " ").first
        let suffix = firstName.map { ", \($0)" } ?? ""
        if hour < 12 { return "Goedemorgen\(suffix)" }
        if hour < 18 { return "Goedemiddag\(suffix)" }
        return "Goedenavond\(suffix)"
    }

    /// Bouwt de contextregel: "DONDERDAG 17 APR · BUILD PHASE · WK 2/5"
    private var contextLine: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "EEEE d MMM"
        var parts: [String] = [formatter.string(from: Date()).uppercased()]

        if let result = periodizationResults.first {
            parts.append(result.phase.displayName.uppercased())

            if let goal = goals.first(where: { !$0.isCompleted && Date() < $0.targetDate }) {
                let cal = Calendar.current
                let totalWeeks = max(1, cal.dateComponents([.weekOfYear], from: goal.createdAt, to: goal.targetDate).weekOfYear ?? 1)
                let elapsedWeeks = max(1, cal.dateComponents([.weekOfYear], from: goal.createdAt, to: Date()).weekOfYear ?? 1)
                parts.append("WK \(min(elapsedWeeks, totalWeeks))/\(totalWeeks)")
            }
        }

        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(contextLine)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .kerning(0.4)
            Text(greeting)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DashboardHeaderView")
    }
}
