import SwiftUI

// MARK: - Epic #60/#72: Per-phase milestones (collapsible)
//
// Renders a `PhaseTimeline` as one collapsible `DisclosureGroup` per training phase.
// Collapsed: phase dot + name + date range + status. Expanded: targets (state circle, no
// progress bar — cumulative bars live in the progress section) and milestones (with target
// date + satisfied state). The current phase is expanded by default.

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
            headerDot(phase)
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

    /// State-based dot colouring (replaces the old red/orange/purple `TrainingPhase.color`
    /// mapping): current gets an accent-filled dot with a soft ring, past a full accent dot,
    /// future a neutral gray dot.
    @ViewBuilder
    private func headerDot(_ phase: PhaseSummary) -> some View {
        switch phase.status {
        case .current:
            Circle()
                .fill(themeManager.primaryAccentColor)
                .frame(width: 10, height: 10)
                .background(
                    Circle()
                        .fill(themeManager.primaryAccentColor.opacity(0.25))
                        .frame(width: 16, height: 16)
                )
        case .past:
            Circle()
                .fill(themeManager.primaryAccentColor)
                .frame(width: 10, height: 10)
        case .future:
            Circle()
                .fill(Color(.systemFill))
                .frame(width: 10, height: 10)
        }
    }

    @ViewBuilder
    private func statusBadge(_ phase: PhaseSummary) -> some View {
        switch phase.status {
        case .past:
            Text("Afgerond")
                .font(.caption2).foregroundColor(.secondary)
        case .current:
            Text(currentStatusText(phase))
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(themeManager.primaryAccentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(themeManager.primaryAccentColor.opacity(0.15)))
        case .future:
            Text("Aankomend")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    /// "Nu" when the phase has no targets/milestones yet, otherwise "Nu · done/total" — pre-format
    /// the counts as Strings so the catalog key interpolates as %@, not %lld (§13).
    private func currentStatusText(_ phase: PhaseSummary) -> String {
        let total = totalCount(phase)
        guard total > 0 else { return String(localized: "Nu") }
        let doneStr = String(doneCount(phase))
        let totalStr = String(total)
        return String(localized: "Nu · \(doneStr)/\(totalStr)")
    }

    private func doneCount(_ phase: PhaseSummary) -> Int {
        phase.targets.filter(\.isMet).count + phase.milestones.filter(\.isSatisfied).count
    }

    private func totalCount(_ phase: PhaseSummary) -> Int {
        phase.targets.count + phase.milestones.count
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
        HStack(alignment: .center, spacing: 10) {
            targetStateCircle(isMet: target.isMet)
            Text(LocalizedStringKey(target.label))
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Text(valueText(for: target))
                .font(.caption)
                .fontWeight(target.isMet ? .semibold : .medium)
                .foregroundColor(target.isMet ? themeManager.primaryAccentColor : .secondary)
        }
    }

    /// Leading state marker for a target row: accent-filled circle with a checkmark when met,
    /// a dashed open circle otherwise. No progress bar — that lives in the progress section.
    @ViewBuilder
    private func targetStateCircle(isMet: Bool) -> some View {
        if isMet {
            Circle()
                .fill(themeManager.primaryAccentColor)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                )
        } else {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
        }
    }

    private func milestoneRow(_ milestone: PhaseMilestone) -> some View {
        HStack(spacing: 10) {
            // Unsatisfied milestone reads as a target flag (dated essential workout) rather than
            // an empty circle — mirrors the redesign's "target" glyph.
            Image(systemName: milestone.isSatisfied ? "checkmark.circle.fill" : "flag")
                .foregroundColor(milestone.isSatisfied ? themeManager.primaryAccentColor : .secondary)
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

    /// "12 mrt – 7 mei" — pre-formatted so the View renders it verbatim (§13).
    private func dateRange(_ phase: PhaseSummary) -> String {
        "\(shortDate(phase.start)) – \(shortDate(phase.end)) · \(phase.weekCount)w"
    }

    private func shortDate(_ date: Date) -> String {
        return AppDateFormatters.display("d MMM").string(from: date)
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
