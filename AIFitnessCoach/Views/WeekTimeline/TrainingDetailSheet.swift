import SwiftUI

// Epic #65 story 65.5: split out of WeekTimelineView.swift (§5 file-split). Pure move — no
// semantic changes; access relaxed private -> internal only where the split
// requires it (listed in the PR body).

// MARK: - TrainingDetailSheet

/// Detail sheet that opens when tapping a training in the week list.
struct TrainingDetailSheet: View {
    let workout: SuggestedWorkout
    var forecast: DayForecast?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var planManager: TrainingPlanManager
    @State private var showingMoveSheet = false

    private var dateLabel: String {
        let f = AppDateFormatters.display("EEE d MMM")
        // Story 33.2a: use displayDate so moved sessions show the NEW day.
        return f.string(from: workout.displayDate).uppercased()
    }

    // Epic #37 story 37.3: classify via the language-independent `kind`, then localize the badge.
    private var activityBadge: String {
        switch workout.kind {
        case .interval:            return String(localized: "INTERVAL")
        case .strength:            return String(localized: "KRACHT")
        case .rest:                return String(localized: "RUST")
        case .longRun:             return String(localized: "LANGE DUUR")
        case .endurance, .cycling: return String(localized: "DUUR")
        case .swimming, .running:  return workout.heartRateZone?.uppercased() ?? String(localized: "TRAINING")
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if workout.suggestedDurationMinutes > 0 { parts.append("\(workout.suggestedDurationMinutes) min") }
        if !workout.description.isEmpty { parts.append(workout.description) }
        if let t = workout.targetTRIMP, t > 0 { parts.append("\(t) TRIMP") }
        return parts.joined(separator: " · ")
    }

    // Estimate heart rate zone range based on the zone string (assumption: maxHR ~190)
    private var hrRange: String {
        guard let zone = workout.heartRateZone?.lowercased() else { return "—" }
        if zone.contains("1") { return "< 114 bpm" }
        if zone.contains("2") { return "114–133 bpm" }
        if zone.contains("3") { return "133–152 bpm" }
        if zone.contains("4") { return "152–171 bpm" }
        if zone.contains("5") { return "> 171 bpm" }
        return zone
    }

    // Nutrition advice based on duration and zone
    private var fuelingAdvice: (voor: String, tijdens: String, na: String) {
        let duration = workout.suggestedDurationMinutes
        let isIntense = workout.heartRateZone?.lowercased().contains("4") == true
                     || workout.heartRateZone?.lowercased().contains("5") == true
                     || workout.kind == .interval
        let isLong = duration >= 90

        if isLong {
            return (String(localized: "Maaltijd · 2u vooraf"), String(localized: "30g koolhydraten / 20 min + water"), String(localized: "Herstelmaaltijd binnen 45 min"))
        } else if isIntense {
            return (String(localized: "Lichte snack · 60 min vooraf"), String(localized: "Water"), String(localized: "Maaltijd binnen 90 min"))
        } else {
            return (String(localized: "Geen speciale voorbereiding"), String(localized: "Water"), String(localized: "Normale maaltijd"))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header: date + badge
                HStack(spacing: 8) {
                    Text(dateLabel)
                        .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                    Text(activityBadge)
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(themeManager.primaryAccentColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(themeManager.primaryAccentColor.opacity(0.12))
                        .clipShape(Capsule())
                    if workout.isSwapped {
                        Label("Verplaatst", systemImage: "arrow.triangle.swap")
                            .font(.caption2).fontWeight(.medium)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(themeManager.primaryAccentColor.opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(themeManager.primaryAccentColor)
                    }
                }

                // Title + subtitle
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.activityType)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.subheadline).foregroundColor(.secondary)
                }

                // Story 33.2a: Move the session to another day this week.
                Button {
                    showingMoveSheet = true
                } label: {
                    Label("Verplaats sessie", systemImage: "calendar.badge.clock")
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(themeManager.primaryAccentColor)

                // Three metric blocks
                HStack(spacing: 10) {
                    MetricBlock(label: "ZONE", value: workout.heartRateZone ?? "—", unit: nil)
                    MetricBlock(label: "HARTSLAG", value: hrRange, unit: nil)
                    MetricBlock(label: "TRIMP", value: workout.targetTRIMP.map { "\($0)" } ?? "—", unit: nil)
                }

                // Weather section
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

                // Nutrition section
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
        .sheet(isPresented: $showingMoveSheet) {
            MoveWorkoutSheet(workout: workout) { newDate in
                planManager.moveWorkout(workout, to: newDate)
                showingMoveSheet = false
                dismiss() // also close detail — UI must show the updated order
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func weatherIconFor(_ f: DayForecast) -> String {
        if f.precipitationProbability > 0.6 { return "cloud.rain.fill" }
        if f.precipitationProbability > 0.3 { return "cloud.drizzle.fill" }
        if f.windSpeedKmh > 30 { return "wind" }
        return "sun.max.fill"
    }

    // Epic #37 story 37.1c: rendered via Text(weatherAdvice(...)) -> verbatim, so localize each
    // branch. The embedded cycling/training distinction is split into two full sentences.
    private func weatherAdvice(_ f: DayForecast) -> String {
        if f.isRiskyForOutdoorTraining { return String(localized: "Overweeg een alternatieve indoor training.") }
        if f.highCelsius > 25 { return String(localized: "Warm — extra hydratatie aanbevolen.") }
        if f.windSpeedKmh < 20 && f.precipitationProbability < 0.2 {
            let isCycling = workout.kind == .cycling
            return isCycling ? String(localized: "Prima fietsweer.") : String(localized: "Prima trainingsweer.")
        }
        return String(localized: "Controleer het weer voor vertrek.")
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
