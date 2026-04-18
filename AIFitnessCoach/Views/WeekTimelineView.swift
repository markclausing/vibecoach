import SwiftUI

/// V2.0 Sprint 1 (compleet): Horizontale week-tijdlijn + in/uitklapbaar dagschema + detail-sheet.
struct WeekTimelineView: View {
    let plan: SuggestedTrainingPlan?
    let activities: [ActivityRecord]
    let currentWeekTRIMP: Double
    let weeklyTRIMPTarget: Double
    var weeklyForecast: [DayForecast] = []
    var onSkipWorkout: ((SuggestedWorkout) -> Void)?
    var onAlternativeWorkout: ((SuggestedWorkout) -> Void)?

    @EnvironmentObject var themeManager: ThemeManager
    @State private var isExpanded = false
    @State private var selectedWorkout: SuggestedWorkout? = nil

    // MARK: - Week helpers

    private var currentWeekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let daysSinceMon = (cal.component(.weekday, from: today) + 5) % 7
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

    private var todayWorkout: SuggestedWorkout? {
        planWorkout(for: Calendar.current.startOfDay(for: Date()))
    }

    private var weekRows: [(date: Date, workout: SuggestedWorkout)] {
        currentWeekDays.compactMap { date in
            guard let w = planWorkout(for: date) else { return nil }
            return (date, w)
        }
    }

    private var daysRemaining: Int {
        currentWeekDays.filter { $0 >= Calendar.current.startOfDay(for: Date()) }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            circleTimeline

            if weekRows.isEmpty {
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

    // MARK: - Hoofd kaart (in/uitgeklapt)

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
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Ingeklapte kaart: vandaag

    private var collapsedTodayRow: some View {
        Group {
            if let workout = todayWorkout {
                Button { selectedWorkout = workout } label: {
                    TodaySummaryRow(
                        workout: workout,
                        forecast: weeklyForecast.first {
                            Calendar.current.isDate($0.date, inSameDayAs: Date())
                        }
                    )
                }
                .buttonStyle(.plain)
            } else {
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

    // MARK: - Uitgeklapte lijst

    private var expandedList: some View {
        VStack(spacing: 0) {
            ForEach(Array(weekRows.enumerated()), id: \.offset) { index, row in
                let isLast = index == weekRows.count - 1
                WorkoutDayRowView(
                    date: row.date,
                    workout: row.workout,
                    isToday: Calendar.current.isDateInToday(row.date),
                    isCompleted: hasActivity(on: row.date),
                    forecast: weeklyForecast.first {
                        Calendar.current.isDate($0.date, inSameDayAs: row.date)
                    },
                    onTap: { selectedWorkout = row.workout },
                    onSkip: { onSkipWorkout?(row.workout) },
                    onAlternative: { onAlternativeWorkout?(row.workout) }
                )
                if !isLast { Divider().padding(.leading, 72) }
            }
        }
    }

    // MARK: - TRIMP voortgangsbalk

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

    // MARK: - Toggle knop

    private var toggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(isExpanded ? "Minder" : "Hele week bekijken")
                    .font(.subheadline).fontWeight(.medium)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption).fontWeight(.semibold)
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Leeg schema

    private var emptyPlanCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 36)).foregroundColor(.secondary)
            Text("Nog geen schema voor deze week.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - TodaySummaryRow

/// De compacte "vandaag"-kaart in de ingeklapte staat van het weekschema.
private struct TodaySummaryRow: View {
    let workout: SuggestedWorkout
    var forecast: DayForecast?

    @EnvironmentObject var themeManager: ThemeManager

    private var icon: String {
        let t = workout.activityType.lowercased()
        if t.contains("interval") || t.contains("z4") { return "bolt.fill" }
        if t.contains("kracht") { return "dumbbell.fill" }
        if t.contains("fiets") || t.contains("rit") { return "figure.outdoor.cycle" }
        if t.contains("rust") { return "moon.fill" }
        return "waveform.path.ecg"
    }

    private var badgeLabel: String {
        let t = workout.activityType.lowercased()
        if t.contains("interval") { return "INTERVAL" }
        if t.contains("duur") || t.contains("z2") || t.contains("rit") { return "DUUR" }
        if t.contains("kracht") { return "KRACHT" }
        if t.contains("rust") { return "RUST" }
        return workout.heartRateZone?.uppercased() ?? ""
    }

    private var todayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.dateFormat = "EEE d"
        return "VANDAAG · \(f.string(from: Date()).uppercased())"
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
            // Icoon-blok
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

            // Weer + chevron
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

// MARK: - DayCircleView

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
        let f = DateFormatter(); f.locale = Locale(identifier: "nl_NL"); f.dateFormat = "EEE"
        return f.string(from: date).prefix(2).uppercased()
    }
    private var dayNumber: String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }

    private var subIcon: String {
        if isRest { return "moon.fill" }
        guard let w = workout else { return "minus" }
        let type = w.activityType.lowercased()
        if type.contains("interval") || type.contains("z4") { return "bolt.fill" }
        if type.contains("kracht") { return "dumbbell.fill" }
        return "waveform.path.ecg"
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(dayAbbrev)
                .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)

            ZStack {
                if isToday {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(themeManager.primaryAccentColor, lineWidth: 1.5)
                        .frame(width: 38, height: 38)
                }
                Circle()
                    .fill(isToday
                          ? themeManager.primaryAccentColor
                          : (isCompleted ? themeManager.primaryAccentColor.opacity(0.12) : Color(.systemBackground)))
                    .overlay(Circle().stroke(isToday || isCompleted ? Color.clear : Color(.systemGray4), lineWidth: 1))
                    .frame(width: 34, height: 34)

                if isCompleted && !isToday {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(themeManager.primaryAccentColor)
                } else {
                    Text(dayNumber)
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundColor(isToday ? .white : (isPast ? .secondary : .primary))
                }
            }
            .frame(width: 38, height: 38)

            Image(systemName: subIcon)
                .font(.system(size: 9))
                .foregroundColor(isRest ? .secondary : (isToday ? themeManager.primaryAccentColor : .secondary))
        }
    }
}

// MARK: - WorkoutDayRowView

struct WorkoutDayRowView: View {
    let date: Date
    let workout: SuggestedWorkout
    let isToday: Bool
    let isCompleted: Bool
    var forecast: DayForecast? = nil
    var onTap: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    var onAlternative: (() -> Void)? = nil

    @EnvironmentObject var themeManager: ThemeManager

    private var isRest: Bool {
        workout.activityType.lowercased().contains("rust") || workout.suggestedDurationMinutes == 0
    }

    private var dayLabel: (abbrev: String, number: String) {
        let a = DateFormatter(); a.locale = Locale(identifier: "nl_NL"); a.dateFormat = "EEE"
        let n = DateFormatter(); n.dateFormat = "d"
        return (a.string(from: date).prefix(2).uppercased(), n.string(from: date))
    }

    private var workoutIcon: String {
        let t = workout.activityType.lowercased()
        if isRest { return "moon.fill" }
        if t.contains("interval") || t.contains("z4") { return "bolt.fill" }
        if t.contains("kracht") { return "dumbbell.fill" }
        if t.contains("fiets") || t.contains("rit") { return "figure.outdoor.cycle" }
        return "waveform.path.ecg"
    }

    private var subtitle: String {
        if isRest { return workout.description }
        var parts: [String] = []
        if workout.suggestedDurationMinutes > 0 { parts.append("\(workout.suggestedDurationMinutes) min") }
        if !workout.description.isEmpty { parts.append(workout.description) }
        if let t = workout.targetTRIMP, t > 0 { parts.append("\(t) TRIMP") }
        return parts.isEmpty ? workout.activityType : parts.joined(separator: " · ")
    }

    var body: some View {
        Button {
            if !isRest { onTap?() }
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text(dayLabel.abbrev)
                        .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                    Text(dayLabel.number)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isToday ? themeManager.primaryAccentColor : .primary)
                }
                .frame(width: 28)

                ZStack {
                    Circle()
                        .fill(isCompleted
                              ? themeManager.primaryAccentColor.opacity(0.12)
                              : (isToday ? themeManager.primaryAccentColor.opacity(0.10) : Color(.systemGray6)))
                        .frame(width: 36, height: 36)
                    Image(systemName: isCompleted ? "checkmark" : workoutIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isCompleted || isToday ? themeManager.primaryAccentColor : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.activityType)
                        .font(.subheadline)
                        .fontWeight(isToday ? .semibold : .regular)
                        .foregroundColor(isCompleted ? .secondary : .primary)
                        .strikethrough(isCompleted)
                    Text(subtitle)
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }

                Spacer()

                if let f = forecast {
                    HStack(spacing: 3) {
                        Image(systemName: weatherIconFor(f)).font(.caption).foregroundColor(.secondary)
                        Text("\(Int(f.highCelsius))°").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(isToday ? themeManager.primaryAccentColor.opacity(0.07) : Color(.systemBackground))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isRest && !isCompleted {
                Button { onSkip?() } label: { Label("Overslaan", systemImage: "arrow.right.circle") }
                Button { onAlternative?() } label: { Label("Alternatief", systemImage: "arrow.2.squarepath") }
            }
        }
    }

    private func weatherIconFor(_ f: DayForecast) -> String {
        if f.precipitationProbability > 0.6 { return "cloud.rain.fill" }
        if f.precipitationProbability > 0.3 { return "cloud.drizzle.fill" }
        if f.windSpeedKmh > 30 { return "wind" }
        return "sun.max.fill"
    }
}

// MARK: - TrainingDetailSheet

/// Detail-sheet die opent bij het aantikken van een training in de week-lijst.
struct TrainingDetailSheet: View {
    let workout: SuggestedWorkout
    var forecast: DayForecast?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.dateFormat = "EEE d MMM"
        return f.string(from: workout.resolvedDate).uppercased()
    }

    private var activityBadge: String {
        let t = workout.activityType.lowercased()
        if t.contains("interval") { return "INTERVAL" }
        if t.contains("duur") || t.contains("rit") || t.contains("z2") { return "DUUR" }
        if t.contains("kracht") { return "KRACHT" }
        if t.contains("lang") { return "LANGE DUUR" }
        return workout.heartRateZone?.uppercased() ?? "TRAINING"
    }

    private var subtitle: String {
        var parts: [String] = []
        if workout.suggestedDurationMinutes > 0 { parts.append("\(workout.suggestedDurationMinutes) min") }
        if !workout.description.isEmpty { parts.append(workout.description) }
        if let t = workout.targetTRIMP, t > 0 { parts.append("\(t) TRIMP") }
        return parts.joined(separator: " · ")
    }

    // Schatting hartslagzone-bereik op basis van zone-string (aanname: maxHR ~190)
    private var hrRange: String {
        guard let zone = workout.heartRateZone?.lowercased() else { return "—" }
        if zone.contains("1") { return "< 114 bpm" }
        if zone.contains("2") { return "114–133 bpm" }
        if zone.contains("3") { return "133–152 bpm" }
        if zone.contains("4") { return "152–171 bpm" }
        if zone.contains("5") { return "> 171 bpm" }
        return zone
    }

    // Voedingsadvies op basis van duur en zone
    private var fuelingAdvice: (voor: String, tijdens: String, na: String) {
        let duration = workout.suggestedDurationMinutes
        let isIntense = workout.heartRateZone?.lowercased().contains("4") == true
                     || workout.heartRateZone?.lowercased().contains("5") == true
                     || workout.activityType.lowercased().contains("interval")
        let isLong = duration >= 90

        if isLong {
            return ("Maaltijd · 2u vooraf", "30g koolhydraten / 20 min + water", "Herstelmaaltijd binnen 45 min")
        } else if isIntense {
            return ("Lichte snack · 60 min vooraf", "Water", "Maaltijd binnen 90 min")
        } else {
            return ("Geen speciale voorbereiding", "Water", "Normale maaltijd")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header: datum + badge
                HStack(spacing: 8) {
                    Text(dateLabel)
                        .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                    Text(activityBadge)
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(themeManager.primaryAccentColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(themeManager.primaryAccentColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                // Titel + subtitel
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.activityType)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.subheadline).foregroundColor(.secondary)
                }

                // Drie metrics blokken
                HStack(spacing: 10) {
                    MetricBlock(label: "ZONE", value: workout.heartRateZone ?? "—", unit: nil)
                    MetricBlock(label: "HARTSLAG", value: hrRange, unit: nil)
                    MetricBlock(label: "TRIMP", value: workout.targetTRIMP.map { "\($0)" } ?? "—", unit: nil)
                }

                // Weer sectie
                if let f = forecast {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WEER")
                            .font(.caption).fontWeight(.semibold).foregroundColor(.secondary).kerning(0.5)

                        HStack(spacing: 14) {
                            Image(systemName: weatherIconFor(f))
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(f.conditionDescription) · \(Int(f.highCelsius))°")
                                    .font(.headline).foregroundColor(.primary)
                                Text("Wind \(Int(f.windSpeedKmh)) km/u · \(Int(f.precipitationProbability * 100))% neerslag")
                                    .font(.caption).foregroundColor(.secondary)
                                Text(weatherAdvice(f))
                                    .font(.caption).italic().foregroundColor(.secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Voeding sectie
                VStack(alignment: .leading, spacing: 10) {
                    Text("VOEDING")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.secondary).kerning(0.5)

                    let fueling = fuelingAdvice
                    FuelingRow(timing: "VOOR", advice: fueling.voor)
                    Divider()
                    FuelingRow(timing: "TIJDENS", advice: fueling.tijdens)
                    Divider()
                    FuelingRow(timing: "NA", advice: fueling.na)
                }
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
    }

    private func weatherIconFor(_ f: DayForecast) -> String {
        if f.precipitationProbability > 0.6 { return "cloud.rain.fill" }
        if f.precipitationProbability > 0.3 { return "cloud.drizzle.fill" }
        if f.windSpeedKmh > 30 { return "wind" }
        return "sun.max.fill"
    }

    private func weatherAdvice(_ f: DayForecast) -> String {
        if f.isRiskyForOutdoorTraining { return "Overweeg een alternatieve indoor training." }
        if f.highCelsius > 25 { return "Warm — extra hydratatie aanbevolen." }
        if f.windSpeedKmh < 20 && f.precipitationProbability < 0.2 { return "Prima \(workout.activityType.lowercased().contains("fiets") || workout.activityType.lowercased().contains("rit") ? "fietsweer" : "trainingsweeer")." }
        return "Controleer het weer voor vertrek."
    }
}

// MARK: - MetricBlock

private struct MetricBlock: View {
    let label: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary).kerning(0.5)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.7).lineLimit(1)
            if let u = unit {
                Text(u).font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - FuelingRow

private struct FuelingRow: View {
    let timing: String
    let advice: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timing)
                .font(.caption).fontWeight(.bold).foregroundColor(.primary)
                .frame(width: 52, alignment: .leading)
            Text(advice)
                .font(.subheadline).foregroundColor(.primary)
            Spacer()
        }
    }
}
