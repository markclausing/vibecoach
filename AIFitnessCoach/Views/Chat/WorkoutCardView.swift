import SwiftUI

struct WorkoutCardView: View {
    let workout: SuggestedWorkout
    /// Epic 21: Optional weather forecast for the day of this workout.
    var weatherForecast: DayForecast?
    var onSkip: (() -> Void)?
    var onAlternative: (() -> Void)?
    var onSelect: (() -> Void)?
    @EnvironmentObject var themeManager: ThemeManager

    @State private var isProcessingAction: Bool = false

    var body: some View {
        Button(action: {
            onSelect?()
        }) {
            VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workout.displayDayLabel)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(themeManager.primaryAccentColor.opacity(0.75))

                // Epic 21: Weather badge — only show if there is forecast data
                if let forecast = weatherForecast {
                    Spacer()
                    WeatherBadgeView(forecast: forecast)
                } else {
                    Spacer()
                }

                if isProcessingAction {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Menu {
                        Button(role: .destructive, action: {
                            isProcessingAction = true
                            onSkip?()
                            Task { @MainActor in try? await Task.sleep(nanoseconds: 5_000_000_000); isProcessingAction = false }
                        }) {
                            Label("Overslaan", systemImage: "trash")
                        }

                        Button(action: {
                            isProcessingAction = true
                            onAlternative?()
                            Task { @MainActor in try? await Task.sleep(nanoseconds: 5_000_000_000); isProcessingAction = false }
                        }) {
                            Label("Geef alternatief", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.gray)
                    }
                }
            }

            Text(workout.activityType)
                .font(.headline)

            // Sprint 17.3: Coach reasoning — why is this workout in the schedule?
            if let reasoning = workout.reasoning, !reasoning.isEmpty {
                Label(reasoning, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(themeManager.primaryAccentColor.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(workout.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

                // Statistics row: duration | TRIMP | 💧 fluid | 🍌 carbs
            WorkoutStatsRow(workout: workout)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: Color(.label).opacity(0.05), radius: 4, x: 0, y: 2)
            .opacity(isProcessingAction ? 0.5 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
