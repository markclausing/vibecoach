import SwiftUI

// MARK: - Epic #60: Per-phase milestones (collapsible)
//
// Renders a `PhaseTimeline` as one collapsible `DisclosureGroup` per training phase.
// Collapsed: phase dot + name + date range + status. Expanded: targets (with progress) and
// milestones (with target date + satisfied state). The current phase is expanded by default.

struct PhaseMilestonesView: View {
    let timeline: PhaseTimeline
    @EnvironmentObject var themeManager: ThemeManager
    @State private var expandedPhases: Set<TrainingPhase> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIJLPALEN PER FASE")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)

            VStack(spacing: 10) {
                ForEach(timeline.phases) { phase in
                    DisclosureGroup(isExpanded: expansionBinding(phase.phase)) {
                        expandedContent(phase)
                    } label: {
                        header(phase)
                    }
                    .tint(.primary)
                }
            }
        }
        .padding(16)
        .onAppear {
            // Open the current phase by default so the user lands on "what matters now".
            if expandedPhases.isEmpty,
               let current = timeline.phases.first(where: { $0.status == .current }) {
                expandedPhases.insert(current.phase)
            }
        }
    }

    // MARK: - Header (collapsed row)

    private func header(_ phase: PhaseSummary) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color(for: phase.phase))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                // Phase displayName stays English (matches TrainingPhase.displayName, used app-wide).
                Text(LocalizedStringKey(phase.phase.displayName))
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(dateRange(phase))
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            statusBadge(phase)
        }
    }

    @ViewBuilder
    private func statusBadge(_ phase: PhaseSummary) -> some View {
        switch phase.status {
        case .past:
            Text("Afgerond")
                .font(.caption2).foregroundColor(.secondary)
        case .current:
            Text("Nu")
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(themeManager.primaryAccentColor)
        case .future:
            Image(systemName: "lock.fill")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Expanded content

    @ViewBuilder
    private func expandedContent(_ phase: PhaseSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(phase.targets) { target in
                targetRow(target)
            }
            if !phase.milestones.isEmpty {
                Divider()
                ForEach(phase.milestones) { milestone in
                    milestoneRow(milestone)
                }
            }
        }
        .padding(.top, 8)
        .padding(.leading, 20)
    }

    private func targetRow(_ target: PhaseTarget) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(target.label))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                Text(valueText(for: target))
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            if target.current != nil {
                ProgressView(value: target.progress)
                    .tint(target.isMet ? .green : themeManager.primaryAccentColor)
            }
        }
    }

    private func milestoneRow(_ milestone: PhaseMilestone) -> some View {
        HStack(spacing: 10) {
            Image(systemName: milestone.isSatisfied ? "checkmark.circle.fill" : "circle")
                .foregroundColor(milestone.isSatisfied ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                // Milestone description is a Dutch prompt term — render verbatim (§13).
                Text(LocalizedStringKey(milestone.description))
                    .font(.subheadline).foregroundColor(.primary)
                Text("Streefdatum \(shortDate(milestone.targetDate))")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func expansionBinding(_ phase: TrainingPhase) -> Binding<Bool> {
        Binding(
            get: { expandedPhases.contains(phase) },
            set: { isOpen in
                if isOpen { expandedPhases.insert(phase) } else { expandedPhases.remove(phase) }
            }
        )
    }

    /// Maps the phase's colour name (TrainingPhase.color) to a SwiftUI Color.
    private func color(for phase: TrainingPhase) -> Color {
        switch phase.color {
        case "blue":   return .blue
        case "orange": return .orange
        case "red":    return .red
        case "purple": return .purple
        default:       return .gray
        }
    }

    /// "12 mrt – 7 mei" — pre-formatted so the View renders it verbatim (§13).
    private func dateRange(_ phase: PhaseSummary) -> String {
        "\(shortDate(phase.start)) – \(shortDate(phase.end)) · \(phase.weekCount)w"
    }

    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        df.locale = AppLanguage.currentLocale
        return df.string(from: date)
    }

    /// Formats the value column: "30 / 26 km" for an achieved target, or "≤ 16 km" / "≥ 280 TRIMP"
    /// for a future phase where nothing is achieved yet.
    private func valueText(for target: PhaseTarget) -> String {
        let req = String(format: "%.0f", target.required)
        if let current = target.current {
            let cur = String(format: "%.0f", current)
            let suffix = target.isInverted ? " (max)" : ""
            return "\(cur) / \(req) \(target.unit)\(suffix)"
        } else {
            let prefix = target.isInverted ? "≤ " : "≥ "
            return "\(prefix)\(req) \(target.unit)"
        }
    }
}
