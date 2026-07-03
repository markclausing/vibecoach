import SwiftUI

// Epic #65 story 65.5: split out of WeekTimelineView.swift (§5 file-split). Pure move — no
// semantic changes; access relaxed private -> internal only where the split
// requires it (listed in the PR body).

// MARK: - StageDayRowView (Epic #55 story 55.2)

/// A single multi-day event day in the week list, rendered as "Etappe X/N" with the
/// event title instead of a coach training. Non-interactive: the event window is fixed,
/// there is nothing to swap or open. Visually distinct via the accent-coloured flag icon.
struct StageDayRowView: View {
    let date: Date
    let stage: EventStageEntry
    let isToday: Bool
    /// Home-location forecast (fallback).
    var forecast: DayForecast?
    /// Epic #56: forecast + place name at the stage's approximate location along the route.
    var stageWeather: StageWeather?

    @EnvironmentObject var themeManager: ThemeManager

    /// Prefer the location-aware stage forecast; fall back to the home forecast.
    private var displayForecast: DayForecast? { stageWeather?.forecast ?? forecast }

    private var dayLabel: (abbrev: String, number: String) {
        let a = AppDateFormatters.display("EEE")
        let n = AppDateFormatters.display("d")
        return (a.string(from: date).prefix(2).uppercased(), n.string(from: date))
    }

    // Epic #37 §13: pre-format the numbers as String so the catalog key stays "%@/%@"
    // (avoids the %lld-vs-%@ mismatch that silently falls back to the source language).
    private var stageLabel: String {
        let index = String(stage.stageIndex)
        let total = String(stage.totalStages)
        return String(localized: "Etappe \(index)/\(total)")
    }

    var body: some View {
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
                    .fill(themeManager.primaryAccentColor.opacity(isToday ? 0.18 : 0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.primaryAccentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(stageLabel)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(themeManager.primaryAccentColor)
                // User-entered free text (the goal title) — render verbatim, not localized.
                Text(stage.goalTitle)
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }

            Spacer()

            if let f = displayForecast {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: weatherIconFor(f)).font(.caption).foregroundColor(.secondary)
                        Text("\(Int(f.highCelsius))°").font(.caption).foregroundColor(.secondary)
                    }
                    // Epic #56: the approximate location this forecast is for ("≈ Emmerich").
                    if let place = stageWeather?.placeName, !place.isEmpty {
                        Text("≈ \(place)")
                            .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(isToday ? themeManager.primaryAccentColor.opacity(0.07) : Color(.systemBackground))
    }

    private func weatherIconFor(_ f: DayForecast) -> String {
        if f.precipitationProbability > 0.6 { return "cloud.rain.fill" }
        if f.precipitationProbability > 0.3 { return "cloud.drizzle.fill" }
        if f.windSpeedKmh > 30 { return "wind" }
        return "sun.max.fill"
    }
}
