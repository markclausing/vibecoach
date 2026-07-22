import SwiftUI

/// Epic #72 story 72.2: extracted from GoalsListView (pure move). Red-status warning with
/// the recovery-plan CTA (§1: a red status always ships with an action).
struct GoalWarningCard: View {
    let risk: DashboardView.GoalRiskStatus
    let onAdjustPlan: () -> Void
    let onDetails: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text("Bijsturing nodig")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.orange)
                Text(risk.isTaperingOverload
                     ? String(localized: "Je trainingsbelasting is te hoog voor de taperingsfase.")
                     : String(format: String(localized: "Je trainingsbelasting is %.0f TRIMP/week — het doel is %.0f."), risk.currentWeeklyRate, risk.requiredWeeklyRate))
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 12) {
                    Button {
                        onAdjustPlan()
                    } label: {
                        Text("Pas plan aan")
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                    Button {
                        onDetails()
                    } label: {
                        Text("Details")
                            .font(.caption).fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.07))
    }
}
