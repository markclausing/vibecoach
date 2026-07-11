import SwiftUI

/// Epic #72 story 72.2: extracted from GoalsListView (pure move; restyled in story 72.3).
struct GoalProgressSection: View {
    let gap: BlueprintGap
    let periResult: PeriodizationResult?
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VOORTGANG DEZE FASE")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)

            // Training load (TRIMP)
            PhaseProgressCard(
                label: "Trainingsbelasting",
                valueCurrent: String(format: "%.0f", gap.actualTRIMPToDate),
                valueTarget: String(format: "%.0f", gap.totalPhaseTRIMPTarget),
                unit: "TRIMP",
                progress: gap.trimpProgressPct,
                reference: gap.trimpReferencePct,
                accentColor: themeManager.primaryAccentColor
            )

            // Distance
            if gap.totalPhaseKmTarget > 0 {
                let sportLabel = gap.blueprintType == .cyclingTour ? "Afstand (wielrennen)" : "Afstand (hardlopen)"
                PhaseProgressCard(
                    label: sportLabel,
                    valueCurrent: String(format: "%.0f", gap.actualKmToDate),
                    valueTarget: String(format: "%.0f", gap.totalPhaseKmTarget),
                    unit: "km",
                    progress: gap.kmProgressPct,
                    reference: gap.kmReferencePct,
                    accentColor: themeManager.primaryAccentColor
                )
            }

            // Longest session
            if let session = periResult?.milestoneItems.first(where: { $0.label == "Langste sessie" }) {
                PhaseProgressCard(
                    label: "Langste sessie",
                    valueCurrent: String(format: "%.0f", session.current),
                    valueTarget: String(format: "%.0f", session.required),
                    unit: "km",
                    progress: session.progress,
                    reference: nil,
                    accentColor: themeManager.primaryAccentColor
                )
            }
        }
        .padding(16)
    }
}

// MARK: - PhaseProgressCard

private struct PhaseProgressCard: View {
    let label: String
    let valueCurrent: String
    let valueTarget: String
    let unit: String
    let progress: Double
    let reference: Double?
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Epic #37 story 37.1c: `label` is a String passed by the caller, resolved
                // via the catalog. valueCurrent/valueTarget/unit stay verbatim (data + units).
                Text(LocalizedStringKey(label))
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(valueCurrent)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("/ \(valueTarget) \(unit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progress >= (reference ?? 0) ? accentColor : Color.orange)
                        .frame(width: geo.size.width * min(1, progress), height: 8)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                    // Ghost reference marker
                    if let ref = reference, ref > 0 {
                        Rectangle()
                            .fill(Color(.secondaryLabel).opacity(0.5))
                            .frame(width: 2, height: 12)
                            .offset(x: geo.size.width * min(1, ref) - 1)
                    }
                }
            }
            .frame(height: 8)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
