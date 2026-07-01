import SwiftUI

// MARK: - Sprint 17.3: Milestone Progress Card

/// Card that visually displays the success criteria of the PeriodizationEngine
/// with progress bars per goal. Makes the 'why' behind the schedule clear.
struct MilestoneProgressCard: View {
    let results: [PeriodizationResult]

    var body: some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundColor(.primary)
                    Text("Fase-Mijlpalen")
                        .font(.headline)
                }

                ForEach(results, id: \.goal.id) { result in
                    GoalMilestonesSection(result: result)
                    if result.goal.id != results.last?.goal.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

private struct GoalMilestonesSection: View {
    let result: PeriodizationResult
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.goal.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                Text(result.phase.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(themeManager.primaryAccentColor.opacity(0.15))
                    .foregroundStyle(themeManager.primaryAccentColor)
                    .cornerRadius(4)
            }

            ForEach(result.milestoneItems, id: \.label) { item in
                MilestoneProgressRow(item: item)
            }
        }
    }
}

private struct MilestoneProgressRow: View {
    let item: PeriodizationResult.MilestoneItem

    private var accentColor: Color { item.isMet ? .green : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: item.isMet ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(accentColor)
                    .font(.caption)
                Text(item.label)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(progressText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemFill))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accentColor)
                        .frame(width: geo.size.width * item.progress, height: 6)
                        .animation(.easeInOut(duration: 0.4), value: item.progress)
                }
            }
            .frame(height: 6)
            Text(item.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var progressText: String {
        if item.label.contains("belasting") {
            return String(format: "%.0f / %.0f TRIMP", item.current, item.required)
        }
        return String(format: "%.1f / %.1f km", item.current, item.required)
    }
}
