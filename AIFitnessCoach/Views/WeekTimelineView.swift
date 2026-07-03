import SwiftUI

/// V2.0 Sprint 1 (complete): Horizontal week timeline + collapsible day schedule + detail sheet.
struct WeekTimelineView: View {
    let plan: SuggestedTrainingPlan?
    let activities: [ActivityRecord]
    let currentWeekTRIMP: Double
    let weeklyTRIMPTarget: Double
    var weeklyForecast: [DayForecast] = []
    /// Epic #55 story 55.2: active goals, used to synthesize multi-day event stage
    /// entries ("Etappe X/N") that replace coach trainings on event days.
    var eventGoals: [FitnessGoal] = []
    /// Epic #56: per-date location-aware forecast for event stage days (keyed by start-of-day).
    var stageWeather: [Date: StageWeather] = [:]
    var onSkipWorkout: ((SuggestedWorkout) -> Void)?
    var onAlternativeWorkout: ((SuggestedWorkout) -> Void)?
    /// Story 33.2b: callback for "Herschrijf schema" — Dashboard wires this to
    /// `ChatViewModel.requestPlanReset(...)`. Optional so preview views without a
    /// reset flow keep working.
    var onResetSchema: (() -> Void)?
    /// Story 33.2b: loading state — disables the button and shows a ProgressView.
    var isResettingSchema: Bool = false

    @EnvironmentObject var themeManager: ThemeManager
    @State private var isExpanded = false
    @State private var selectedWorkout: SuggestedWorkout?

    // MARK: - Week helpers

    private var currentWeekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // swiftlint:disable:next force_unwrapping
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: today)! } // day arithmetic on a valid startOfDay date, never nil
    }

    private func planWorkout(for date: Date) -> SuggestedWorkout? {
        // Story 33.2a: use displayDate so moved sessions match correctly.
        plan?.workouts.first { Calendar.current.isDate($0.displayDate, inSameDayAs: date) }
    }

    /// Story 33.2b: number of manually moved workouts — determines whether the
    /// "Herschrijf schema" button is visible.
    private var swappedCount: Int {
        plan?.workouts.filter { $0.isSwapped }.count ?? 0
    }

    private func hasActivity(on date: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return false }
        return activities.contains { $0.startDate >= start && $0.startDate < end && ($0.trimp ?? 0) > 5 }
    }

    private func isRestDay(_ workout: SuggestedWorkout?) -> Bool {
        guard let w = workout else { return false }
        return w.isRestDay
    }

    private var todayEntry: WeekDayEntry? {
        entry(for: Calendar.current.startOfDay(for: Date()))
    }

    /// Epic #55 story 55.2: per-day entries — coach workouts merged with synthesized
    /// multi-day event stage entries (stages take precedence on event days).
    private var weekEntries: [(date: Date, entry: WeekDayEntry)] {
        WeekScheduleBuilder.entries(
            for: currentWeekDays,
            workouts: plan?.workouts ?? [],
            eventGoals: eventGoals
        )
    }

    private func entry(for date: Date) -> WeekDayEntry? {
        weekEntries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }?.entry
    }

    private var daysRemaining: Int {
        currentWeekDays.filter { $0 >= Calendar.current.startOfDay(for: Date()) }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if swappedCount > 0 && onResetSchema != nil {
                resetSchemaButton
            }
            circleTimeline

            if weekEntries.isEmpty {
                emptyPlanCard
            } else {
                mainCard
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            TrainingDetailSheet(
                workout: workout,
                forecast: weeklyForecast.first {
                    Calendar.current.isDate($0.date, inSameDayAs: workout.resolvedDate)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Story 33.2b: Reset Schema button

    private var resetSchemaButton: some View {
        Button {
            onResetSchema?()
        } label: {
            HStack(spacing: 8) {
                if isResettingSchema {
                    ProgressView()
                        .controlSize(.small)
                        .tint(themeManager.primaryAccentColor)
                    Text("Coach herberekent weekbelasting…")
                        .font(.subheadline).fontWeight(.medium)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.subheadline)
                    Text("Herschrijf schema rondom verplaatste sessie\(swappedCount == 1 ? "" : "s")")
                        .font(.subheadline).fontWeight(.medium)
                }
                Spacer()
            }
            .foregroundStyle(themeManager.primaryAccentColor)
            .padding(.vertical, 10).padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(themeManager.primaryAccentColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isResettingSchema)
        .padding(.horizontal)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("DEZE WEEK · PLAN")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)
            Spacer()
            if weeklyTRIMPTarget > 0 {
                Text("\(Int(currentWeekTRIMP)) / \(Int(weeklyTRIMPTarget)) TRIMP")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Horizontal row of dots

    private var circleTimeline: some View {
        HStack(spacing: 0) {
            ForEach(currentWeekDays, id: \.self) { date in
                let dayEntry = entry(for: date)
                DayCircleView(
                    date: date,
                    workout: dayEntry?.workout,
                    hasActivity: hasActivity(on: date),
                    isRest: isRestDay(dayEntry?.workout),
                    stageIndex: dayEntry?.stage?.stageIndex
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Main card (collapsed/expanded)

    private var mainCard: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedList
            } else {
                collapsedTodayRow
            }

            trimpProgressBar.padding(.horizontal, 16).padding(.top, 12)

            toggleButton
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Collapsed card: today

    private var collapsedTodayRow: some View {
        Group {
            switch todayEntry {
            case .workout(let workout):
                Button { selectedWorkout = workout } label: {
                    TodaySummaryRow(
                        workout: workout,
                        forecast: weeklyForecast.first {
                            Calendar.current.isDate($0.date, inSameDayAs: Date())
                        }
                    )
                }
                .buttonStyle(.plain)
            case .stage(let stage):
                // Epic #55 story 55.2: today is an event day — show the stage, not a training.
                StageDayRowView(
                    date: Calendar.current.startOfDay(for: Date()),
                    stage: stage,
                    isToday: true,
                    forecast: weeklyForecast.first {
                        Calendar.current.isDate($0.date, inSameDayAs: Date())
                    },
                    stageWeather: stageWeather[Calendar.current.startOfDay(for: Date())]
                )
            case .none:
                HStack {
                    Image(systemName: "moon.fill")
                        .foregroundColor(.secondary)
                    Text("Rustdag vandaag")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Expanded list

    private var expandedList: some View {
        VStack(spacing: 0) {
            ForEach(Array(weekEntries.enumerated()), id: \.offset) { index, row in
                let isLast = index == weekEntries.count - 1
                switch row.entry {
                case .workout(let workout):
                    WorkoutDayRowView(
                        date: row.date,
                        workout: workout,
                        isToday: Calendar.current.isDateInToday(row.date),
                        isCompleted: hasActivity(on: row.date),
                        forecast: weeklyForecast.first {
                            Calendar.current.isDate($0.date, inSameDayAs: row.date)
                        },
                        onTap: { selectedWorkout = workout },
                        onSkip: { onSkipWorkout?(workout) },
                        onAlternative: { onAlternativeWorkout?(workout) }
                    )
                case .stage(let stage):
                    StageDayRowView(
                        date: row.date,
                        stage: stage,
                        isToday: Calendar.current.isDateInToday(row.date),
                        forecast: weeklyForecast.first {
                            Calendar.current.isDate($0.date, inSameDayAs: row.date)
                        },
                        stageWeather: stageWeather[Calendar.current.startOfDay(for: row.date)]
                    )
                }
                if !isLast { Divider().padding(.leading, 72) }
            }
        }
    }

    // MARK: - TRIMP progress bar

    private var trimpProgressBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemFill))
                        .frame(height: 6)
                    let fraction = weeklyTRIMPTarget > 0
                        ? min(1.0, currentWeekTRIMP / weeklyTRIMPTarget)
                        : 0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(themeManager.primaryAccentColor)
                        .frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                if weeklyTRIMPTarget > 0 {
                    let pct = Int(min(100, currentWeekTRIMP / weeklyTRIMPTarget * 100))
                    Text("\(Int(currentWeekTRIMP)) / \(Int(weeklyTRIMPTarget)) TRIMP · \(pct)%")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(daysRemaining) dagen te gaan")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Toggle button

    private var toggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(isExpanded ? String(localized: "Minder") : String(localized: "Hele week bekijken"))
                    .font(.subheadline).fontWeight(.medium)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption).fontWeight(.semibold)
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Empty schedule

    private var emptyPlanCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 36)).foregroundColor(.secondary)
            Text("Nog geen schema voor deze week.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - TodaySummaryRow

/// The compact "today" card in the collapsed state of the week schedule.
private struct TodaySummaryRow: View {
    let workout: SuggestedWorkout
    var forecast: DayForecast?

    @EnvironmentObject var themeManager: ThemeManager

    // Epic #37 story 37.3: classify via the language-independent `kind` so a localized
    // activityType (e.g. German "Radfahren") still maps to the right icon/badge.
    private var icon: String {
        switch workout.kind {
        case .rest:     return "moon.fill"
        case .interval: return "bolt.fill"
        case .strength: return "dumbbell.fill"
        case .cycling:  return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .endurance, .longRun, .running: return "waveform.path.ecg"
        }
    }

    private var badgeLabel: String {
        switch workout.kind {
        case .interval:            return String(localized: "INTERVAL")
        case .strength:            return String(localized: "KRACHT")
        case .rest:                return String(localized: "RUST")
        case .longRun:             return String(localized: "LANGE DUUR")
        case .endurance, .cycling: return String(localized: "DUUR")
        case .swimming, .running:  return workout.heartRateZone?.uppercased() ?? ""
        }
    }

    // Epic #37 story 37.1c: rendered via Text(todayLabel) -> verbatim. The "VANDAAG" prefix is
    // localized; the date (%@) is locale-formatted.
    private var todayLabel: String {
        let f = AppDateFormatters.display("EEE d")
        return String(localized: "VANDAAG · \(f.string(from: Date()).uppercased())")
    }

    private var subtitle: String {
        var parts: [String] = []
        if workout.suggestedDurationMinutes > 0 { parts.append("\(workout.suggestedDurationMinutes) min") }
        if let d = workout.description.isEmpty ? nil : workout.description { parts.append(d) }
        if let trimp = workout.targetTRIMP, trimp > 0 { parts.append("\(trimp) TRIMP") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon block
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeManager.primaryAccentColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(themeManager.primaryAccentColor)
            }

            // Labels
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(todayLabel)
                        .font(.caption2).fontWeight(.medium).foregroundColor(.secondary)
                    if !badgeLabel.isEmpty {
                        Text(badgeLabel)
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(themeManager.primaryAccentColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(themeManager.primaryAccentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(workout.activityType)
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }

            Spacer()

            // Weather + chevron
            VStack(alignment: .trailing, spacing: 2) {
                if let f = forecast {
                    Image(systemName: weatherIconName(f))
                        .font(.caption).foregroundColor(.secondary)
                    Text("\(Int(f.highCelsius))°")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func weatherIconName(_ f: DayForecast) -> String {
        if f.precipitationProbability > 0.6 { return "cloud.rain.fill" }
        if f.precipitationProbability > 0.3 { return "cloud.drizzle.fill" }
        if f.windSpeedKmh > 30 { return "wind" }
        return "sun.max.fill"
    }
}
