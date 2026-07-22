import SwiftUI

/// Epic #72 story 72.2: hero section of the active-goal card — identity row (sport icon,
/// pills, title, race date, days countdown), verdict banner, and the phase timeline bar.
struct GoalHeroCard: View {
    let goal: FitnessGoal
    let gap: BlueprintGap?
    let verdict: GoalVerdict?
    let daysLeft: Int
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 0) {
            identityRow

            if let verdict {
                GoalVerdictBanner(verdict: verdict)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            if let phase = goal.currentPhase {
                Divider()
                phaseBarSection(goal: goal, currentPhase: phase, gap: gap)
                    .padding(16)
            }
        }
    }

    // MARK: - Identity row

    private var identityRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(themeManager.primaryAccentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: Self.sportIcon(goal.sportCategory))
                    .font(.system(size: 20))
                    .foregroundColor(themeManager.primaryAccentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Actief")
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(themeManager.primaryAccentColor.opacity(0.15))
                        .foregroundColor(themeManager.primaryAccentColor)
                        .clipShape(Capsule())
                    if gap != nil {
                        Text("Blueprint")
                            .font(.caption2).fontWeight(.medium)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(.systemFill))
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())
                    }
                }
                Text(goal.title)
                    .font(.title3).fontWeight(.bold)
                    .lineLimit(2)
                // Race-date line: pre-formatted String (§13) rendered verbatim, no catalog key.
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(raceDateString)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .center, spacing: 1) {
                Text("\(daysLeft)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("DAGEN")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary).kerning(0.5)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
    }

    private var raceDateString: String {
        AppDateFormatters.displayStyle(.medium).string(from: goal.targetDate)
    }

    // MARK: - Phase Bar

    private func phaseBarSection(goal: FitnessGoal, currentPhase: TrainingPhase, gap: BlueprintGap?) -> some View {
        let segments = phaseSegments(for: goal)
        let totalW   = max(1, segments.reduce(0) { $0 + $1.weeks })
        let currentIndex = segments.firstIndex { $0.phase == currentPhase } ?? 0
        let elapsedFraction = phaseElapsedFraction(gap: gap)

        // Epic #37 story 37.1c: assigned to a var then Text(weekLabel) -> verbatim. The phase
        // name (%@) and counts (%lld) interpolate into a catalog format key.
        let weekLabel: String = {
            if let g = gap {
                return String(localized: "\(currentPhase.displayName) · week \(g.phaseWeekNumber) van \(g.phaseTotalWeeks)")
            }
            return currentPhase.displayName
        }()

        let nextLabel = nextPhaseStartLabel(for: goal)

        return VStack(alignment: .leading, spacing: 8) {
            // Segmented bar
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(Array(segments.enumerated()), id: \.element.phase.rawValue) { index, seg in
                        let isActive = seg.phase == currentPhase
                        let width = geo.size.width * (Double(seg.weeks) / Double(totalW))
                        let segWidth = max(0, width - 3)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isActive
                                      ? themeManager.primaryAccentColor.opacity(0.25)
                                      : (index < currentIndex ? themeManager.primaryAccentColor : Color(.systemFill)))
                            // Epic #72 story 72.2: in-phase progress fill on the active segment.
                            if isActive {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(themeManager.primaryAccentColor)
                                    .frame(width: segWidth * elapsedFraction)
                            }
                        }
                        .frame(width: segWidth, height: isActive ? 8 : 5)
                        .animation(.easeInOut(duration: 0.3), value: isActive)
                    }
                }
                .frame(height: 8, alignment: .center)
            }
            .frame(height: 8)

            // Phase labels row
            HStack(spacing: 0) {
                ForEach(segments, id: \.phase.rawValue) { seg in
                    let isActive = seg.phase == currentPhase
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = Double(totalW)  // ForEach disambiguation; removing it breaks closure type inference.
                    Text(phaseShortLabel(seg.phase) + " \(seg.weeks)w")
                        .font(.system(size: 9, weight: isActive ? .bold : .regular))
                        .foregroundColor(isActive ? themeManager.primaryAccentColor : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Week label + next phase date
            HStack {
                Text(weekLabel)
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                if let next = nextLabel {
                    Text(next)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// Fraction (0...1) of the current phase window elapsed so far — DST-safe via
    /// `Calendar.fractionalDays` (§3). Falls back to fully filled when there's no BlueprintGap.
    private func phaseElapsedFraction(gap: BlueprintGap?) -> Double {
        guard let gap else { return 1.0 }
        let totalDays = Calendar.current.fractionalDays(from: gap.phaseStartDate, to: gap.phaseEndDate)
        guard totalDays > 0 else { return 1.0 }
        let elapsedDays = Calendar.current.fractionalDays(from: gap.phaseStartDate, to: Date())
        return min(1.0, max(0.0, elapsedDays / totalDays))
    }

    private func phaseShortLabel(_ phase: TrainingPhase) -> String {
        switch phase {
        case .baseBuilding: return "BASE"
        case .buildPhase:   return "BUILD"
        case .peakPhase:    return "PEAK"
        case .tapering:     return "TAPER"
        }
    }

    // Epic #60: same PhaseWindowCalculator the per-phase milestone list uses, so bar and list
    // never disagree.
    private func phaseSegments(for goal: FitnessGoal) -> [(phase: TrainingPhase, weeks: Int)] {
        PhaseWindowCalculator.windows(for: goal).map { (phase: $0.phase, weeks: $0.weekCount) }
    }

    private func nextPhaseStartLabel(for goal: FitnessGoal) -> String? {
        let df  = AppDateFormatters.display("d MMM")
        let cal = Calendar.current

        // swiftlint:disable force_unwrapping
        // Calendar week arithmetic on a valid targetDate — never nil.
        switch goal.currentPhase {
        // Epic #37 story 37.1c: rendered via Text(nextLabel) -> verbatim. Phase names stay
        // English (matching TrainingPhase.displayName); the date interpolates as %@.
        case .baseBuilding:
            let d = cal.date(byAdding: .weekOfYear, value: -12, to: goal.targetDate)!
            return String(localized: "Build start \(df.string(from: d))")
        case .buildPhase:
            let d = cal.date(byAdding: .weekOfYear, value: -4, to: goal.targetDate)!
            return String(localized: "Peak start \(df.string(from: d))")
        case .peakPhase:
            let d = cal.date(byAdding: .weekOfYear, value: -2, to: goal.targetDate)!
            return String(localized: "Taper start \(df.string(from: d))")
        case .tapering, nil:
            return nil
        }
        // swiftlint:enable force_unwrapping
    }

    // MARK: - Shared sport icon (also used by GoalsListView.completedGoalRow)

    static func sportIcon(_ category: SportCategory?) -> String {
        switch category {
        case .cycling:    return "bicycle"
        case .running:    return "figure.run"
        case .swimming:   return "figure.pool.swim"
        case .triathlon:  return "medal.fill"
        case .strength:   return "dumbbell.fill"
        case .walking:    return "figure.walk"
        default:          return "flag.fill"
        }
    }
}
