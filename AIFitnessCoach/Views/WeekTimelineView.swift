import SwiftUI

/// V2.0 Sprint 1: Horizontale week-tijdlijn + dagelijks workout-overzicht.
/// Vervangt de oude TrainingCalendarView op het dashboard met:
///   - Compacte bolletjesrij voor de 7 dagen van de huidige week
///   - Verticale lijst met gekleurde rijen per dag
struct WeekTimelineView: View {
    let plan: SuggestedTrainingPlan?
    let activities: [ActivityRecord]
    let currentWeekTRIMP: Double
    let weeklyTRIMPTarget: Double
    var weeklyForecast: [DayForecast] = []
    var onSkipWorkout: ((SuggestedWorkout) -> Void)?
    var onAlternativeWorkout: ((SuggestedWorkout) -> Void)?

    @EnvironmentObject var themeManager: ThemeManager

    // MARK: - Week helpers

    /// De 7 dagen van de huidige kalenderweek (maandag t/m zondag).
    private var currentWeekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        // weekday: 1=zon, 2=ma … 7=zat → offset naar maandag
        let daysSinceMon = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysSinceMon, to: today)!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    }

    private func planWorkout(for date: Date) -> SuggestedWorkout? {
        plan?.workouts.first { Calendar.current.isDate($0.resolvedDate, inSameDayAs: date) }
    }

    private func hasActivity(on date: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return false }
        return activities.contains { $0.startDate >= start && $0.startDate < end && ($0.trimp ?? 0) > 5 }
    }

    private func isRestDay(_ workout: SuggestedWorkout?) -> Bool {
        guard let w = workout else { return false }
        return w.activityType.lowercased().contains("rust") || w.suggestedDurationMinutes == 0
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            circleTimeline
            workoutList
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("DEZE WEEK · PLAN")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .kerning(0.5)
            Spacer()
            if weeklyTRIMPTarget > 0 {
                Text("\(Int(currentWeekTRIMP)) / \(Int(weeklyTRIMPTarget)) TRIMP")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Horizontale bolletjesrij

    private var circleTimeline: some View {
        HStack(spacing: 0) {
            ForEach(currentWeekDays, id: \.self) { date in
                DayCircleView(
                    date: date,
                    workout: planWorkout(for: date),
                    hasActivity: hasActivity(on: date),
                    isRest: isRestDay(planWorkout(for: date))
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Dagrijen

    private var workoutList: some View {
        let rows: [(date: Date, workout: SuggestedWorkout)] = currentWeekDays.compactMap { date in
            guard let workout = planWorkout(for: date) else { return nil }
            return (date, workout)
        }

        return Group {
            if rows.isEmpty {
                emptyPlanState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        let isLast = index == rows.count - 1
                        WorkoutDayRowView(
                            date: row.date,
                            workout: row.workout,
                            isToday: Calendar.current.isDateInToday(row.date),
                            isCompleted: hasActivity(on: row.date),
                            forecast: weeklyForecast.first { Calendar.current.isDate($0.date, inSameDayAs: row.date) },
                            onSkip: { onSkipWorkout?(row.workout) },
                            onAlternative: { onAlternativeWorkout?(row.workout) }
                        )
                        if !isLast {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                .padding(.horizontal)
            }
        }
    }

    private var emptyPlanState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("Nog geen schema voor deze week.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - DayCircleView

/// Compacte bolletje in de horizontale timeline: dag-afkorting + getal + statusicoon eronder.
struct DayCircleView: View {
    let date: Date
    let workout: SuggestedWorkout?
    let hasActivity: Bool
    let isRest: Bool

    @EnvironmentObject var themeManager: ThemeManager

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var isPast: Bool { date < Calendar.current.startOfDay(for: Date()) }
    private var isCompleted: Bool { isPast && hasActivity }

    private var dayAbbrev: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.dateFormat = "EEE"
        return f.string(from: date).prefix(2).uppercased()
    }

    private var dayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private var circleBackground: Color {
        if isToday { return themeManager.primaryAccentColor }
        if isCompleted { return themeManager.primaryAccentColor.opacity(0.12) }
        return Color(.systemBackground)
    }

    private var circleForeground: Color {
        if isToday { return .white }
        if isCompleted { return themeManager.primaryAccentColor }
        return .secondary
    }

    private var circleBorder: Color {
        if isToday { return .clear }
        if isCompleted { return .clear }
        return Color(.systemGray4)
    }

    private var subIcon: String {
        if isRest { return "moon.fill" }
        guard let w = workout else { return "minus" }
        let type = w.activityType.lowercased()
        if type.contains("interval") || type.contains("z4") { return "bolt.fill" }
        if type.contains("kracht") || type.contains("strength") { return "dumbbell.fill" }
        return "waveform.path.ecg"
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(dayAbbrev)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            ZStack {
                Circle()
                    .fill(circleBackground)
                    .overlay(Circle().stroke(circleBorder, lineWidth: 1))
                    .frame(width: 36, height: 36)

                if isCompleted && !isToday {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(circleForeground)
                } else {
                    Text(dayNumber)
                        .font(.system(size: 14, weight: isToday ? .bold : .regular))
                        .foregroundColor(isToday ? .white : (isPast ? .secondary : .primary))
                }
            }

            Image(systemName: subIcon)
                .font(.system(size: 9))
                .foregroundColor(isRest ? .secondary : (isToday ? themeManager.primaryAccentColor : .secondary))
        }
    }
}

// MARK: - WorkoutDayRowView

/// Één dag-rij in het overzicht onder de tijdlijn.
struct WorkoutDayRowView: View {
    let date: Date
    let workout: SuggestedWorkout
    let isToday: Bool
    let isCompleted: Bool
    var forecast: DayForecast? = nil
    var onSkip: (() -> Void)? = nil
    var onAlternative: (() -> Void)? = nil

    @EnvironmentObject var themeManager: ThemeManager

    private var isRest: Bool {
        workout.activityType.lowercased().contains("rust") || workout.suggestedDurationMinutes == 0
    }

    private var dayLabel: (abbrev: String, number: String) {
        let abbrevF = DateFormatter()
        abbrevF.locale = Locale(identifier: "nl_NL")
        abbrevF.dateFormat = "EEE"
        let numF = DateFormatter()
        numF.dateFormat = "d"
        return (abbrevF.string(from: date).prefix(2).uppercased(), numF.string(from: date))
    }

    private var workoutIcon: String {
        let type = workout.activityType.lowercased()
        if isRest { return "moon.fill" }
        if type.contains("interval") || type.contains("z4") { return "bolt.fill" }
        if type.contains("kracht") || type.contains("strength") { return "dumbbell.fill" }
        if type.contains("fiets") || type.contains("rit") || type.contains("cycling") { return "figure.outdoor.cycle" }
        return "figure.run"
    }

    private var subtitle: String {
        if isRest { return workout.description }
        var parts: [String] = []
        if workout.suggestedDurationMinutes > 0 {
            parts.append("\(workout.suggestedDurationMinutes) min")
        }
        if let trimp = workout.targetTRIMP, trimp > 0 {
            parts.append("\(trimp) TRIMP")
        }
        if let zone = workout.heartRateZone {
            parts.append(zone)
        }
        return parts.isEmpty ? workout.description : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Dag-label links
            VStack(spacing: 1) {
                Text(dayLabel.abbrev)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text(dayLabel.number)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isToday ? themeManager.primaryAccentColor : .primary)
            }
            .frame(width: 28)

            // Status-icoon in cirkel
            ZStack {
                Circle()
                    .fill(isCompleted
                          ? themeManager.primaryAccentColor.opacity(0.12)
                          : (isToday ? themeManager.primaryAccentColor.opacity(0.10) : Color(.systemGray6)))
                    .frame(width: 36, height: 36)
                Image(systemName: isCompleted ? "checkmark" : workoutIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isCompleted
                                     ? themeManager.primaryAccentColor
                                     : (isToday ? themeManager.primaryAccentColor : .secondary))
            }

            // Naam + details
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activityType)
                    .font(.subheadline)
                    .fontWeight(isToday ? .semibold : .regular)
                    .foregroundColor(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Weersindicator
            if let f = forecast {
                HStack(spacing: 3) {
                    Image(systemName: weatherIcon(for: f))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(f.highCelsius))°")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(isToday ? themeManager.primaryAccentColor.opacity(0.06) : Color(.systemBackground))
        .contextMenu {
            if !isRest && !isCompleted {
                Button { onSkip?() } label: {
                    Label("Overslaan", systemImage: "arrow.right.circle")
                }
                Button { onAlternative?() } label: {
                    Label("Alternatief", systemImage: "arrow.2.squarepath")
                }
            }
        }
    }

    private func weatherIcon(for forecast: DayForecast) -> String {
        if forecast.precipitationProbability > 0.6 { return "cloud.rain.fill" }
        if forecast.precipitationProbability > 0.3 { return "cloud.drizzle.fill" }
        if forecast.windSpeedKmh > 30 { return "wind" }
        return "sun.max.fill"
    }
}
