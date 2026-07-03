import Foundation

// MARK: - Story 61.4 (security-review follow-up): code-side training-plan safety bounds
//
// The physiological safety limits the coach is told to respect (session length,
// week-over-week progression, intensity caps) live only in the *prompt text*.
// A hallucinated or injection-steered model response could therefore propose an
// extreme value (e.g. a 9 999-minute session or an absurd TRIMP) that would be
// persisted and shown as advice unaltered (review L-2 / LLM09 overreliance).
//
// This validator is the code-side guardrail, independent of the prompt: it
// clamps the model-proposed numeric parameters into physiologically-plausible
// bounds *before* the plan is persisted or displayed. It deliberately clamps
// (rather than rejecting the whole plan) so a single bad field never discards an
// otherwise-usable week; the number of clamps is reported so the caller can log
// it. Pure value-in/value-out — no AppStorage, no I/O (§6), so it is trivially
// unit-testable and runs at every `TrainingPlanManager.updatePlan` chokepoint.
enum TrainingPlanSafetyValidator {

    /// Upper bound for a single planned session, in minutes. 10 hours sits well
    /// above any realistic endurance session (long ride, marathon long run, ultra
    /// block) yet rejects the thousands-of-minutes values a hallucination produces.
    static let maxDurationMinutes = 600

    /// Upper bound for a single session's target TRIMP. ~1000 is far above a very
    /// long, very hard session, so legitimate plans pass untouched while absurd
    /// values are capped.
    static let maxTargetTRIMP = 1000

    struct Result: Equatable {
        let plan: SuggestedTrainingPlan
        /// How many workouts had at least one parameter clamped.
        let clampedCount: Int
    }

    /// Returns a copy of `plan` with each workout's `suggestedDurationMinutes` and
    /// `targetTRIMP` clamped into the safe ranges above (negatives → 0). All other
    /// fields — including `id`, `scheduledDate` and `isSwapped` — are preserved.
    static func sanitize(_ plan: SuggestedTrainingPlan) -> Result {
        var clampedCount = 0

        let safeWorkouts = plan.workouts.map { workout -> SuggestedWorkout in
            let safeDuration = min(max(workout.suggestedDurationMinutes, 0), maxDurationMinutes)
            let safeTRIMP: Int? = workout.targetTRIMP.map { min(max($0, 0), maxTargetTRIMP) }

            guard safeDuration != workout.suggestedDurationMinutes || safeTRIMP != workout.targetTRIMP else {
                return workout
            }
            clampedCount += 1
            return SuggestedWorkout(
                id: workout.id,
                dateOrDay: workout.dateOrDay,
                activityType: workout.activityType,
                suggestedDurationMinutes: safeDuration,
                targetTRIMP: safeTRIMP,
                description: workout.description,
                heartRateZone: workout.heartRateZone,
                targetPace: workout.targetPace,
                reasoning: workout.reasoning,
                scheduledDate: workout.scheduledDate,
                isSwapped: workout.isSwapped
            )
        }

        let safePlan = SuggestedTrainingPlan(
            motivation: plan.motivation,
            workouts: safeWorkouts,
            newPreferences: plan.newPreferences
        )
        return Result(plan: safePlan, clampedCount: clampedCount)
    }
}
