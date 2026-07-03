import SwiftUI

/// Detailed view for a single workout, intended to be shown as a bottom sheet.
struct WorkoutDetailView: View {
    let workout: SuggestedWorkout
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var planManager: TrainingPlanManager
    @State private var showingMoveSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(workout.displayDayLabel)
                                .font(.headline)
                                .foregroundStyle(themeManager.primaryAccentColor.opacity(0.75))
                            if workout.isSwapped {
                                // Story 33.2a: visual confirmation that the user moved this
                                // session themselves — prevents confusion when the day differs
                                // from the original AI suggestion.
                                Label("Verplaatst", systemImage: "arrow.triangle.swap")
                                    .font(.caption2).fontWeight(.medium)
                                    .padding(.vertical, 3).padding(.horizontal, 8)
                                    .background(themeManager.primaryAccentColor.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundStyle(themeManager.primaryAccentColor)
                            }
                        }

                        Text(workout.activityType)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .padding(.top)

                    // Story 33.2a: action button to move the session to another day.
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

                    // Info section with icons
                    VStack(spacing: 16) {
                        InfoRowView(icon: "clock", title: "Duur", value: "\(workout.suggestedDurationMinutes) minuten")

                        if let trimp = workout.targetTRIMP {
                            InfoRowView(icon: "bolt.heart", title: "Doel TRIMP", value: "\(trimp)")
                        }

                        if let zone = workout.heartRateZone {
                            InfoRowView(icon: "heart.text.square", title: "Hartslagzone", value: zone)
                        }

                        if let pace = workout.targetPace {
                            InfoRowView(icon: "speedometer", title: "Doel Tempo", value: pace)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)

                    // Nutrition & Hydration section (Epic 24)
                    let profile = UserProfileService.cachedProfile()
                    if let plan = NutritionService.fuelingPlan(for: workout, profile: profile) {
                        WorkoutFuelingSectionView(plan: plan)
                    }

                    // Description section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Omschrijving")
                            .font(.headline)

                        Text(workout.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(.horizontal)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sluiten") {
                        dismiss()
                    }
                }
            }
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
    }
}
