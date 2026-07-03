import SwiftUI

// Epic #65 story 65.5: split out of GoalsListView.swift (§5 file-split). Pure move — no
// semantic changes; access relaxed private -> internal only where the split
// requires it (listed in the PR body).

// MARK: - GoalRowView (preserved for EditGoal navigation)

struct GoalRowView: View {
    let goal: FitnessGoal
    @EnvironmentObject var themeManager: ThemeManager

    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal.title)
                    .font(.headline)
                    .strikethrough(goal.isCompleted, color: .secondary)
                    .foregroundColor(goal.isCompleted ? .secondary : .primary)
                Spacer()
                if goal.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if daysRemaining >= 0 {
                    Text("\(daysRemaining) dagen")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(themeManager.primaryAccentColor.opacity(0.1))
                        .foregroundStyle(themeManager.primaryAccentColor)
                        .clipShape(Capsule())
                } else {
                    Text("Verlopen")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 6) {
                if let phase = goal.currentPhase {
                    let phaseColor: Color = {
                        switch phase {
                        case .baseBuilding: return .blue
                        case .buildPhase:   return .orange
                        case .peakPhase:    return .red
                        case .tapering:     return .purple
                        }
                    }()
                    Text(phase.displayName)
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(phaseColor.opacity(0.12))
                        .foregroundColor(phaseColor)
                        .clipShape(Capsule())
                }
                if let sport = goal.sportCategory?.displayName, !sport.isEmpty {
                    Text(sport)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
            }

            Text(goal.targetDate, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
