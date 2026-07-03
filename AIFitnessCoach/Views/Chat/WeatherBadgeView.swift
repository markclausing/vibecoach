import SwiftUI

// MARK: - WeatherBadgeView

/// Epic 21: Compact weather badge shown on a WorkoutCardView.
/// Shows a weather icon + precipitation probability. Orange/red for bad outdoor weather.
struct WeatherBadgeView: View {
    let forecast: DayForecast

    private var badgeColor: Color {
        forecast.isRiskyForOutdoorTraining ? .orange : Color(.secondaryLabel)
    }

    private var weatherIcon: String {
        let rain = forecast.precipitationProbability
        let wind = forecast.windSpeedKmh
        if rain > 0.7 || forecast.conditionDescription.contains("regen") { return "cloud.rain.fill" }
        if rain > 0.4 { return "cloud.drizzle.fill" }
        if wind > 40 { return "wind" }
        if forecast.conditionDescription.contains("bewolkt") { return "cloud.fill" }
        if forecast.conditionDescription.contains("Mistig") { return "cloud.fog.fill" }
        if forecast.conditionDescription.contains("sneeuw") { return "snowflake" }
        if forecast.conditionDescription.contains("Onweer") { return "cloud.bolt.rain.fill" }
        return "sun.max.fill"
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: weatherIcon)
                .font(.caption2)
                .foregroundColor(badgeColor)
            Text(String(format: "%.0f%%", forecast.precipitationProbability * 100))
                .font(.caption2)
                .foregroundColor(badgeColor)
            if forecast.windSpeedKmh > 30 {
                Image(systemName: "wind")
                    .font(.caption2)
                    .foregroundColor(badgeColor)
                Text(String(format: "%.0f", forecast.windSpeedKmh))
                    .font(.caption2)
                    .foregroundColor(badgeColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.12))
        .cornerRadius(6)
    }
}
