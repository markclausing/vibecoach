import Foundation
import SwiftData

/// Story 65.3: owns the coach's PHI context cache.
///
/// Extracted from `ChatViewModel` — the ~20 `cache*` setters, the PHI computed
/// properties and the `CoachContextCache` (SwiftData) bridge now live here. The view
/// model holds one instance (`context`) and views call `viewModel.context.cacheX(...)`.
///
/// `@MainActor` because it touches a SwiftData `ModelContext`. The stored strings inherit
/// `NSFileProtectionCompleteUnlessOpen` from the container (Story 61.3 / 61.7) — PHI no
/// longer sits in an unprotected `@AppStorage` plist between dashboard refreshes.
@MainActor
final class CoachContextStore {

    private var contextCache: CoachContextCache?
    private var configuredModelContext: ModelContext?

    /// Injects the SwiftData model context and loads (or creates) the singleton
    /// `CoachContextCache` record. Call once from the view hierarchy — subsequent calls
    /// are no-ops. All context properties below return `""` / `0` until this has been
    /// called, which is safe because they are only read when building a prompt (a user
    /// action that cannot happen before the view appears).
    func configure(with context: ModelContext) {
        guard configuredModelContext == nil else { return }
        configuredModelContext = context
        let existing = (try? context.fetch(FetchDescriptor<CoachContextCache>()))?.first
        if let existing {
            contextCache = existing
        } else {
            let cache = CoachContextCache()
            context.insert(cache)
            contextCache = cache
        }
    }

    // MARK: - PHI context properties
    // Backed by CoachContextCache in SwiftData (NSFileProtectionCompleteUnlessOpen).
    // Fall back to "" / 0 before configure(with:) is called — safe, see comment above.

    /// Epic 14.4: today's Vibe Score for injection into AI prompts.
    var todayVibeScoreContext: String {
        get { contextCache?.todayVibeScoreContext ?? "" }
        set { contextCache?.todayVibeScoreContext = newValue }
    }

    /// Epic 18.1: RPE + mood of the last workout.
    var lastWorkoutFeedbackContext: String {
        get { contextCache?.lastWorkoutFeedbackContext ?? "" }
        set { contextCache?.lastWorkoutFeedbackContext = newValue }
    }

    /// Epic 17: active blueprint status per goal.
    var blueprintContext: String {
        get { contextCache?.blueprintContext ?? "" }
        set { contextCache?.blueprintContext = newValue }
    }

    /// Epic 17.1: PeriodizationEngine status per goal.
    var periodizationContext: String {
        get { contextCache?.periodizationContext ?? "" }
        set { contextCache?.periodizationContext = newValue }
    }

    /// Timestamp of the last successful coach analysis (Unix timestamp).
    var lastAnalysisTimestamp: Double {
        get { contextCache?.lastAnalysisTimestamp ?? 0 }
        set { contextCache?.lastAnalysisTimestamp = newValue }
    }

    /// Epic 18: daily symptom scores — pain per body area.
    var symptomContext: String {
        get { contextCache?.symptomContext ?? "" }
        set { contextCache?.symptomContext = newValue }
    }

    /// Epic 21: 7-day weather forecast for outdoor training advice.
    var weatherContext: String {
        get { contextCache?.weatherContext ?? "" }
        set { contextCache?.weatherContext = newValue }
    }

    /// Epic 32 Story 32.3c: physiological patterns in recent workouts.
    var workoutPatternsContext: String {
        get { contextCache?.workoutPatternsContext ?? "" }
        set { contextCache?.workoutPatternsContext = newValue }
    }

    /// Epic 45 Story 45.3: per-workout detail over the past 14 days.
    var workoutHistoryContext: String {
        get { contextCache?.workoutHistoryContext ?? "" }
        set { contextCache?.workoutHistoryContext = newValue }
    }

    /// Epic 23 Sprint 1: gap analysis per active goal.
    var gapAnalysisContext: String {
        get { contextCache?.gapAnalysisContext ?? "" }
        set { contextCache?.gapAnalysisContext = newValue }
    }

    /// Epic Doel-Intenties: intent instructions per goal.
    var intentContext: String {
        get { contextCache?.intentContext ?? "" }
        set { contextCache?.intentContext = newValue }
    }

    /// Epic #55 story 55.3: multi-day event-window blocks.
    var eventWindowContext: String {
        get { contextCache?.eventWindowContext ?? "" }
        set { contextCache?.eventWindowContext = newValue }
    }

    /// Epic 23 Sprint 2: future projection per goal.
    var projectionContext: String {
        get { contextCache?.projectionContext ?? "" }
        set { contextCache?.projectionContext = newValue }
    }

    /// Epic 24 Sprint 1: physiological profile + nutrition plan.
    var nutritionContext: String {
        get { contextCache?.nutritionContext ?? "" }
        set { contextCache?.nutritionContext = newValue }
    }

    /// Story 33.2a: manually moved workouts (isSwapped == true).
    var userOverrideContext: String {
        get { contextCache?.userOverrideContext ?? "" }
        set { contextCache?.userOverrideContext = newValue }
    }

    /// Story 33.4: Intent-vs-Execution analysis for the most recent workout.
    var intentExecutionContext: String {
        get { contextCache?.intentExecutionContext ?? "" }
        set { contextCache?.intentExecutionContext = newValue }
    }

    /// Epic 24 Sprint 3: one-time coach notice on a detected profile change.
    var profileUpdateNote: String {
        get { contextCache?.profileUpdateNote ?? "" }
        set { contextCache?.profileUpdateNote = newValue }
    }

    // MARK: - Snapshot

    /// A deterministic snapshot of every context string, for the prompt assembler.
    func snapshot() -> CoachPromptAssembler.CoachContextSnapshot {
        CoachPromptAssembler.CoachContextSnapshot(
            todayVibeScoreContext: todayVibeScoreContext,
            lastWorkoutFeedbackContext: lastWorkoutFeedbackContext,
            userOverrideContext: userOverrideContext,
            intentExecutionContext: intentExecutionContext,
            symptomContext: symptomContext,
            workoutPatternsContext: workoutPatternsContext,
            workoutHistoryContext: workoutHistoryContext,
            weatherContext: weatherContext,
            blueprintContext: blueprintContext,
            periodizationContext: periodizationContext,
            intentContext: intentContext,
            eventWindowContext: eventWindowContext,
            gapAnalysisContext: gapAnalysisContext,
            projectionContext: projectionContext,
            nutritionContext: nutritionContext,
            profileUpdateNote: profileUpdateNote
        )
    }

    // MARK: - Cache setters

    /// Marks in the AI cache that the Vibe Score is missing because the Watch was not worn.
    /// The coach then explicitly gets the instruction to rely on symptom scores and own feeling.
    func cacheVibeScoreUnavailable() {
        todayVibeScoreContext = VibeScoreContextFormatter.noVibeDataSentinel
    }

    /// Epic 14.4: Writes today's Vibe Score to the cache.
    func cacheVibeScore(_ readiness: DailyReadiness?) {
        todayVibeScoreContext = VibeScoreContextFormatter.format(
            readiness: readiness,
            previousValue: todayVibeScoreContext
        )
    }

    /// Story 33.2a: writes the USER_OVERRIDE block (manually moved workouts) to the cache.
    func cacheUserOverrides(_ workouts: [SuggestedWorkout]) {
        userOverrideContext = UserOverrideContextFormatter.format(workouts: workouts)
    }

    /// Story 33.4: writes the Intent-vs-Execution analysis to the cache. Pass `""` to clear.
    func cacheIntentExecution(_ formatted: String) {
        intentExecutionContext = formatted
    }

    /// Epic 18.1: Writes the subjective feedback (RPE + mood) of the last workout to the cache.
    func cacheLastWorkoutFeedback(rpe: Int?,
                                  mood: String?,
                                  workoutName: String?,
                                  trimp: Double?,
                                  startDate: Date? = nil,
                                  sessionType: SessionType? = nil) {
        lastWorkoutFeedbackContext = LastWorkoutContextFormatter.format(
            rpe: rpe,
            mood: mood,
            workoutName: workoutName,
            trimp: trimp,
            startDate: startDate,
            sessionType: sessionType
        )
    }

    /// Epic 17: Writes the blueprint status of all active goals to the cache.
    func cacheActiveBlueprints(_ results: [BlueprintCheckResult]) {
        blueprintContext = BlueprintContextFormatter.format(results: results)
    }

    /// Epic 17.1: Writes the PeriodizationEngine status to the cache.
    func cachePeriodizationStatus(_ results: [PeriodizationResult]) {
        guard !results.isEmpty else {
            periodizationContext = ""
            return
        }
        periodizationContext = results
            .map { $0.coachingContext }
            .joined(separator: "\n\n")
    }

    /// Epic Doel-Intenties: Writes the intent instructions per goal to the cache.
    func cacheIntentContext(_ results: [PeriodizationResult]) {
        intentContext = IntentContextFormatter.format(results: results)
    }

    /// Epic #55 story 55.3: Writes the multi-day event-window block(s) to the cache.
    func cacheEventWindow(_ goals: [FitnessGoal]) {
        eventWindowContext = EventWindowContextFormatter.format(goals: goals)
    }

    /// Epic 23 Sprint 1: Writes the gap analysis (planned vs. realized) to the cache.
    func cacheGapAnalysis(_ gaps: [BlueprintGap]) {
        guard !gaps.isEmpty else {
            gapAnalysisContext = ""
            return
        }
        gapAnalysisContext = gaps
            .map { $0.coachContext }
            .joined(separator: "\n\n")
    }

    /// Epic 23 Sprint 2: Writes the future projection per goal to the cache.
    func cacheProjections(_ projections: [GoalProjection]) {
        projectionContext = FutureProjectionService.buildCoachContext(from: projections)
    }

    /// Epic 18 Sprint 2: Writes the daily symptom scores + hard constraints to the cache.
    func cacheSymptomContext(_ symptoms: [Symptom], preferences: [UserPreference] = []) {
        symptomContext = SymptomContextFormatter.format(symptoms: symptoms, preferences: preferences)

        // Debug: the full injury section that goes to the coach is PHI — log it
        // only at .debug level with .private redaction (stripped in release).
        AppLoggers.coach.debug("Injury section → coach: \(self.symptomContext, privacy: .private)")
    }

    /// Epic #62 story 62.1: clears every goal-derived prompt-context cache immediately after a
    /// goal is deleted, so the coach can't keep referencing a goal that no longer exists.
    func clearGoalDerivedContext() {
        blueprintContext = ""
        periodizationContext = ""
        intentContext = ""
        eventWindowContext = ""
        gapAnalysisContext = ""
        projectionContext = ""
    }
}
