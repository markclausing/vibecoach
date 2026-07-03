import SwiftUI

// Epic #65 story 65.5: split out of WeekTimelineView.swift (§5 file-split). Pure move — no
// semantic changes; access relaxed private -> internal only where the split
// requires it (listed in the PR body).

// MARK: - WorkoutDayRowView

struct WorkoutDayRowView: View {
    let date: Date
    let workout: SuggestedWorkout
    let isToday: Bool
    let isCompleted: Bool
    var forecast: DayForecast?
    var onTap: (() -> Void)?
    var onSkip: (() -> Void)?
    var onAlternative: (() -> Void)?

    @EnvironmentObject var themeManager: ThemeManager

    private var isRest: Bool {
        workout.isRestDay
    }

    private var dayLabel: (abbrev: String, number: String) {
        let a = AppDateFormatters.display("EEE")
        let n = AppDateFormatters.display("d")
        return (a.string(from: date).prefix(2).uppercased(), n.string(from: date))
    }

    private var workoutIcon: String {
        switch workout.kind {
        case .rest:     return "moon.fill"
        case .interval: return "bolt.fill"
        case .strength: return "dumbbell.fill"
        case .cycling:  return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .endurance, .longRun, .running: return "waveform.path.ecg"
        }
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
