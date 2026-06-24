import Foundation
import SwiftUI

/// Shared state manager for the active training plan.
/// It acts as the single source of truth for both DashboardView and ChatView.
@MainActor
class TrainingPlanManager: ObservableObject {
    @Published var activePlan: SuggestedTrainingPlan?
    @AppStorage("latestSuggestedPlanData") private var latestSuggestedPlanData: Data = Data()

    init() {
        loadPlan()
    }

    /// Loads the plan from AppStorage — always sorts chronologically.
    private func loadPlan() {
        if let decodedPlan = try? JSONDecoder().decode(SuggestedTrainingPlan.self, from: latestSuggestedPlanData) {
            self.activePlan = sorted(decodedPlan)
        }
    }

    /// Updates the plan, sorts chronologically, publishes the change and saves to AppStorage.
    /// Story 61.4 (L-2): every plan — whether AI-proposed, merged or user-moved —
    /// passes through the code-side safety validator here (the single chokepoint),
    /// so out-of-range model parameters are clamped before they are ever persisted
    /// or displayed, independent of the prompt guardrails.
    func updatePlan(_ newPlan: SuggestedTrainingPlan) {
        let validated = TrainingPlanSafetyValidator.sanitize(newPlan)
        if validated.clampedCount > 0 {
            AppLoggers.trainingPlan.notice("Clamped out-of-range parameters on \(validated.clampedCount, privacy: .public) model-proposed workout(s)")
        }
        let sorted = sorted(validated.plan)
        self.activePlan = sorted
        if let encoded = try? JSONEncoder().encode(sorted) {
            latestSuggestedPlanData = encoded
        }
        // Debug: confirm the update without dumping per-workout schedule detail.
        AppLoggers.trainingPlan.debug("Plan updated: \(sorted.workouts.count, privacy: .public) workouts (sorted chronologically)")
    }

    /// Returns a new SuggestedTrainingPlan with workouts sorted by `displayDate`
    /// (chronologically). Story 33.2a — by sorting on `displayDate`, moved
    /// sessions automatically shift to their new position in the UI.
    private func sorted(_ plan: SuggestedTrainingPlan) -> SuggestedTrainingPlan {
        let chronological = plan.workouts.sorted { $0.displayDate < $1.displayDate }
        return SuggestedTrainingPlan(
            motivation: plan.motivation,
            workouts: chronological,
            newPreferences: plan.newPreferences
        )
    }

    // MARK: - Story 33.2a: Move session

    /// Moves a planned workout to a new date. Writes the override to
    /// `scheduledDate`, marks `isSwapped = true` (so the coach knows this is a
    /// user-driven choice), re-sorts the list so the UI moves along immediately
    /// and persists to AppStorage.
    /// - Parameters:
    ///   - workout: The workout to move — matched by `id`.
    ///   - newDate: The new date (normalised to `startOfDay`).
    /// - Returns: `true` if the workout was found and moved; `false` if the id is not
    ///   in the active plan (then there is nothing to do).
    @discardableResult
    func moveWorkout(_ workout: SuggestedWorkout, to newDate: Date) -> Bool {
        guard let plan = activePlan else { return false }
        guard let index = plan.workouts.firstIndex(where: { $0.id == workout.id }) else {
            return false
        }

        // `workouts` is `let` on the struct — build a new array with the override applied.
        var updatedWorkouts = plan.workouts
        var moved = updatedWorkouts[index]
        moved.scheduledDate = Calendar.current.startOfDay(for: newDate)
        moved.isSwapped = true
        updatedWorkouts[index] = moved

        let updatedPlan = SuggestedTrainingPlan(
            motivation: plan.motivation,
            workouts: updatedWorkouts,
            newPreferences: plan.newPreferences
        )

        // Update via the existing pipeline — sorting on displayDate + persistence
        // + the Published change happen inside it automatically.
        updatePlan(updatedPlan)
        return true
    }

    // MARK: - Story 33.2b: Merge AI replan while preserving swaps

    /// Merge an AI-proposed plan with the current plan, where manually
    /// moved sessions (`isSwapped == true`) are **authoritative**. AI suggestions on
    /// days that overlap with a swap are mercilessly filtered out — defense in
    /// depth against LLM hallucinations that "forget" a day was sacred.
    ///
    /// - Parameter aiPlan: The full 7-day plan proposed by Gemini.
    /// - Returns: `true` if there was an active plan to merge with; `false` if
    ///   no plan existed yet (then prefer calling `updatePlan` directly).
    @discardableResult
    func mergeReplannedPlan(_ aiPlan: SuggestedTrainingPlan) -> Bool {
        guard let currentPlan = activePlan else {
            return false
        }

        let calendar = Calendar.current
        let currentSwapped = currentPlan.workouts.filter { $0.isSwapped }
        let reservedDays = Set(currentSwapped.map { calendar.startOfDay(for: $0.displayDate) })

        // Filter AI output: only proposals for days NOT occupied by a swap.
        let aiNonOverlapping = aiPlan.workouts.filter { workout in
            let day = calendar.startOfDay(for: workout.displayDate)
            return !reservedDays.contains(day)
        }

        // Combine: swaps + the AI's proposals for the remaining days. `updatePlan`
        // then sorts chronologically by displayDate.
        let merged = currentSwapped + aiNonOverlapping

        let mergedPlan = SuggestedTrainingPlan(
            motivation: aiPlan.motivation,        // keep the AI's motivation
            workouts: merged,
            newPreferences: aiPlan.newPreferences
        )
        updatePlan(mergedPlan)
        return true
    }
}
