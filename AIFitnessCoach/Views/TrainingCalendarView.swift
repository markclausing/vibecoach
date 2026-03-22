import SwiftUI

/// Een visuele component om een trainingsschema voor 7 dagen te tonen op basis van Gemini JSON output.
struct TrainingCalendarView: View {
    let plan: SuggestedTrainingPlan

    // Bijvoorbeeld een callback als we een training willen wegdrukken of aanpassen
    var onDismissWorkout: ((SuggestedWorkout) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Jouw Plan voor de komende 7 dagen")
                .font(.headline)

            Text(plan.motivation)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .italic()
                .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(plan.workouts) { workout in
                        WorkoutCardView(workout: workout, onDismiss: {
                            onDismissWorkout?(workout)
                        })
                    }
                }
                .padding(.horizontal, 4) // voor schaduw clips
            }
        }
    }
}

struct WorkoutCardView: View {
    let workout: SuggestedWorkout
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workout.dateOrDay)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Spacer()
                Button(action: {
                    onDismiss?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }

            Text(workout.activityType)
                .font(.headline)

            Text(workout.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                if workout.suggestedDurationMinutes > 0 {
                    Label("\(workout.suggestedDurationMinutes) min", systemImage: "clock")
                        .font(.caption2)
                }
                if workout.targetTRIMP > 0 {
                    Label("TRIMP: \(workout.targetTRIMP)", systemImage: "bolt.heart")
                        .font(.caption2)
                }
            }
        }
        .padding()
        .frame(width: 180, height: 160)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}
