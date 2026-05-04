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

    /// Loads the plan from AppStorage — sorteert altijd chronologisch.
    private func loadPlan() {
        if let decodedPlan = try? JSONDecoder().decode(SuggestedTrainingPlan.self, from: latestSuggestedPlanData) {
            self.activePlan = sorted(decodedPlan)
        }
    }

    /// Updates the plan, sorteert chronologisch, publiceert de wijziging en slaat op in AppStorage.
    func updatePlan(_ newPlan: SuggestedTrainingPlan) {
        let sorted = sorted(newPlan)
        self.activePlan = sorted
        if let encoded = try? JSONEncoder().encode(sorted) {
            latestSuggestedPlanData = encoded
        }
        // Debug: toon de chronologische volgorde na sortering
        print("📅 [TrainingPlan] Gesorteerde volgorde na update:")
        sorted.workouts.forEach { workout in
            print("   \(workout.dateOrDay) → displayDate: \(workout.displayDate)")
        }
    }

    /// Retourneert een nieuw SuggestedTrainingPlan met workouts gesorteerd op `displayDate`
    /// (chronologisch). Story 33.2a — door op `displayDate` te sorteren bewegen verplaatste
    /// sessies automatisch naar hun nieuwe positie in de UI.
    private func sorted(_ plan: SuggestedTrainingPlan) -> SuggestedTrainingPlan {
        let chronological = plan.workouts.sorted { $0.displayDate < $1.displayDate }
        return SuggestedTrainingPlan(
            motivation: plan.motivation,
            workouts: chronological,
            newPreferences: plan.newPreferences
        )
    }

    // MARK: - Story 33.2a: Verplaats sessie

    /// Verplaatst een geplande workout naar een nieuwe datum. Schrijft de override naar
    /// `scheduledDate`, markeert `isSwapped = true` (zodat de coach weet dat dit een
    /// gebruiker-gedreven keuze is), hersorteert de lijst zodat de UI direct meebeweegt
    /// en persisteert naar AppStorage.
    /// - Parameters:
    ///   - workout: De workout om te verplaatsen — gematched op `id`.
    ///   - newDate: De nieuwe datum (genormaliseerd naar `startOfDay`).
    /// - Returns: `true` als de workout gevonden en verplaatst is; `false` als de id niet
    ///   in het actieve plan voorkomt (dan is er niks te doen).
    @discardableResult
    func moveWorkout(_ workout: SuggestedWorkout, to newDate: Date) -> Bool {
        guard let plan = activePlan else { return false }
        guard let index = plan.workouts.firstIndex(where: { $0.id == workout.id }) else {
            return false
        }

        // `workouts` is `let` op de struct — bouw een nieuwe array met de override toegepast.
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

        // Update via de bestaande pijplijn — sortering op displayDate + persistence
        // + Published change gebeuren daarbinnen automatisch.
        updatePlan(updatedPlan)
        return true
    }

    // MARK: - Story 33.2b: Merge AI-replan met behoud van swaps

    /// Merge een door de AI voorgesteld plan met het huidige plan, waarbij handmatig
    /// verplaatste sessies (`isSwapped == true`) **leidend** zijn. AI-suggesties op
    /// dagen die overlappen met een swap worden genadeloos gefilterd — defense in
    /// depth tegen LLM-hallucinaties die "vergeten" dat een dag heilig was.
    ///
    /// - Parameter aiPlan: Het volledige door Gemini voorgestelde 7-daagse plan.
    /// - Returns: `true` als er een actief plan was om mee te mergen; `false` als
    ///   er nog geen plan bestond (dan kun je beter `updatePlan` direct aanroepen).
    @discardableResult
    func mergeReplannedPlan(_ aiPlan: SuggestedTrainingPlan) -> Bool {
        guard let currentPlan = activePlan else {
            return false
        }

        let calendar = Calendar.current
        let currentSwapped = currentPlan.workouts.filter { $0.isSwapped }
        let reservedDays = Set(currentSwapped.map { calendar.startOfDay(for: $0.displayDate) })

        // Filter AI-output: alleen voorstellen voor dagen die NIET door een swap bezet zijn.
        let aiNonOverlapping = aiPlan.workouts.filter { workout in
            let day = calendar.startOfDay(for: workout.displayDate)
            return !reservedDays.contains(day)
        }

        // Combineer: swaps + AI's voorstellen voor de overige dagen. `updatePlan`
        // sorteert vervolgens chronologisch op displayDate.
        let merged = currentSwapped + aiNonOverlapping

        let mergedPlan = SuggestedTrainingPlan(
            motivation: aiPlan.motivation,        // AI's motivatie behouden
            workouts: merged,
            newPreferences: aiPlan.newPreferences
        )
        updatePlan(mergedPlan)
        return true
    }
}
