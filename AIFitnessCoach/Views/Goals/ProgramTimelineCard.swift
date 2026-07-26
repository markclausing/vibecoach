import SwiftUI

/// Epic #73 story 73.5: the single "training programme" overview at the top of the Goals tab.
///
/// Before this card every active goal drew its own base→build→peak→taper bar, so two overlapping
/// races rendered two contradicting timelines side by side. This renders **one** macrocycle to the
/// A-race, with the interim races plotted on it as mini-taper tune-up markers, one current-phase
/// line and one combined weekly target. The per-goal cards below keep their verdict, progress and
/// milestones — but no longer their own competing phase bar.
struct ProgramTimelineCard: View {
    let program: UnifiedProgram
    /// Injected so previews and tests can pin the "you are here" marker.
    var now: Date = Date()

    @EnvironmentObject var themeManager: ThemeManager

    private var week: (current: Int, total: Int) { program.programWeek(at: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            anchorRow
            Divider()
            timelineSection
                .padding(16)
            if program.races.count > 1 {
                Divider()
                racesSection
                    .padding(16)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
        .accessibilityIdentifier("ProgramTimelineCard")
    }

    // MARK: - Header

    private var headerRow: some View {
        // Counts are pre-formatted into Strings so the catalog key stays %@-based (§13).
        let weekLabel = String(localized: "Week \("\(week.current)") van \("\(week.total)")")
        return HStack {
            Text("TRAININGSPROGRAMMA")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)
            Spacer()
            Text(weekLabel)
                .font(.caption2).fontWeight(.semibold)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(themeManager.primaryAccentColor.opacity(0.15))
                .foregroundColor(themeManager.primaryAccentColor)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - A-race identity

    @ViewBuilder
    private var anchorRow: some View {
        if let anchor = program.anchorRace {
            let daysLeft = max(0, Calendar.current.dateComponents([.day], from: now, to: anchor.date).day ?? 0)
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(themeManager.primaryAccentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 18))
                        .foregroundColor(themeManager.primaryAccentColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    RacePriorityBadge(priority: anchor.priority)
                    Text(anchor.title)
                        .font(.title3).fontWeight(.bold)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        Image(systemName: "calendar").font(.caption2)
                        // Pre-formatted date String rendered verbatim (§13) — no catalog key.
                        Text(AppDateFormatters.displayStyle(.medium).string(from: anchor.date))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .center, spacing: 1) {
                    Text("\(daysLeft)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("DAGEN")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary).kerning(0.5)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Macrocycle bar

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            macrocycleBar
            phaseLabelsRow
            statusLine
        }
    }

    /// One bar for the whole macrocycle: phase segments sized by their real duration, the interim
    /// races pinned on top at their date position, and a "you are here" tick.
    private var macrocycleBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    ForEach(program.phases, id: \.phase.rawValue) { window in
                        let span = Calendar.current.fractionalDays(from: window.start, to: window.end)
                        let total = max(1, Calendar.current.fractionalDays(from: program.start, to: program.end))
                        let isActive = window.phase == underlyingPhase
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isActive
                                  ? themeManager.primaryAccentColor
                                  : (window.end <= now
                                     ? themeManager.primaryAccentColor.opacity(0.45)
                                     : Color(.systemFill)))
                            .frame(width: max(0, geo.size.width * (span / total) - 3),
                                   height: isActive ? 10 : 6)
                    }
                }
                .frame(height: 10, alignment: .center)

                // Interim races sit on the bar as small markers; the anchor is the bar's end.
                ForEach(program.races.filter { !$0.isAnchor }) { race in
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                        .offset(x: geo.size.width * program.fraction(of: race.date) - 4, y: -11)
                }

                // "You are here"
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary)
                    .frame(width: 2, height: 18)
                    .offset(x: geo.size.width * program.fraction(of: now) - 1)
            }
        }
        .frame(height: 26)
    }

    private var phaseLabelsRow: some View {
        HStack(spacing: 0) {
            ForEach(program.phases, id: \.phase.rawValue) { window in
                let isActive = window.phase == underlyingPhase
                Text(Self.shortLabel(window.phase) + " \(window.weekCount)w")
                    .font(.system(size: 9, weight: isActive ? .bold : .regular))
                    .foregroundColor(isActive ? themeManager.primaryAccentColor : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Current phase + the one combined weekly target that replaced `.max()` across goals (73.3).
    private var statusLine: some View {
        let trimp = String(format: "%.0f", program.weeklyTrimpTarget)
        let targetLabel = String(localized: "\(trimp) TRIMP/week")
        return HStack {
            if program.inMiniTaper, let race = activeMiniTaperRace {
                Label(String(localized: "Mini-taper · \(race.title)"), systemImage: "arrow.down.right")
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.orange)
                    .lineLimit(1)
            } else {
                Text(LocalizedStringKey(program.currentPhase.displayName))
                    .font(.caption).fontWeight(.medium)
            }
            Spacer()
            Text(targetLabel)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Race list

    private var racesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RACES")
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)

            ForEach(program.races) { race in
                HStack(spacing: 10) {
                    RacePriorityBadge(priority: race.priority)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(race.title)
                            .font(.subheadline).fontWeight(race.isAnchor ? .semibold : .regular)
                            .lineLimit(1)
                        if let taperStart = race.miniTaperStart {
                            let dateStr = AppDateFormatters.display("d MMM").string(from: taperStart)
                            Text(String(localized: "Mini-taper vanaf \(dateStr) — daarna weer opbouwen"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text(AppDateFormatters.display("d MMM").string(from: race.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    /// The macrocycle window that contains `now`, ignoring a mini-taper override — the bar shows
    /// where the *program* stands; the mini-taper is called out separately in the status line.
    private var underlyingPhase: TrainingPhase? {
        program.phases.first { now >= $0.start && now < $0.end }?.phase
    }

    private var activeMiniTaperRace: RaceMarker? {
        program.races.first { race in
            guard let start = race.miniTaperStart else { return false }
            return now >= start && now < race.date
        }
    }

    static func shortLabel(_ phase: TrainingPhase) -> String {
        switch phase {
        case .baseBuilding: return "BASE"
        case .buildPhase:   return "BUILD"
        case .peakPhase:    return "PEAK"
        case .tapering:     return "TAPER"
        }
    }
}

// MARK: - Priority badge

/// A/B/C race-priority chip. The A-race anchors the macrocycle; B/C are tune-ups.
struct RacePriorityBadge: View {
    let priority: RacePriority
    @EnvironmentObject var themeManager: ThemeManager

    private var tint: Color {
        switch priority {
        case .a: return themeManager.primaryAccentColor
        case .b: return .orange
        case .c: return .secondary
        }
    }

    var body: some View {
        Text(priority.rawValue)
            .font(.caption2).fontWeight(.bold)
            .frame(width: 20, height: 20)
            .background(tint.opacity(0.15))
            .foregroundColor(tint)
            .clipShape(Circle())
            .accessibilityLabel(Text(String(localized: "\(priority.rawValue)-race")))
    }
}
