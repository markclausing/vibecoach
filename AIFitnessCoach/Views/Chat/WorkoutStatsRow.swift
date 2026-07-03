import SwiftUI

// MARK: - Epic 24 Sprint 4: Nutrition UI components

/// Compact row with training statistics at the bottom of a WorkoutCardView.
/// Shows: ⏱ duration | ⚡ TRIMP | 💧 fluid | 🍌 carbs
struct WorkoutStatsRow: View {
    let workout: SuggestedWorkout

    private var fueling: WorkoutFuelingPlan? {
        NutritionService.fuelingPlan(for: workout, profile: UserProfileService.cachedProfile())
    }

    var body: some View {
        HStack(spacing: 10) {
            if workout.suggestedDurationMinutes > 0 {
                statChip(icon: "clock", value: "\(workout.suggestedDurationMinutes) min", color: .primary)
            }

            let trimpText = workout.targetTRIMP.map { "\($0)" } ?? "-"
            statChip(icon: "bolt.heart", value: "TRIMP: \(trimpText)", color: .primary)

            if let plan = fueling {
                statChip(icon: "drop.fill", value: "\(Int(plan.fluidMl.rounded())) ml", color: .blue)
                statChip(icon: "leaf.fill", value: "\(Int(plan.carbsGram.rounded())) g", color: .green)
            }
        }
    }

    private func statChip(icon: String, value: String, color: Color) -> some View {
        Label(value, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(color)
    }
}
