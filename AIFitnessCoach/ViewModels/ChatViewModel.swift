import Foundation
import SwiftUI
import SwiftData
import Combine

/// The viewmodel that tracks the chat state and handles actions.
@MainActor
class ChatViewModel: ObservableObject {
    /// List of stored chat messages.
    @Published var messages: [ChatMessage] = []
    /// The current text input from the user.
    @Published var inputText: String = ""
    /// An optionally selected image from the gallery.
    @Published var selectedImage: UIImage?
    /// True if the application is waiting for a response from the AI.
    @Published var isTyping: Bool = false

    /// Status message during a retry attempt, e.g. "Opnieuw proberen (1/3)...". Empty if no retry is running.
    @Published var retryStatusMessage: String = ""

    /// True if we are currently fetching Strava data via the explicit button.
    @Published var isFetchingWorkout: Bool = false

    /// User-friendly error message from the last AI call. `nil` as soon as a
    /// new call starts or completes successfully. Screens that do not show a chat
    /// (such as the Dashboard on pull-to-refresh) use this to show a banner —
    /// otherwise a timeout would fail silently because the chat bubble
    /// is not visible.
    @Published var lastAIErrorMessage: String?

    /// The protocol against which we run the AI requests.
    /// Lazy: only created on the first AI request, not at app start.
    /// Tests can inject a mock via the init parameter.
    private var _model: GenerativeModelProtocol?
    /// Epic #51-A2: the model name for which `_model` was built. Gets
    /// compared with the current AppStorage choice to automatically rebuild
    /// when the user switches Gemini model in Settings. Without this check
    /// the lazily-built model stayed stuck on the old name until a
    /// `rebuildRealModel()` trigger (key-flow only), so the next
    /// question after a model switch still went through the old model.
    private var _modelBuiltForName: String?

    /// Epic #53: the currently active provider (from AppStorage). One source so
    /// the rebuild check, the model snapshot and `buildGenerativeModel` consistently
    /// resolve the same provider-aware model name — otherwise a rebuild loop arises
    /// (built name ≠ compared name) with a non-Gemini provider.
    private var currentProvider: AIProvider { AIProvider.current() }

    private var model: GenerativeModelProtocol {
        if let existing = _model {
            // Mocks injected by tests or `-UITesting` have no
            // `_modelBuiltForName`. We leave those untouched — otherwise the
            // getter would overwrite the mock with a live `RealGenerativeModel`
            // that hits the `hasAPIKey` gate.
            if let builtName = _modelBuiltForName,
               builtName != AIModelAppStorageKey.resolvedPrimary(for: currentProvider) {
                // Built ourselves AND the configured model name has changed → rebuild.
            } else {
                return existing
            }
        }
        let resolvedName = AIModelAppStorageKey.resolvedPrimary(for: currentProvider)
        let built = buildGenerativeModel(modelName: resolvedName)
        _model = built
        _modelBuiltForName = resolvedName
        return built
    }

    /// Epic #51-A2: snapshot of the primary/fallback model names that are in use
    /// for the current `fetchAIResponse` call. Gets compared by the UI
    /// with the current AppStorage choice to show a banner if the user
    /// switches model during `isTyping`.
    @Published private(set) var activeRequestPrimaryModel: String = ""
    @Published private(set) var activeRequestFallbackModel: String = ""

    /// Epic #51-A6: handle to the running AI Task so `cancelOngoingRequest()`
    /// can cancel it when the user leaves the Coach tab (or sends a
    /// new message before the previous one is back). Without this reference
    /// the Gemini call kept running until natural completion and a
    /// "ghost" answer could appear when returning to the tab.
    private var currentRequestTask: Task<Void, Never>?

    /// Service for external API calls (Sprint 4.2).
    private let fitnessDataService: FitnessDataService

    /// Service for HealthKit (Sprint 7.2).
    private let healthKitManager: HealthKitManager
    private let fitnessCalculator: PhysiologicalCalculatorProtocol

    // MARK: - Story 61.7: PHI context cache in SwiftData (protected storage)
    //
    // The 17 prompt-context strings that used to live in @AppStorage (cleartext
    // UserDefaults/Library/Preferences) now live in a `CoachContextCache` SwiftData
    // record that inherits `NSFileProtectionCompleteUnlessOpen` from the container
    // (Story 61.3).  Access is through computed properties so the rest of the class
    // does not need to change.  The cache is loaded lazily on the first call to
    // `configure(with:)`, which AppTabHostView invokes on `.task`.

    private var contextCache: CoachContextCache?
    private var configuredModelContext: ModelContext?

    /// Injects the SwiftData model context and loads (or creates) the singleton
    /// `CoachContextCache` record.  Call once from the view hierarchy — subsequent
    /// calls are no-ops.  All context properties below return `""` / `0` until this
    /// has been called, which is safe because they are only read when building a
    /// prompt (a user action that cannot happen before the view appears).
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

    // Read the user's preference regarding the primary data source (Sprint 7.4)
    @AppStorage(AppStorageKeys.selectedDataSource) private var selectedDataSource: DataSource = .healthKit

    // Epic 20: BYOK — user-configured AI provider.
    // C-02: the API key itself is NO longer in @AppStorage but in the
    // Keychain (see `UserAPIKeyStore`). Reading happens via `effectiveAPIKey()`.
    @AppStorage("vibecoach_aiProvider") private var storedProviderRaw: String = AIProvider.gemini.rawValue

    /// The API key with which the current model was built.
    /// Kept track of to detect when a rebuild is needed.
    private var activeAPIKey: String = ""

    /// True if a usable API key is configured.
    var hasAPIKey: Bool {
        !effectiveAPIKey().isEmpty
    }

    /// The shared state manager for the current training plan.
    private var trainingPlanManager: TrainingPlanManager?

    /// Stored Data of the most recently generated plan (for fallback reference)
    @AppStorage("latestSuggestedPlanData") private var latestSuggestedPlanData: Data = Data()

    /// Stored insights/motivation from the coach to highlight on the dashboard
    @AppStorage("latestCoachInsight") private var latestCoachInsight: String = ""

    // MARK: - PHI context computed properties (Story 61.7)
    // Backed by CoachContextCache in SwiftData (NSFileProtectionCompleteUnlessOpen).
    // Fall back to "" / 0 before configure(with:) is called — safe, see comment above.

    /// Epic 14.4: today's Vibe Score for injection into AI prompts.
    private var todayVibeScoreContext: String {
        get { contextCache?.todayVibeScoreContext ?? "" }
        set { contextCache?.todayVibeScoreContext = newValue }
    }

    /// Epic 18.1: RPE + mood of the last workout.
    private var lastWorkoutFeedbackContext: String {
        get { contextCache?.lastWorkoutFeedbackContext ?? "" }
        set { contextCache?.lastWorkoutFeedbackContext = newValue }
    }

    /// Epic 17: active blueprint status per goal.
    private var blueprintContext: String {
        get { contextCache?.blueprintContext ?? "" }
        set { contextCache?.blueprintContext = newValue }
    }

    /// Epic 17.1: PeriodizationEngine status per goal.
    private var periodizationContext: String {
        get { contextCache?.periodizationContext ?? "" }
        set { contextCache?.periodizationContext = newValue }
    }

    /// Timestamp of the last successful coach analysis (Unix timestamp).
    var lastAnalysisTimestamp: Double {
        get { contextCache?.lastAnalysisTimestamp ?? 0 }
        set { contextCache?.lastAnalysisTimestamp = newValue }
    }

    /// Epic 18: daily symptom scores — pain per body area.
    private var symptomContext: String {
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
    private var gapAnalysisContext: String {
        get { contextCache?.gapAnalysisContext ?? "" }
        set { contextCache?.gapAnalysisContext = newValue }
    }

    /// Epic Doel-Intenties: intent instructions per goal.
    private var intentContext: String {
        get { contextCache?.intentContext ?? "" }
        set { contextCache?.intentContext = newValue }
    }

    /// Epic #55 story 55.3: multi-day event-window blocks.
    private var eventWindowContext: String {
        get { contextCache?.eventWindowContext ?? "" }
        set { contextCache?.eventWindowContext = newValue }
    }

    /// Epic 23 Sprint 2: future projection per goal.
    private var projectionContext: String {
        get { contextCache?.projectionContext ?? "" }
        set { contextCache?.projectionContext = newValue }
    }

    /// Epic 24 Sprint 1: physiological profile + nutrition plan.
    private var nutritionContext: String {
        get { contextCache?.nutritionContext ?? "" }
        set { contextCache?.nutritionContext = newValue }
    }

    /// Story 33.2a: manually moved workouts (isSwapped == true).
    private var userOverrideContext: String {
        get { contextCache?.userOverrideContext ?? "" }
        set { contextCache?.userOverrideContext = newValue }
    }

    /// Story 33.4: Intent-vs-Execution analysis for the most recent workout.
    private var intentExecutionContext: String {
        get { contextCache?.intentExecutionContext ?? "" }
        set { contextCache?.intentExecutionContext = newValue }
    }

    /// Epic 24 Sprint 3: one-time coach notice on a detected profile change.
    var profileUpdateNote: String {
        get { contextCache?.profileUpdateNote ?? "" }
        set { contextCache?.profileUpdateNote = newValue }
    }

    /// Callback to send new preferences to the View so they get stored in SwiftData.
    var onNewPreferencesDetected: (([ExtractedPreference]) -> Void)?

    /// Sets the TrainingPlanManager
    func setTrainingPlanManager(_ manager: TrainingPlanManager) {
        self.trainingPlanManager = manager
    }

    /// Epic 14.4: Writes today's Vibe Score to the AppStorage cache.
    /// Gets called from DashboardView on onAppear so the AI prompts
    /// always contain the current recovery status.
    /// Sentinel value indicating that no Watch data was available today.
    /// Gets recognized in buildContextPrefix to give the AI the correct instruction.
    /// Marks in the AI cache that the Vibe Score is missing because the Watch was not worn.
    /// The coach then explicitly gets the instruction to rely on symptom scores and own feeling.
    func cacheVibeScoreUnavailable() {
        todayVibeScoreContext = VibeScoreContextFormatter.noVibeDataSentinel
    }

    func cacheVibeScore(_ readiness: DailyReadiness?) {
        todayVibeScoreContext = VibeScoreContextFormatter.format(
            readiness: readiness,
            previousValue: todayVibeScoreContext
        )
    }

    /// Epic 20 / M-04: Returns the user-configured Gemini API key.
    /// There is no Secrets fallback anymore — BYOK is mandatory, the onboarding ensures
    /// a key is always filled in before AI functionality gets called.
    /// C-02: key gets read from the Keychain via `UserAPIKeyStore`.
    func effectiveAPIKey() -> String {
        return UserAPIKeyStore.read(for: currentProvider)
    }

    /// Builds a new Gemini model based on the current API key.
    /// Gets called when the user has stored a new key.
    /// Epic 20: Placeholder for Sprint 20.2 — stores the active key so future
    /// code can detect whether the key has changed and the model must be rebuilt.
    private func rebuildRealModel() {
        let key = effectiveAPIKey()
        guard !key.isEmpty else { return }
        activeAPIKey = key
        // Clear the cached instance so buildGenerativeModel() rebuilds it
        // with the new key on the next AI request.
        _model = nil
    }

    /// Epic 18.1: Writes the subjective feedback of the last workout to the AppStorage cache.
    /// Gets called from DashboardView as soon as there is an ActivityRecord with rpe and mood.
    /// The AI uses this to detect discrepancies (e.g. low TRIMP but high RPE = overtraining signal).
    /// Epic 33 Story 33.1b: optional `sessionType` — if present, the type + physiological
    /// intent is passed along so the coach calibrates his tone (no "too slow" with Recovery).
    /// Format logic lives in `LastWorkoutContextFormatter` (testable without ChatViewModel state).
    /// Story 33.2a: writes the USER_OVERRIDE block to the cache. Called from
    /// `DashboardView.onAppear` so the block is present on every plan-context build.
    func cacheUserOverrides(_ workouts: [SuggestedWorkout]) {
        userOverrideContext = UserOverrideContextFormatter.format(workouts: workouts)
    }

    /// Story 33.4: writes the Intent-vs-Execution analysis to the cache. Called
    /// from DashboardView when there is a recent match between a SuggestedWorkout
    /// and an ActivityRecord on the same calendar day. Pass `""` to clear the cache.
    func cacheIntentExecution(_ formatted: String) {
        intentExecutionContext = formatted
    }

    // MARK: - Story 33.2b: Reset Schema

    /// Determines whether `trainingPlanManager?.updatePlan` or `mergeReplannedPlan` is
    /// used as soon as a new plan comes back from Gemini. Default `.replace`
    /// preserves the existing behaviour of requestRecoveryPlan / skipWorkout etc.
    private enum PlanUpdateMode {
        case replace
        case mergePreservingSwaps
    }
    private var pendingPlanUpdateMode: PlanUpdateMode = .replace

    /// Story 33.2b: asks Gemini to re-plan the rest of the week around
    /// the manually moved sessions. The response plan gets merged by
    /// `TrainingPlanManager.mergeReplannedPlan(_:)` so overrides
    /// are guaranteed to remain, even with AI hallucinations on sacred days.
    /// - Parameter swappedWorkouts: The workouts with `isSwapped == true` from the
    ///   current plan. Caller (`WeekTimelineView`) supplies these.
    func requestPlanReset(swappedWorkouts: [SuggestedWorkout],
                          contextProfile: AthleticProfile? = nil,
                          activeGoals: [FitnessGoal] = [],
                          activePreferences: [UserPreference] = []) {
        // Prevent parallel resets — isTyping catches most cases, but the
        // mode flag must be protected too.
        guard !isTyping else { return }

        let (systemText, userText) = PlanResetPromptBuilder.build(swappedWorkouts: swappedWorkouts)
        pendingPlanUpdateMode = .mergePreservingSwaps
        sendHiddenSystemMessage(
            systemText: systemText,
            userText: userText,
            fallbackMessage: String(localized: "Ik heb je week opnieuw ingedeeld rondom je verplaatste sessies. Bekijk je overzicht."),
            contextProfile: contextProfile,
            activeGoals: activeGoals,
            activePreferences: activePreferences
        )
    }

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

    /// Epic 17: Writes the blueprint status of all active goals to the AppStorage cache.
    /// Gets called from DashboardView so the AI knows which critical workouts
    /// have already been achieved and which are still open — for more targeted coaching.
    func cacheActiveBlueprints(_ results: [BlueprintCheckResult]) {
        blueprintContext = BlueprintContextFormatter.format(results: results)
    }

    /// Epic 17.1: Writes the PeriodizationEngine status to the AppStorage cache.
    /// Gets called from DashboardView so the AI knows per goal which training phase
    /// the user is in and whether he meets the phase-specific success criteria.
    func cachePeriodizationStatus(_ results: [PeriodizationResult]) {
        guard !results.isEmpty else {
            periodizationContext = ""
            return
        }
        periodizationContext = results
            .map { $0.coachingContext }
            .joined(separator: "\n\n")
    }

    /// Epic Doel-Intenties: Writes the intent instructions per goal to the AppStorage cache.
    /// Gets called from ContentView (after cachePeriodizationStatus) so the AI receives a separate
    /// [GOAL INTENTS AND APPROACH] section with format, intent and VibeScore instructions.
    func cacheIntentContext(_ results: [PeriodizationResult]) {
        intentContext = IntentContextFormatter.format(results: results)
    }

    /// Epic #55 story 55.3: Writes the multi-day event-window block(s) to the AI prompt cache.
    /// Called from DashboardView so every coach interaction knows which dates are the event
    /// itself — and to suppress other training + plan post-event recovery.
    func cacheEventWindow(_ goals: [FitnessGoal]) {
        eventWindowContext = EventWindowContextFormatter.format(goals: goals)
    }

    /// Epic 23 Sprint 1: Writes the gap analysis (difference planned vs. realized) to the AppStorage cache.
    /// The coach uses this to give concrete adjustment advice:
    /// "You're X km behind schedule — 15% more volume this week to catch up."
    func cacheGapAnalysis(_ gaps: [BlueprintGap]) {
        guard !gaps.isEmpty else {
            gapAnalysisContext = ""
            return
        }
        gapAnalysisContext = gaps
            .map { $0.coachContext }
            .joined(separator: "\n\n")
    }

    /// Epic 23 Sprint 2: Writes the future projection per goal to the AppStorage cache.
    /// The coach uses this to proactively warn if a goal is "At Risk" or "Unreachable":
    /// "At your current pace you won't be ready for the marathon until July."
    func cacheProjections(_ projections: [GoalProjection]) {
        projectionContext = FutureProjectionService.buildCoachContext(from: projections)
    }

    /// Epic #62 story 62.1: clears every goal-derived prompt-context cache immediately after a
    /// goal is deleted, so the coach can't keep referencing a goal that no longer exists. The
    /// remaining goals' context is rebuilt on the next `DashboardView` appear (the standard
    /// refresh path), so this is a safe "forget now, re-derive on next visit" — no stale residue.
    func clearGoalDerivedContext() {
        blueprintContext = ""
        periodizationContext = ""
        intentContext = ""
        eventWindowContext = ""
        gapAnalysisContext = ""
        projectionContext = ""
    }

    /// Epic 24 Sprint 1: Fetches the physiological profile via HealthKit and computes the nutrition plan
    /// for today's and tomorrow's workouts based on the active training plan.
    /// Result gets cached in AppStorage and injected into every AI prompt.
    func refreshNutritionContext() async {
        let profileService = UserProfileService(healthStore: healthKitManager.healthStore)
        let profile = await profileService.fetchProfile()

        // Fetch the planned workouts from the active training plan (TrainingPlanManager).
        // We extract duration and zone per workout for today and tomorrow.
        let todayWorkouts   = extractPlannedWorkouts(for: 0)
        let tomorrowWorkouts = extractPlannedWorkouts(for: 1)

        nutritionContext = NutritionService.buildCoachContext(
            profile: profile,
            todayWorkouts: todayWorkouts,
            tomorrowWorkouts: tomorrowWorkouts
        )
        AppLoggers.coach.debug("Nutrition context updated: \(profile.coachSummary, privacy: .private)")
    }

    /// Extracts planned workouts (duration + zone) from the active plan for a relative day.
    /// `dayOffset` 0 = today, 1 = tomorrow.
    private func extractPlannedWorkouts(for dayOffset: Int) -> [(durationMinutes: Int, zone: TrainingZone)] {
        guard let plan = trainingPlanManager?.activePlan else { return [] }
        let targetDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        let targetDay  = Calendar.current.startOfDay(for: targetDate)

        return plan.workouts.compactMap { workout -> (Int, TrainingZone)? in
            let workoutDay = Calendar.current.startOfDay(for: workout.resolvedDate)
            guard workoutDay == targetDay else { return nil }
            // No nutrition plan for rest days (Epic #37: language-independent rest detection)
            guard !workout.isRestDay else { return nil }

            // Estimate the zone based on heart-rate zone or description in the plan.
            let zoneText = (workout.heartRateZone ?? workout.description).lowercased()
            let isHighIntensity = zoneText.contains("interval")
                || zoneText.contains("tempo")
                || zoneText.contains("drempel")
                || zoneText.contains("zone 4")
                || zoneText.contains("z4")
            let zone: TrainingZone = isHighIntensity ? .zone4 : .zone2

            // Use the planned duration; default 45 min if unknown.
            let duration = workout.suggestedDurationMinutes > 0 ? workout.suggestedDurationMinutes : 45
            return (duration, zone)
        }
    }

    /// Epic 18 Sprint 2: Writes the daily symptom scores + hard constraints to the AppStorage cache.
    /// The SymptomTracker is the 'Single Source of Truth' for injury status:
    /// - Score > 0 → active complaint, with constraint rules based on severity
    /// - Score == 0 → recovered, replaces any still-active UserPreference text
    /// - No score filled in + active UserPreference → show as 'unknown, score not entered yet'
    func cacheSymptomContext(_ symptoms: [Symptom], preferences: [UserPreference] = []) {
        symptomContext = SymptomContextFormatter.format(symptoms: symptoms, preferences: preferences)

        // Debug: the full injury section that goes to the coach is PHI — log it
        // only at .debug level with .private redaction (stripped in release).
        AppLoggers.coach.debug("Injury section → coach: \(self.symptomContext, privacy: .private)")
    }

    /// SPRINT 13.4: Returns the most recently stored coach insight (from AppStorage).
    /// Gets used by ChatView to show a welcome message if the chat is empty.
    var latestStoredInsight: String {
        return latestCoachInsight
    }

    /// SPRINT 13.4: Adds the most recent coach insight as a welcome message.
    /// Gets called only if `messages` is empty, so existing conversations are not disturbed.
    func injectWelcomeMessage(_ text: String) {
        guard messages.isEmpty, !text.isEmpty else { return }
        messages.append(ChatMessage(role: .ai, text: text))
    }

    /// Initializes the `ChatViewModel`.
    ///
    /// - Parameter aiModel: The AI service to be used.
    ///             When nothing is passed, the
    ///             `RealGenerativeModel` (the one that talks to the Google API) is used by default.
    init(aiModel: GenerativeModelProtocol? = nil,
         fitnessDataService: FitnessDataService = FitnessDataService(),
         healthKitManager: HealthKitManager = HealthKitManager(),
         fitnessCalculator: PhysiologicalCalculatorProtocol = PhysiologicalCalculator()) {
        self.fitnessDataService = fitnessDataService
        self.healthKitManager = healthKitManager
        self.fitnessCalculator = fitnessCalculator
        // Inject a test mock if one is passed; otherwise build lazily on first use.
        self._model = aiModel
    }

    /// Builds the Gemini model with the current API key and system instruction.
    /// Only gets called on the first real AI request (.onAppear or user action),
    /// not already during app start.
    ///
    /// Sprint 26.1: If `-UITesting` is active, a mock model is returned
    /// so the Gemini API is not called during E2E tests.
    ///
    /// Epic #35: if `modelName` is nil, this function reads the user-chosen
    /// primary model name from `AppStorage`. This keeps it possible to
    /// explicitly specify a different model from the fallback path.
    private func buildGenerativeModel(modelName: String? = nil) -> GenerativeModelProtocol {
        let provider = currentProvider
        let resolvedModelName = modelName ?? AIModelAppStorageKey.resolvedPrimary(for: provider)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            return UITestMockGenerativeModel()
        }
        #endif
        // Epic #51-A1: the scope instruction is the first block so the model
        // refuses off-topic questions before it even gets to the other coaching rules.
        // Text lives in ChatScopeInstruction so it is separately testable.
        // Epic #37 story 37.3: the coach replies in the user's chosen language. The instruction
        // body stays English (maintainability); only this directive steers the output language.
        let replyLanguage = AppLanguage.currentPromptLanguageName
        let systemInstruction = ChatScopeInstruction.text + """
            LANGUAGE — ABSOLUTE RULE:
            Always reply to the user in \(replyLanguage). Every piece of user-facing text you produce
            — your chat prose and the `motivation`, `description`, `reasoning` AND `activityType`
            fields in the JSON — MUST be written in \(replyLanguage), regardless of the language of
            these instructions (the Dutch example values below are illustrations only). The
            instructions below are in English for maintainability; your output to the user is always \(replyLanguage).

            You are a collaborative, thoughtful and proactive AI fitness coach.
            You don't just analyse fatigue — you actively help the user plan the very next step toward their stated goals.
            Position yourself as a smart training partner — not as a cautionary doctor.

            CRITICAL BEHAVIOUR RULE — CONTEXT RESPONSIVENESS:
            ALWAYS respond specifically to the user's LATEST message. Never just repeat the general status.
            - If the user mentions a specific workout (e.g. 'avondwandeling', 'intervaltraining'), respond to that specific workout.
            - If you adjust the schedule, CONFIRM it explicitly and concretely: 'Ik heb je geplande intervaltraining voor morgen verschoven naar donderdag vanwege je kuitklachten.' Name the day, the activity and the reason.
            - Never give a general overview when the question is specific. Be direct and personal.

            CRITICAL RULE — VIBE SCORE AUTHORITY:
            The user has a locally computed Vibe Score (0-100) that combines sleep and HRV. This score is the only objective measure of recovery.
            - Base your judgement about fatigue SOLELY on the Vibe Score you receive in the context.
            - Score ≥ 80: treat the user as well recovered. Even if sleep was slightly shorter than ideal.
            - Score 50-79: be careful but not alarming. Prioritize Zone 2 and lower intensity.
            - Score < 50: enforce rest or active recovery. This is a hard red flag.
            - NEVER contradict the Vibe Score based on your own estimate of sleep time or other factors.

            CRITICAL RULE — RPE DISCREPANCY (Epic 18):
            After a workout the user can enter a subjective exertion score (RPE 1-10).
            - If a workout's TRIMP is low or average (e.g. <60 TRIMP) but the RPE is ≥8: this is a serious early warning sign of overtraining or oncoming illness. Advise extra rest immediately and do NOT increase the plan's intensity.
            - If RPE is low (1-4) while TRIMP is high: the athlete is having a good day — use this in your planning.
            - Always combine the RPE with the Vibe Score for a complete picture.

            CRITICAL RULE — PERIODIZATION & PHASE COACHING (Sprint 17.2):
            For each goal you receive the current TrainingPhase, the success criteria and the achieved/outstanding status.
            Use this data ACTIVELY in your answers:
            - COMPLIMENTS (🎉 COMPLIMENT TRIGGER): If a phase requirement is met, open your answer with a sincere, specific compliment. Name the achievement (e.g. 'Great — you put down a 28 km run last week, exactly what the Build phase requires!').
            - URGENCY (🚨 CRITICAL MILESTONE SHORTFALL): If a critical requirement (e.g. the longest session) is not met, be direct but motivating. Name the exact distance or TRIMP still missing. Plan that milestone as the FIRST PRIORITY in the schedule.
            - SCHEDULE ACCOUNTABILITY: If you adjust the schedule because of injury, overload or another reason, you MUST always explain how the phase requirements are still achievable despite the change. Example: 'I'm replacing your running session with a long bike ride, but we'll safeguard the aerobic base for the Marathon Blueprint like this: on Saturday we'll plan a 26 km endurance run once your calf has recovered.'
            - Be strict but motivating — the coach stands beside the athlete, not above them.

            CRITICAL RULE — INJURY & SPORT INTERACTION:
            The daily pain scores and constraints are SOLELY in the [CURRENT COMPLAINTS] context you receive at every interaction.
            That block is the 'Single Source of Truth' — follow the HARD CONSTRAINTS in it strictly.
            - If a 🚫 HARD CONSTRAINT is present: ALWAYS adjust the schedule, name the constraint explicitly ('Given your calf pain of 7/10, we will NOT schedule any running sessions this week').
            - If a ✅ RECOVERED message is present: celebrate it in your Insight and propose a careful build-up.
            - If an area has 'score not entered today': be careful, but don't impose absolute bans.
            - Are there NO complaints listed? Then you may plan the schedule fully based on the blueprint and training phase.

            CRITICAL RULE — WEATHER-DRIVEN DAY PLANNING (Epic 21):
            You receive the 7-day weather forecast in the context. Use this ACTIVELY when creating or adjusting the schedule.
            - ALWAYS look at the next 3 days. If a key workout (long ride, tempo run, interval) can't go outside today because of ⚠️ BAD OUTDOOR WEATHER, but tomorrow or the day after the conditions are ideal, then EXPLICITLY propose swapping those days' workouts.
            - ALWAYS state the day swap in the `motivation` field: "I see Saturday has a 75% chance of rain but Sunday is clear and calm. I've moved your 60 km endurance ride to Sunday and put a shorter 45-min Zone 2 session on the indoor trainer today."
            - If the hard key workout moves to tomorrow or the day after: DELIBERATELY lower the TRIMP for the current day so the athlete starts the key workout rested. Advise max. 40-50% of the normal daily target as a 'charge day'. State this: "Today we keep your TRIMP low so you start tomorrow fresh."
            - Wind speed > 30 km/h is specifically relevant for cycling: always advise moving to a less windy day if there's an alternative within the next 3 days.
            - If there's NO better day in the 3-day window: propose an indoor variant (trainer, swimming, strength training) with an explicit mention of the weather reason.

            CRITICAL RULE — DOUBLE TRAINING & DAY PLANNING (anti-double-day):
            NEVER plan more than one workout per day. This is an absolute, hard constraint.
            Exceptions are only allowed if BOTH conditions are met:
              (a) the weekly TRIMP target is demonstrably unachievable with one session per day, AND
              (b) the second session is an active recovery block (TRIMP ≤ 30, Zone 1/walking only).

            CONFLICT RESOLUTION — when multiple workouts claim the same day:
            Follow this priority order strictly:
              1. Strength training has the highest priority; a competing endurance session is dropped or moved.
              2. If the endurance session represents a crucial milestone (e.g. the required 60 km ride for the cycling blueprint within 7 days), the strength training moves to the nearest free day.
              3. A rest day must never be converted into a training day just to absorb a moved workout — respect the rest days in the weekly pattern.
              4. If no free day is available: cancel the lower-priority workout entirely and compensate via the weekly volume on the remaining days (max. 10–15% more TRIMP per day).

            MANDATORY EXPLANATION on day conflicts:
            If you cancel or move a workout to avoid a double day, you MUST state this explicitly in the `motivation` field.
            Use this exact template: "I've cancelled / moved the planned [session name] from [day] to [new day], so you can put all your focus on [retained session]. [Optional: why that session had priority]."
            Example: "I've cancelled the planned recovery ride on Tuesday, so you can put all your focus on your strength training. Cycling returns to the schedule on Friday."

            CRITICAL CONSTRAINT — WALKING:
            Walking is allowed only as a recovery activity for injuries or a Vibe Score < 50.
            A walking session must NEVER be longer than 60 minutes. In the JSON always set suggestedDurationMinutes ≤ 60 for walks.

            Important context for your analysis:
            We compute a Banister TRIMP (Training Impulse) score locally to determine training load (not the traditional TSS that caps at 100/hour).
            - A TRIMP of 70-100 is a solid, demanding workout.
            - A TRIMP of 100-140 is a very hard workout, but on its own this is no sign of overtraining.

            IMPORTANT: As soon as you plan or analyse a schedule or status for the next 7 days, your answer MUST contain a JSON object (optionally in a code block) that matches this structure.
            `dateOrDay` MUST be either a weekday name (in \(replyLanguage)) or an ISO date "YYYY-MM-DD" computed from [CURRENT DATE] — never a relative term like "today"/"tomorrow", and add no extra words after the weekday. Structure:
            {
                "motivation": "Write an empathetic, descriptive analysis of at most 3 sentences here, in \(replyLanguage). Start with a DIRECT response to the user's latest message (name the specific activity). Then explain the WHY behind your strategic choices. If you make a change to the schedule, confirm it explicitly ('I've moved X to Y because...'). If you resolved a double day by cancelling or moving a workout, always state it: 'I've cancelled/moved [session] from [day] to [day], so you can put all your focus on [retained session].' Make the user feel the coach truly thinks along and truly listens.",
                "workouts": [
                    {
                        "dateOrDay": "Maandag",
                        "activityType": "Hardlopen",
                        "suggestedDurationMinutes": 45,
                        "targetTRIMP": 60,
                        "description": "Recovery after the long endurance run",
                        "heartRateZone": "Zone 2",
                        "targetPace": "5:30 min/km",
                        "reasoning": "Zone 2 recovery run to safeguard the aerobic base. TRIMP 60 = 75% of the weekly Build-phase target."
                    }
                ],
                "newPreferences": [
                    {
                        "text": "My knee is bothering me",
                        "expirationDate": "2024-05-20"
                    }
                ]
            }
            Extra instruction for `reasoning` (Sprint 17.3): For EVERY workout, fill the `reasoning` field with a short, factual explanation (max. 1 sentence) of why this workout is in the schedule. Base it on the phase, the success criteria and the goal. Write it in \(replyLanguage); e.g. (Dutch illustration): "60 km = longest-session requirement (60%) in the Build phase for your cycling goal." or "Zone 2 recovery run to safeguard the aerobic base." NEVER leave this field empty.

            Extra instruction for `newPreferences`: If you notice the user passing a fixed rule, long-term preference, or temporary ailment/injury in their LATEST message, add to this array. Estimate whether the fact is permanent (such as a fixed sport day) or temporary (such as muscle soreness, a minor injury or a cramp). If it's temporary, compute a logical expiration date (e.g. 1 or 2 weeks from today) and return it in the JSON under `expirationDate` as a "YYYY-MM-DD" string. Leave `expirationDate` empty (null) for permanent rules. The `text` field stays in the user's own words (in their language). Don't repeat rules you already know.
            """

            // Epic #53: provider-agnostic construction via the `AIModelFactory`.
            // Provider, model name AND key are provider-aware (sprint B). JSON
            // mode on: the coach response must always contain the plan JSON.
            // Timeout 45s: enough for a complex JSON-schema answer, but fast
            // enough to switch to the lite fallback on overload.
            // Epic 20 / M-04: BYOK-only; C-02: key comes from the Keychain.
            return AIModelFactory.makeModel(
                provider: provider,
                modelName: resolvedModelName,
                systemInstruction: systemInstruction,
                jsonMode: true,
                timeout: 45,
                apiKey: UserAPIKeyStore.read(for: provider)
            )
    }

    /// Builds a lighter fallback model with the same system instruction and
    /// timeout. Gets used invisibly as soon as the primary model returns an
    /// `internalError` (503/429 — peak load).
    ///
    /// Epic #35: the fallback model name is read from `AppStorage`; the
    /// built-in default remains `gemini-flash-lite-latest` — the same value
    /// as before Epic #35, so no regression for existing installations.
    private func buildFallbackGenerativeModel() -> GenerativeModelProtocol {
        return buildGenerativeModel(modelName: AIModelAppStorageKey.resolvedFallback(for: currentProvider))
    }

    /// Removes the selected image from the input.
    func clearImage() {
        self.selectedImage = nil
    }

    /// Fetches the currently stored plan and formats it as a string,
    /// so the AI can use it as reference material for post-workout evaluations.
    private func getStoredPlanString() -> String {
        guard let decodedPlan = try? JSONDecoder().decode(SuggestedTrainingPlan.self, from: latestSuggestedPlanData) else {
            return "No current planned schedule known."
        }

        var planString = "This is my currently planned schedule (always compare your advice against it):\n"
        for workout in decodedPlan.workouts {
            planString += "- \(workout.dateOrDay): \(workout.activityType) "
            if workout.suggestedDurationMinutes > 0 {
                planString += "(\(workout.suggestedDurationMinutes) min)"
            }
            if let trimp = workout.targetTRIMP {
                planString += " [Target TRIMP: \(trimp)]"
            }
            planString += "\n"
        }
        return planString
    }

    /// Generates a context-prefix string based on the given athletic profile.
    /// Epic #44 story 44.6: builds the `[TRAINING THRESHOLDS]` block based on the
    /// cached physiological profile. Returns an empty string if no thresholds are set
    /// — then the coach keeps using its own population assumptions. With a
    /// set LTHR we report Friel zones (more precise for an athletic profile),
    /// otherwise Karvonen on max+rest.
    private func buildTrainingThresholdsBlock() -> String {
        let profile = UserProfileService.cachedProfile()
        var lines: [String] = []
        if let max = profile.maxHeartRate {
            lines.append("- Max HR: \(Int(max.value)) BPM (\(thresholdSourceLabel(max.source)))")
        }
        if let rest = profile.restingHeartRate {
            lines.append("- Resting HR: \(Int(rest.value)) BPM (\(thresholdSourceLabel(rest.source)))")
        }
        if let lthr = profile.lactateThresholdHR {
            lines.append("- LTHR: \(Int(lthr.value)) BPM (\(thresholdSourceLabel(lthr.source)))")
        }
        if let ftp = profile.ftp {
            lines.append("- FTP: \(Int(ftp.value)) W (\(thresholdSourceLabel(ftp.source)))")
        }
        guard !lines.isEmpty else { return "" }

        // Add explicit Z2/Z3 boundaries so the coach does not
        // misinterpret a 'quiet' ride. Z2 endurance + Z3 tempo are the two zones
        // users reflect on most often.
        var zonesLine: String?
        if let zones = WorkoutPatternDetector.heartRateZones(from: profile),
           zones.count >= 3 {
            let z2 = zones[1]
            let z3 = zones[2]
            zonesLine = "- Zone 2 (endurance): \(z2.lowerBPM)-\(z2.upperBPM) BPM · Zone 3 (tempo): \(z3.lowerBPM)-\(z3.upperBPM) BPM"
        }

        var block = "[TRAINING THRESHOLDS (persoonlijk profiel):\n"
        block += lines.joined(separator: "\n")
        if let zonesLine {
            block += "\n\(zonesLine)"
        }
        block += """

        Behaviour rules:
        1. Always interpret "rustig"/"easy"/"recovery" in the context of THESE thresholds — not population averages. A user with max 200 BPM training at 146 BPM is in Z2, not Z3.
        2. On subjective feedback about exertion: tie it to the zone, not just the BPM number ("145 BPM is voor jou Z2 — dat klopt met 'rustig'").
        3. On plan adjustments where zones are explicitly named, use the BPM boundaries above for the instruction to the user.]
        """
        return block
    }

    private func thresholdSourceLabel(_ source: ThresholdSource) -> String {
        switch source {
        case .automatic: return "auto"
        case .manual:    return "handmatig"
        case .strava:    return "Strava"
        }
    }

    private func buildContextPrefix(from profile: AthleticProfile?, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) -> String {
        var prefix = ""

        let now = Date()
        let dateFormatter = AppDateFormatters.fixed("yyyy-MM-dd")
        prefix += "[CURRENT DATE: Today is \(dateFormatter.string(from: now)). Use this for your calculations around 'expirationDate'.]\n\n"

        // Epic 14.4: Inject the Vibe Score as hard context — the AI MUST follow this (see system instruction)
        if todayVibeScoreContext == VibeScoreContextFormatter.noVibeDataSentinel {
            // No Watch data available — give the coach an explicit instruction to communicate this correctly
            prefix += "[RECOVERY STATUS TODAY: No objective biometric data is available (the user probably didn't wear the Apple Watch overnight). Rely fully on the Symptom Tracker scores and the planned goals. NEVER use phrases like 'I can see from your HRV that...' or 'Your biometrics indicate...'. Instead say: 'Because we have no Watch data today, we'll go by your own feeling and the entered scores.']\n\n"
        } else if !todayVibeScoreContext.isEmpty {
            prefix += "[RECOVERY STATUS TODAY: \(todayVibeScoreContext) Follow the critical rule about Vibe Score authority strictly.]\n\n"
        }

        // Epic 18.1: Inject the subjective feedback (RPE + mood) of the last workout
        if !lastWorkoutFeedbackContext.isEmpty {
            prefix += "[SUBJECTIVE FEEDBACK LAST WORKOUT: \(lastWorkoutFeedbackContext) Watch for discrepancies: if TRIMP is low but RPE ≥8, this is an early sign of overtraining or oncoming illness.]\n\n"
        }

        // Story 33.2a: manually moved workouts — coach must respect this.
        if !userOverrideContext.isEmpty {
            prefix += userOverrideContext
        }

        // Story 33.4: intent-vs-execution analysis for the most recent workout.
        if !intentExecutionContext.isEmpty {
            prefix += intentExecutionContext
        }

        // Epic 18: Inject the current pain scores per body area (updated daily)
        if !symptomContext.isEmpty {
            let symptomBlock = """
            [CURRENT COMPLAINTS — SINGLE SOURCE OF TRUTH (updated daily by the user):
            \(symptomContext)
            Behaviour rules:
            1. 🚫 HARD CONSTRAINT present → follow the constraint strictly. Name the injury and the alternative explicitly.
            2. ✅ RECOVERED present → open your Insight with a celebratory confirmation. Propose a careful build-up (e.g. 'Begin met 20 min Zone 1, bouw volgende week op naar normaal volume').
            3. Score ≥7 → extra careful; consider a full rest day or an alternative sport.
            4. Score lower than yesterday → name this as a positive sign of recovery.]
            """
            prefix += symptomBlock + "\n\n"
        }

        // Epic #44 story 44.6: personal training thresholds to the coach. The
        // coach must know that 146 BPM is zone 2 for THIS user, not zone 3.
        // We only add the block if at least one threshold is set —
        // otherwise there is nothing more to say than population defaults and the
        // coach just keeps its own assumptions.
        let thresholdsBlock = buildTrainingThresholdsBlock()
        if !thresholdsBlock.isEmpty {
            prefix += thresholdsBlock + "\n\n"
        }

        // Epic 32 Story 32.3c: inject significant physiological patterns from
        // recent workouts. Only medium/significant patterns land in this
        // cache (see `WorkoutPatternFormatter.chatContextLine`); mild patterns
        // would make the prompt too busy.
        if !workoutPatternsContext.isEmpty {
            let patternsBlock = """
            [PHYSIOLOGICAL PATTERNS IN RECENT WORKOUTS:
            \(workoutPatternsContext)
            Behaviour rules:
            1. If the user asks about recent workouts, refer to these patterns where relevant — be concrete, not a list of technical terms.
            2. On significant cardiac drift + decoupling: ask whether it was deliberate threshold work, or whether external causes were at play (heat, sleep, stress).
            3. Slow HR recovery is a fatigue signal — combine with TRIMP and VibeScore before advising recovery.
            4. Do NOT mention these patterns unprompted in every turn; only when the user reflects on recent execution or asks about training-plan adjustments.]
            """
            prefix += patternsBlock + "\n\n"
        }

        // Epic 45 Story 45.2: richer per-workout context over the past 14 days.
        // Complement to the 1-line pulse above — that gives an aggregate signal,
        // this block gives the specific evidence per workout so plan adjustments
        // can refer to concrete sessions. Deliberately placed right after the patterns block
        // so the coach first reads the signal and then the details.
        if !workoutHistoryContext.isEmpty {
            let historyBlock = """
            [RECENT TRAINING — 14 DAYS (newest first):
            \(workoutHistoryContext)
            Behaviour rules:
            1. Refer specifically to date + session type on every workout reference ("op 18 april in je tempo-rit met cardiac drift 8% …"). No vague terms like "recent".
            2. On ≥3 consecutive workouts with aerobic_decoupling or cardiac_drift: propose sub-LTHR work and motivate it with the specific data from this list.
            3. Use this data only on reflection/schedule questions/goal analysis — don't recite it unprompted in every turn.
            4. Combine with [TRAINING THRESHOLDS] for zone-correct interpretation of the average HR. Use the same zone terminology ("Zone 2"/"Z2", "Zone 3"/"Z3", "LTHR") — don't invent new labels.
            5. Weigh this data against [CURRENT COMPLAINTS]. On an active injury: interpret patterns like cardiac_drift more cautiously (may be recovery fatigue, not a training need). Don't suggest volume increases if the user is recovering.]
            """
            prefix += historyBlock + "\n\n"
        }

        // Epic 21: Inject the 7-day weather forecast for outdoor-activities coaching
        if !weatherContext.isEmpty {
            let weatherBlock = """
            [WEATHER CONDITIONS NEXT 7 DAYS (user's location):
            \(weatherContext)
            Behaviour rules:
            1. DAY-SWAP STRATEGY: If a day with ⚠️ BAD OUTDOOR WEATHER has a key workout, look at the next 3 days. Is there a better day? Then EXPLICITLY swap days and state this in the `motivation` field.
            2. TRIMP PREPARATION: If the key workout moves to tomorrow or the day after, advise max. 40-50% TRIMP today as a 'charge day'. State this explicitly.
            3. Always be specific about percentages: not "het kan regenen" but "Zaterdag 72% neerslag → ik verplaats de 60 km naar zondag (5% neerslag, windstil)".
            4. Wind > 30 km/h = relevant for cycling. Always look for a less windy day if there is one.
            5. Temperature < 5°C or > 30°C → tip about clothing or hydration.
            6. You don't need to mention good weather unless it's a bonus ("Sunday looks ideal — perfect for your long ride").]
            """
            prefix += weatherBlock + "\n\n"
        }

        // Epic 17 / Sprint 17.2: Inject the blueprint + periodization context
        // and print the full content to the console for debugging.
        let hasBlueprintData  = !blueprintContext.isEmpty
        let hasPeriodization  = !periodizationContext.isEmpty

        if hasBlueprintData {
            prefix += "[SPORTS-SCIENCE REQUIREMENTS (BLUEPRINT):\n\(blueprintContext)\nInstruction: ALWAYS check whether the user is on schedule for their critical workouts. If there is an outstanding (❌) requirement with an approaching deadline, make this explicit in your advice and schedule that workout.]\n\n"
        }

        if hasPeriodization {
            prefix += "[PERIODIZATION — PHASE, SUCCESS CRITERIA & COACH BEHAVIOUR:\n\(periodizationContext)\n\nCoach behaviour rules for this context:\n1. COMPLIMENTS (🎉): If a COMPLIMENT TRIGGER is present, open your answer with it. Name the achievement.\n2. URGENCY (🚨): If a CRITICAL MILESTONE SHORTFALL is present, be direct and motivating. Name the exact distance or TRIMP still missing, and plan it as the first priority in the schedule.\n3. SCHEDULE ADJUSTMENT: If you adjust the schedule, always explain how the phase requirements are still achievable despite the change (SCHEDULE ACCOUNTABILITY).]\n\n"
        }

        // Epic Doel-Intenties: inject the intent and format instructions as a separate section.
        // This tells the coach HOW to train (cruising vs. performing, stage ride vs. one-day)
        // and whether stretch-pace trainings are safe based on the current VibeScore.
        if !intentContext.isEmpty {
            let intentBlock = """
            [GOAL INTENTS AND APPROACH — READ THIS BEFORE YOU BUILD THE SCHEDULE:
            \(intentContext)

            Binding coach rules:
            1. INTENT TAKES PRIORITY: ALWAYS adapt the schedule to the intent and the format. A 'finish/complete' goal NEVER gets interval or tempo training unless explicitly requested.
            2. BACK-TO-BACK (multi-day stage): Plan hard sessions on consecutive days (e.g. Sat+Sun). Lower the single-session peak load compared to a one-day race.
            3. STRETCH GOAL SAFETY: If '✅ DOELTIJD' is present, plan one tempo session per week at target pace. If '🔴 DOELTIJD' is present, drop all tempo elements and return to pure endurance training.
            4. VIBE SCORE OVERRIDE: If a VibeScore < 65 is mentioned, recovery has absolute priority — drop intensive elements regardless of the rest of the plan.]
            """
            prefix += intentBlock + "\n\n"
        }

        // Epic #55 story 55.3: multi-day event window — the event days ARE the training;
        // suppress other sessions + fixed preferences in the window and plan recovery after.
        if !eventWindowContext.isEmpty {
            prefix += eventWindowContext + "\n\n"
        }

        // Epic 23 Sprint 1: Inject the gap analysis with TRIMPTranslator hints
        if !gapAnalysisContext.isEmpty {
            let gapBlock = """
            [GAP ANALYSIS — BLUEPRINT VS. REALITY (Epic 23):
            \(gapAnalysisContext)
            Coach behaviour rules:
            1. TRIMP TRANSLATION (MANDATORY): If there is a 📈 VOLUME ADJUSTMENT with an "X TRIMP ≈ +Y min …" hint, ALWAYS use that translation. NEVER state a bare TRIMP number without the accompanying time indication. Correct: "This week you need about 8 TRIMP extra — that's roughly +4 minutes on your Saturday ride." Wrong: "You're 8 TRIMP short."
            2. TIE TO THE SCHEDULE: Always translate the adjustment into a change to an existing training day. E.g. "Extend your Tuesday endurance run by 5 minutes" or "Ride 10 minutes longer on Saturday along the familiar route."
            3. If there is a 🚴 KM-BIJSTURING: give a concrete weekly schedule with extra km per workout, not as an abstract total.
            4. If the athlete is ahead of schedule: compliment briefly and advise consistency — don't prescribe extra volume.
            5. Always tie it to the phase: adjusting in the Taper phase is undesirable — then advise NOT to make up the deficit but to continue with the tapering schedule.]
            """
            prefix += gapBlock + "\n\n"
        }

        // Epic 23 Sprint 2: Inject the future projection (Future Projection Engine)
        if !projectionContext.isEmpty {
            prefix += "\(projectionContext)\n\n"
        }

        // Epic 24 Sprint 1: Inject the physiological profile + nutrition plan into the prompt
        if !nutritionContext.isEmpty {
            prefix += "\(nutritionContext)\n\n"
        }

        // Epic 24 Sprint 3: One-time profile-change notice — inject only once,
        // then clear so the coach does not repeat it every time.
        if !profileUpdateNote.isEmpty {
            prefix += "\(profileUpdateNote)\n\n"
            profileUpdateNote = ""
        }

        // Debug: blueprint/periodization context is PHI — log only at .debug
        // level with .private redaction (stripped in release).
        if hasBlueprintData {
            AppLoggers.coach.debug("Blueprint context → coach: \(self.blueprintContext, privacy: .private)")
        }
        if hasPeriodization {
            AppLoggers.coach.debug("Periodization context → coach: \(self.periodizationContext, privacy: .private)")
        }

        // Epic 16: Inject the training phase per active goal — the AI MUST follow the phase instructions strictly
        let activeGoalsWithPhase = activeGoals.compactMap { goal -> (FitnessGoal, TrainingPhase)? in
            guard let phase = goal.currentPhase else { return nil }
            return (goal, phase)
        }
        if !activeGoalsWithPhase.isEmpty {
            prefix += "[PERIODIZATION — ACTIVE TRAINING PHASES:\n"
            for (goal, phase) in activeGoalsWithPhase {
                let weeksLeft = goal.weeksRemaining(from: now)
                let weeksLeftStr = String(format: "%.1f", weeksLeft)
                // Compute the phase-corrected weekly target (linear baseline × multiplier)
                let linearRate = goal.computedTargetTRIMP / max(0.1, weeksLeft)
                let adjustedTarget = Int((linearRate * phase.multiplier).rounded())
                prefix += "• Goal '\(goal.title)' (\(weeksLeftStr) weeks remaining): \(phase.aiInstruction)\n"
                prefix += "  Mathematically adjusted weekly TRIMP target: \(adjustedTarget) TRIMP/week (multiplier: ×\(String(format: "%.2f", phase.multiplier))). Adhere strictly to this target.\n"
            }
            prefix += "]\n\n"
        }

        // Split preferences into pinned (without end date) vs. temporary (with end date) and
        // inject them as two separate blocks — a temporary preference must explicitly take precedence over
        // a conflicting pinned rule during its lifetime. Filtering of
        // expired items + format logic lives in `PreferencesContextFormatter` (testable).
        prefix += PreferencesContextFormatter.format(activePreferences: activePreferences, now: now)

        // Epic 18: Injury context is fully handled via symptomContext (see top of buildContextPrefix).
        // The old static block based on UserPreference texts has been replaced by the dynamic
        // pain scores + HARD CONSTRAINTS generated in cacheSymptomContext(_:preferences:).

        if let p = profile {
            let peakDistanceKm = String(format: "%.1f", p.peakDistanceInMeters / 1000)
            let peakDurationMin = p.peakDurationInSeconds / 60
            let weeklyVolumeMin = p.averageWeeklyVolumeInSeconds / 60

            prefix += "[ATHLETE CONTEXT: Has a peak performance of \(peakDistanceKm) km in \(peakDurationMin) minutes. Trains on average \(weeklyVolumeMin) minutes per week (avg. last 4 weeks), and last trained \(p.daysSinceLastTraining) days ago."

            // SPRINT 6.3: Overtraining warning
            if p.isRecoveryNeeded {
                prefix += " URGENT: The athlete shows signs of overtraining based on recent volume. Be strict, actively advise taking rest, and analyse this workout purely for recovery."
            }

            // SPRINT 9.3: Pace Baseline Injection
            if let avgPaceInSeconds = p.averagePacePerKmInSeconds {
                let minutes = avgPaceInSeconds / 60
                let seconds = avgPaceInSeconds % 60
                let paceString = String(format: "%d:%02d", minutes, seconds)
                prefix += " Important physiological context: The user's current average running pace is around \(paceString) min/km (top of Zone 2). Use this as the absolute baseline to compute realistic 'targetPace' goals for the upcoming workouts."
            }

            prefix += " Take this into account in your analysis about recovery and performance.]\n\n"
        }

        guard !prefix.isEmpty else { return "" }
        prefix += "[QUESTION]: "
        return prefix
    }

    // MARK: - Sprint 13.3: Proactive Intervention

    /// Struct with the risk data per goal, separate from DashboardView so ChatViewModel
    /// has no dependency on the view layer.
    struct GoalRiskInfo {
        let title: String
        let currentWeeklyRate: Double
        let requiredWeeklyRate: Double
        let weeksRemaining: Double
    }

    /// Asks the AI for a concrete recovery plan for goals that are behind.
    /// Automatically injects the recovery context (goal, current rate, deficit, weeks remaining)
    /// so the coach can directly produce an adjusted plan.
    func requestRecoveryPlan(atRiskGoals: [GoalRiskInfo], contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        guard !atRiskGoals.isEmpty else { return }

        // Build the technical context (invisible to the user)
        var systemLines = [
            "RECOVERY CONTEXT — My goal(s) are behind schedule. Create a gradual recovery plan:",
            ""
        ]

        // Epic 14.4: Inject the Vibe Score so the recovery plan respects the current recovery status
        if todayVibeScoreContext == VibeScoreContextFormatter.noVibeDataSentinel {
            systemLines.append("RECOVERY STATUS TODAY: No Watch data available. Base the recovery plan on the Symptom Tracker scores and the user's own feeling.")
            systemLines.append("")
        } else if !todayVibeScoreContext.isEmpty {
            systemLines.append("RECOVERY STATUS TODAY: \(todayVibeScoreContext) Adjust the intensity of the recovery plan STRICTLY to this score (see system instruction).")
            systemLines.append("")
        }
        for risk in atRiskGoals {
            let deficit = Int(risk.requiredWeeklyRate - risk.currentWeeklyRate)
            let weeksText = String(format: "%.1f", risk.weeksRemaining)
            let currentRate = Int(risk.currentWeeklyRate)

            // Determine the horizon strategy based on weeks remaining
            let horizonAdvice: String
            if risk.weeksRemaining > 8 {
                // Plenty of time left: give Base Building advice, spread the deficit gradually
                let gradualWeeklyIncrease = Int(Double(deficit) / max(risk.weeksRemaining * 0.5, 1))
                horizonAdvice = "The event is \(weeksText) weeks away. PRIORITY: Base Building. Increase the weekly volume very gradually — aim for +\(gradualWeeklyIncrease) TRIMP/week over the coming months. No panic workouts."
            } else if risk.weeksRemaining > 4 {
                horizonAdvice = "The event is \(weeksText) weeks away. Increase the volume in a controlled way, but don't build full peak load yet."
            } else {
                horizonAdvice = "The event is \(weeksText) weeks away. Focus on efficient, high-quality workouts — no more drastic volume increases."
            }

            systemLines.append("• Goal: '\(risk.title)'")
            systemLines.append("  - Current burn rate: \(currentRate) TRIMP/week")
            systemLines.append("  - Required burn rate (ideal): \(Int(risk.requiredWeeklyRate)) TRIMP/week")
            systemLines.append("  - Weekly deficit: \(deficit) TRIMP")
            systemLines.append("  - Weeks remaining: \(weeksText)")
            systemLines.append("  - Horizon advice: \(horizonAdvice)")
            systemLines.append("")

            // Compute the maximum allowed weekly volume (10-15% rule)
            let maxAllowedRate = Int(Double(currentRate) * 1.12) // 12% = middle of 10-15%
            systemLines.append("  ⛔️ HARD PHYSIOLOGICAL LIMIT: The total weekly TRIMP for the coming week must NEVER exceed \(maxAllowedRate) TRIMP (\(currentRate) × 1.12). This is the 10-15% progression rule to prevent overtraining. This is non-negotiable.")
            systemLines.append("")
        }
        systemLines.append(contentsOf: [
            "Give me a concrete, achievable recovery plan for the next 7 days.",
            "The plan must:",
            "1. Strictly respect the 10-15% progression rule — rather slightly too conservative than too aggressive.",
            "2. Spread the deficit over multiple weeks if the event is far away (see horizon advice above).",
            "3. Distribute extra volume via frequency (turn an extra rest day into a light session) instead of one mega session.",
            "4. Always return the full 7-day schedule in JSON format.",
            "",
            "⛔️ EXTRA INTENSITY LIMITS (non-negotiable):",
            "- Indoor sessions (indoor cycling, rowing, swimming) must NEVER be longer than 60 minutes, unless the goal explicitly requires an endurance session of >90 min.",
            "- No single session may be more than 40% higher in TRIMP than the average of the past 7 days. Preventing extreme spikes is a priority."
        ])

        let systemPrompt = systemLines.joined(separator: "\n")

        // The text the user sees in the chat (concise and understandable)
        let goalTitles = atRiskGoals.map { "'\($0.title)'" }.joined(separator: " en ")
        let userFacingText = String(localized: "Los de achterstand op voor \(goalTitles) en geef me een bijgestuurd schema.")

        sendHiddenSystemMessage(
            systemText: systemPrompt,
            userText: userFacingText,
            fallbackMessage: String(localized: "Ik heb je herstelplan klaar! Bekijk je overzicht — het schema is bijgewerkt om je weer op schema te brengen."),
            contextProfile: contextProfile,
            activeGoals: activeGoals,
            activePreferences: activePreferences
        )
    }

    /// Handles rejecting (skipping) a specific suggested workout (Rest Day).
    func skipWorkout(_ workout: SuggestedWorkout, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        let systemPrompt = "The user is skipping the workout '\(workout.activityType)' on \(workout.dateOrDay). Recompute the week and shift the load forward. IMPORTANT: In your JSON output always return the full 7-day schedule (including all unchanged other days), not just the adjusted day."
        let userFacingText = String(localized: "Ik sla de geplande \(workout.activityType) op \(workout.dateOrDay) over.")
        sendHiddenSystemMessage(systemText: systemPrompt, userText: userFacingText, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
    }

    /// Handles the request for an alternative workout.
    func requestAlternativeWorkout(_ workout: SuggestedWorkout, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        let systemPrompt = "The user doesn't like the planned workout '\(workout.activityType)' on \(workout.dateOrDay). Give an alternative for \(workout.dateOrDay) that provides a comparable training stimulus. IMPORTANT: In your JSON output always return the full 7-day schedule (including all unchanged other days), not just the adjusted day."
        let userFacingText = "Geef me een alternatief voor de \(workout.activityType) op \(workout.dateOrDay)."
        sendHiddenSystemMessage(systemText: systemPrompt, userText: userFacingText, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
    }

    /// Sends a message where the UI shows a simple text, but the payload contains the technical prompt.
    /// If JSON parsing fails, `fallbackMessage` is shown instead of the raw AI text —
    /// so that on recovery plan / skip-workout calls raw JSON never appears in the chat.
    private func sendHiddenSystemMessage(
        systemText: String,
        userText: String,
        fallbackMessage: String = String(localized: "Ik heb je schema bijgewerkt! Bekijk je overzicht voor het nieuwe plan."),
        contextProfile: AthleticProfile? = nil,
        activeGoals: [FitnessGoal] = [],
        activePreferences: [UserPreference] = []
    ) {
        messages.append(ChatMessage(role: .user, text: userText))
        isTyping = true

        let contextPrefix = buildContextPrefix(from: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
        let payloadText = "\(contextPrefix)\(systemText)"

        fetchAIResponse(for: payloadText, image: nil, fallbackMessage: fallbackMessage)
    }

    /// Sends the current text field (or the given text) and/or the selected image.
    func sendMessage(_ explicitText: String? = nil, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        let textToUse = explicitText ?? inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        let imageToSend = selectedImage?.downsample(to: 2048.0)

        guard !textToUse.isEmpty || imageToSend != nil else { return }
        // Prevent the user from sending a new message while the coach is still typing.
        guard !isTyping else { return }

        // 1. Create message from user for the UI (WITHOUT the invisible context prefix)
        let imageData = imageToSend?.jpegData(compressionQuality: 0.8)
        let uiMessage = ChatMessage(role: .user, text: textToUse, attachedImageData: imageData)
        messages.append(uiMessage)

        isTyping = true
        inputText = ""
        clearImage()

        // 2. Build the final payload prompt
        let contextPrefix = buildContextPrefix(from: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)

        // Combine explicitly injected goals into user text if applicable for plain chat
        var finalUserText = textToUse
        let uncompletedGoals = activeGoals.filter { !$0.isCompleted }
        if !uncompletedGoals.isEmpty && textToUse != "" {
            let goalsString = uncompletedGoals.map { goal in
                let formatter = AppDateFormatters.promptStyle(.medium)
                return "\(goal.title) voor \(formatter.string(from: goal.targetDate))"
            }.joined(separator: ", ")

            finalUserText = "[DOELEN: \(goalsString)]\n" + finalUserText
        }

        let payloadText = finalUserText.isEmpty ? contextPrefix : "\(contextPrefix)\(finalUserText)"

        // 3. Fetch AI response with the enriched payload
        fetchAIResponse(for: payloadText, image: imageToSend)
    }

    /// Removes the last error message and resends the last user message.
    /// Gets called via the 'Probeer opnieuw' button in the MessageBubble.
    func retryLastMessage(contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        // Remove the last error message from the chat
        if let lastErrorIndex = messages.indices.last(where: { messages[$0].isError }) {
            messages.remove(at: lastErrorIndex)
        }

        // Find the last user message to resend
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else { return }

        // Also remove the user message itself so sendMessage() re-adds it cleanly
        if let lastUserIndex = messages.indices.last(where: { messages[$0].role == .user }) {
            messages.remove(at: lastUserIndex)
        }

        // Resend — sendMessage re-adds the message and calls the AI
        sendMessage(lastUserMessage.text, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
    }

    /// Generates a text prompt for the Gemini AI based on the physiological data from HealthKit.
    struct DailyWorkout {
        let date: Date
        let name: String
        let durationMinutes: Int
        let trimp: Int
    }

    private func generateCurrentStatusPrompt(workouts: [DailyWorkout], days: Int, activeGoals: [FitnessGoal]) -> String {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        let storedPlanContext = getStoredPlanString()

        var lines: [String] = [storedPlanContext, "\nThese are my most recent completed workouts (including rest days):"]

        // Inject Goals explicitly
        let uncompletedGoals = activeGoals.filter { !$0.isCompleted }
        if uncompletedGoals.isEmpty {
            lines.append("- My saved goals: No specific goals.")
        } else {
            let goalsString = uncompletedGoals.map { goal in
                let formatter = AppDateFormatters.promptStyle(.medium)
                let dateStr = formatter.string(from: goal.targetDate)
                let sport = goal.sportCategory?.displayName ?? "Sport"
                return "\(goal.title) (\(sport)) for \(dateStr)"
            }.joined(separator: ", ")
            lines.append("- My saved goals: \(goalsString)")
        }

        lines.append("- My load (past \(days) days):")
        var totalTrimp = 0

        var workoutsByDay: [Int: [DailyWorkout]] = [:]

        for workout in workouts {
            let startOfWorkoutDay = calendar.startOfDay(for: workout.date)
            let components = calendar.dateComponents([.day], from: startOfWorkoutDay, to: startOfToday)
            let dayOffset = components.day ?? 0

            if dayOffset < days && dayOffset >= 0 {
                if workoutsByDay[dayOffset] == nil {
                    workoutsByDay[dayOffset] = []
                }
                workoutsByDay[dayOffset]?.append(workout)
                totalTrimp += workout.trimp
            }
        }

        var emptyDaysStreak: [Int] = []

        for dayOffset in 0..<days {
            let displayDay = days - dayOffset

            if let dailyWorkouts = workoutsByDay[dayOffset], !dailyWorkouts.isEmpty {
                if !emptyDaysStreak.isEmpty {
                    if emptyDaysStreak.count == 1 {
                        lines.append("- Day \(emptyDaysStreak[0]): Rest")
                    } else {
                        lines.append("- Day \(emptyDaysStreak.first!) to \(emptyDaysStreak.last!): Rest")
                    }
                    emptyDaysStreak.removeAll()
                }

                var dayName = "Day \(displayDay)"
                if dayOffset == 0 {
                    dayName += " (Today)"
                } else if dayOffset == 1 {
                    dayName += " (Yesterday)"
                }

                for workout in dailyWorkouts {
                    // L-1: the workout name is external free text (Strava/HK) — sanitize
                    // before it enters the prompt (prompt-injection defense-in-depth).
                    let safeName = PromptInputSanitizer.sanitizeExternalText(workout.name)
                    lines.append("- \(dayName): \(workout.durationMinutes) min \(safeName) (TRIMP: \(workout.trimp))")
                }
            } else {
                emptyDaysStreak.append(displayDay)
            }
        }

        if !emptyDaysStreak.isEmpty {
            if emptyDaysStreak.count == 1 {
                lines.append("- Day \(emptyDaysStreak[0]): Rest")
            } else {
                lines.append("- Day \(emptyDaysStreak.first!) to \(emptyDaysStreak.last!): Rest")
            }
        }

        lines.append("Total Cumulative TRIMP: \(totalTrimp)")

        lines.append("\nInstruction for the Coach:")

        let dateString = now.formatted(date: .complete, time: .omitted)
        lines.append("NOTE: Today is \(dateString). The new 7-day schedule MUST start from today. Remove days in the past and fill out the week.")
        lines.append("CRITICAL: ALWAYS sort the workouts in the JSON array chronologically — day 1 (today) first, day 7 (6 days out) last. Never reversed, never random.")
        lines.append("Compare these recent activities with the current schedule above. Is the remaining schedule for this week still optimal and realistic? If not, recompute the schedule (always return all 7 days) and give a short motivation or feedback on my recent workouts.")

        return lines.joined(separator: "\n")
    }

    /// Fetches the status via the selected source for the past X days.
    /// Falls back to the other source on lack of data or permissions.
    func analyzeCurrentStatus(days: Int = 7, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        guard !isFetchingWorkout else { return }
        isFetchingWorkout = true

        Task {
            // SPRINT 7.4 - Check selected data source
            if selectedDataSource == .healthKit {
                do {
                    let workouts = try await healthKitManager.fetchRecentWorkouts(days: days)
                    if !workouts.isEmpty {
                        var dailyWorkouts: [DailyWorkout] = []
                        for workout in workouts {
                            let durationInMinutes = Int(workout.duration / 60.0)
                            let calculatedTSS = fitnessCalculator.calculateTSS(durationInSeconds: workout.duration, averageHeartRate: workout.averageHeartRate, maxHeartRate: workout.maxHeartRate, restingHeartRate: workout.restingHeartRate)
                            let trimpInt = Int(calculatedTSS)

                            dailyWorkouts.append(DailyWorkout(date: workout.startDate, name: workout.name, durationMinutes: durationInMinutes, trimp: trimpInt))
                        }

                        let uiPrompt = generateCurrentStatusPrompt(workouts: dailyWorkouts, days: days, activeGoals: activeGoals)
                        await sendPromptToAI(uiPrompt: uiPrompt, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
                        return
                    }
                    AppLoggers.coach.notice("No or empty HealthKit workouts found, falling back to Strava.")
                } catch {
                    AppLoggers.coach.warning("Error fetching HealthKit data (\(error.localizedDescription, privacy: .public)), falling back to Strava.")
                }

                // Fallback to Strava
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)

            } else {
                // Strava selected
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
            }
        }
    }

    /// Helper function for the AI prompt injection (without showing the payload in the UI).
    private func sendPromptToAI(uiPrompt: String, contextProfile: AthleticProfile?, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) async {
        await MainActor.run {
            // Note: We do NOT add uiPrompt (the raw JSON context) to messages.
            // Optionally add a friendly system indication for the UI if it was a manual refresh,
            // or leave the UI empty and only show the loading (isTyping).
            // For now we keep it simple and invisible.
            isTyping = true
            isFetchingWorkout = false

            let contextPrefix = buildContextPrefix(from: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
            let payloadText = "\(contextPrefix)\(uiPrompt)"
            fetchAIResponse(for: payloadText, image: nil)
        }
    }

    /// Helper function for fetching via HealthKit, with optional fallback.
    private func fetchHealthKitRecentWorkouts(days: Int, contextProfile: AthleticProfile?, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = [], isFallback: Bool = false) async {
        do {
            let workouts = try await healthKitManager.fetchRecentWorkouts(days: days)
            if !workouts.isEmpty {
                var dailyWorkouts: [DailyWorkout] = []
                for workout in workouts {
                    let durationInMinutes = Int(workout.duration / 60.0)
                    let calculatedTSS = fitnessCalculator.calculateTSS(durationInSeconds: workout.duration, averageHeartRate: workout.averageHeartRate, maxHeartRate: workout.maxHeartRate, restingHeartRate: workout.restingHeartRate)
                    let trimpInt = Int(calculatedTSS)

                    dailyWorkouts.append(DailyWorkout(date: workout.startDate, name: workout.name, durationMinutes: durationInMinutes, trimp: trimpInt))
                }

                let uiPrompt = generateCurrentStatusPrompt(workouts: dailyWorkouts, days: days, activeGoals: activeGoals)
                await sendPromptToAI(uiPrompt: uiPrompt, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
                return
            }

            if !isFallback {
                AppLoggers.coach.notice("No or empty HealthKit workouts found, falling back to Strava.")
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
            } else {
                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: String(localized: "Ik kon geen recente trainingen vinden in HealthKit of je Strava account.")))
                    isFetchingWorkout = false
                }
            }
        } catch {
            if !isFallback {
                AppLoggers.coach.warning("Error fetching HealthKit data (\(error.localizedDescription, privacy: .public)), falling back to Strava.")
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
            } else {
                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: String(localized: "Ik kon geen recente trainingen vinden. HealthKit fout: \(error.localizedDescription)")))
                    isFetchingWorkout = false
                }
            }
        }
    }

    /// Helper function for fetching via Strava, including fallback to HealthKit.
    private func fetchStravaRecentActivities(days: Int, contextProfile: AthleticProfile?, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = [], isFallback: Bool = false) async {
        do {
            let activities = try await fitnessDataService.fetchRecentActivities(days: days)

            if activities.isEmpty {
                if !isFallback && selectedDataSource == .strava {
                    // Reverse Fallback: If Strava fails or is empty and Strava was the source, try HealthKit
                    AppLoggers.coach.notice("No recent Strava activity found. Reverse fallback to HealthKit.")
                    await fetchHealthKitRecentWorkouts(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
                    return
                }

                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: String(localized: "Ik kon geen recente trainingen vinden in HealthKit of je Strava account.")))
                    isFetchingWorkout = false
                }
                return
            }

            let formatter = ISO8601DateFormatter()
            var dailyWorkouts: [DailyWorkout] = []

            for activity in activities {
                let date = formatter.date(from: activity.start_date) ?? Date()
                let durationMinutes = activity.moving_time / 60

                // Estimate resting heart rate and max heart rate if these are not available via Strava,
                // or we can use a simple fallback.
                // In a real app we would get this from the profile or take a default.
                let avgHR = activity.average_heartrate ?? 140.0
                let calculatedTSS = fitnessCalculator.calculateTSS(durationInSeconds: Double(activity.moving_time), averageHeartRate: avgHR, maxHeartRate: 190.0, restingHeartRate: 60.0)

                dailyWorkouts.append(DailyWorkout(date: date, name: activity.name, durationMinutes: durationMinutes, trimp: Int(calculatedTSS)))
            }

            let uiPrompt = generateCurrentStatusPrompt(workouts: dailyWorkouts, days: days, activeGoals: activeGoals)

            await sendPromptToAI(uiPrompt: uiPrompt, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)

        } catch let error as FitnessDataError {
            if !isFallback && selectedDataSource == .strava {
                AppLoggers.coach.warning("Strava API error (\(error.localizedDescription, privacy: .public)). Reverse fallback to HealthKit.")
                await fetchHealthKitRecentWorkouts(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
                return
            }

            var errorMsg = String(localized: "Fout bij ophalen van data: ")
            switch error {
            case .missingToken: errorMsg += String(localized: "Je bent niet ingelogd op Strava. Ga naar instellingen om te koppelen.")
            case .unauthorized: errorMsg += String(localized: "Je Strava sessie is verlopen. Koppel opnieuw in de instellingen.")
            case .rateLimited(let retryAfter):
                let f = AppDateFormatters.display("HH:mm")
                errorMsg += String(localized: "Strava-limiet bereikt — hervat om \(f.string(from: retryAfter)).")
            case .networkError(let desc): errorMsg += String(localized: "Netwerkfout (\(desc)).")
            case .decodingError(let desc): errorMsg += String(localized: "Data onleesbaar (\(desc)).")
            case .invalidResponse: errorMsg += String(localized: "Ongeldig antwoord van de server.")
            }
            await MainActor.run {
                messages.append(ChatMessage(role: .ai, text: errorMsg))
                isFetchingWorkout = false
            }
        } catch {
            if !isFallback && selectedDataSource == .strava {
                await fetchHealthKitRecentWorkouts(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
                return
            }

            await MainActor.run {
                messages.append(ChatMessage(role: .ai, text: "Er is een onbekende fout opgetreden."))
                isFetchingWorkout = false
            }
        }
    }

    // MARK: - JSON Parsing Helpers

    /// Fetches a clean JSON string from an AI response that may contain markdown formatting.
    ///
    /// Strategy (in order):
    /// 1. Strip markdown code block tags (```json, ```JSON, ```) at the beginning and end.
    /// 2. Extract the first balanced top-level `{ ... }` object: scan from the first `{`
    ///    while tracking string context (so braces inside string values don't count) and
    ///    brace depth, then stop at the matching `}`. This discards any trailing junk —
    ///    most importantly a duplicated closing brace (`}}`), which the model occasionally
    ///    emits and which `JSONDecoder` rejects as malformed.
    /// 3. Trim whitespace.
    ///
    /// `static` + internal so the brace-balancing logic is unit-testable without a
    /// ChatViewModel instance (CLAUDE.md §6).
    static func extractCleanJSON(from rawText: String) -> String {
        var text = rawText

        // Step 1: Strip markdown code block opening tag (```json or ```)
        // Use case-insensitive search so ```JSON also works
        if let startRange = text.range(of: "```json", options: .caseInsensitive) {
            text = String(text[startRange.upperBound...])
        } else if let startRange = text.range(of: "```") {
            text = String(text[startRange.upperBound...])
        }

        // Strip closing ``` (search from back to front)
        if let endRange = text.range(of: "```", options: .backwards) {
            text = String(text[..<endRange.lowerBound])
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 2: Extract the first balanced { ... } object. String-aware so a `{`/`}`
        // inside a description/reasoning value doesn't throw off the depth count, and
        // escape-aware so an escaped quote (\") inside a string isn't treated as the
        // string terminator.
        guard let start = text.firstIndex(of: "{") else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var depth = 0
        var inString = false
        var escaped = false
        var idx = start
        var balancedEnd: String.Index?
        while idx < text.endIndex {
            let ch = text[idx]
            if escaped {
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        balancedEnd = idx
                        break
                    }
                }
            }
            idx = text.index(after: idx)
        }

        if let balancedEnd {
            // Found a complete object — drop anything after the matching brace.
            text = String(text[start...balancedEnd])
        } else if !text.hasPrefix("{") {
            // Unbalanced (e.g. a truncated response) and there was leading prose:
            // fall back to the old first-{ … last-} slice so we still attempt a parse.
            if let lastBrace = text.lastIndex(of: "}") {
                text = String(text[start...lastBrace])
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sends the request asynchronously to the AI model with the correct content payload.
    ///
    /// - Parameters:
    ///   - text: The text entered by the user.
    ///   - image: An optional UIImage.
    ///   - fallbackMessage: Optional. If JSON parsing fails (e.g. on hidden system calls),
    ///     this message is shown instead of the raw AI text. Use this for
    ///     recovery plan requests, skip workout, etc. to prevent JSON from becoming visible in the chat.
    func fetchAIResponse(for text: String, image: UIImage?, fallbackMessage: String? = nil) {
        // To ensure the unit tests (which mock the protocol) do not fail on the check
        // of the missing API key (because the static Secrets placeholder is often active in CI),
        // we ignore the check if a custom model is injected for testing, or log the warning.
        // Epic 20: BYOK — block if no valid API key is configured.
        // Exception: if a custom model (e.g. a mock for unit tests) is injected,
        // we skip the key check so tests do not fail on a missing key.
        if model is RealAIProviderClient {
            guard hasAPIKey else {
                let noKeyMessage = "Je AI Coach slaapt. Voer een API-sleutel in via de Instellingen om hem wakker te maken."
                messages.append(ChatMessage(role: .ai, text: noKeyMessage))
                lastAIErrorMessage = noKeyMessage
                return
            }
        }

        // Clear any previous error banner as soon as a new call starts.
        lastAIErrorMessage = nil

        // Epic #51-A2: snapshot the model names we are going to use for THIS
        // call so the UI can show the banner if the user switches model during
        // isTyping. We read the keys here — not via a
        // @AppStorage property — to explicitly snapshot once per call.
        activeRequestPrimaryModel = AIModelAppStorageKey.resolvedPrimary(for: currentProvider)
        activeRequestFallbackModel = AIModelAppStorageKey.resolvedFallback(for: currentProvider)

        // Epic #51-A6: clean up the previous Task neatly should the user send a
        // new question before the previous one is back (defensive — the UI
        // disables the send button during isTyping, but this guard prevents
        // a race condition from leading to duplicate responses).
        currentRequestTask?.cancel()

        currentRequestTask = Task { [weak self] in
            guard let self = self else { return }
            // Create a dynamic array of ModelContent.Part objects
            var promptParts: [AIPromptPart] = []

            if !text.isEmpty {
                promptParts.append(.text(text))
            }

            // Convert the UIImage to JPEG data and wrap it in a provider-neutral part
            if let image = image, let imageData = image.jpegData(compressionQuality: 0.8) {
                promptParts.append(.imageData(imageData, mimeType: "image/jpeg"))
            }

            // M-1: the assembled prompt is the entire PHI corpus — never log its
            // content. Log only a non-identifying length signal for debugging.
            AppLoggers.coach.debug("Prompt assembled (\(text.count, privacy: .public) chars)")

            // Waterfall: primary model first. On 503/429 (overload) we silently
            // switch to the fallback model — lighter by default, more often available
            // during peaks. Both model names are configurable in
            // Settings → AI Coach Configuratie from Epic #35. Other errors (invalid key, prompt
            // blocked, network) fall straight through to the UI.
            var responseText: String?
            var finalError: Error?

            do {
                responseText = try await model.generateContent(promptParts)
            } catch {
                // Epic #53: provider-agnostic overload detection (Gemini
                // `internalError` AND our own `AIProviderError.overloaded`). On
                // a temporary 503/429 we silently switch to the fallback
                // model; other errors (invalid key, blocked, network) fall
                // straight through to the UI.
                if AIProviderError.isOverload(error) {
                    retryStatusMessage = String(localized: "Model tijdelijk overbelast — overschakelen naar lichtere variant...")
                    let fallbackModel = buildFallbackGenerativeModel()
                    do {
                        responseText = try await fallbackModel.generateContent(promptParts)
                    } catch {
                        finalError = error
                    }
                } else {
                    finalError = error
                }
            }

            // Reset retry status message
            retryStatusMessage = ""

            // Epic #51-A6: if the Task has been cancelled in the meantime (user
            // left the Coach tab or sent a new question before this one was
            // back), we do NOT want to show an error bubble or banner. We
            // only reset the typing state and leave the chat clean.
            if Task.isCancelled || finalError is CancellationError {
                self.isTyping = false
                self.currentRequestTask = nil
                self.activeRequestPrimaryModel = ""
                self.activeRequestFallbackModel = ""
                return
            }

            // Handle error if all attempts have failed.
            // Epic #51-A5: specific messages per error category (offline /
            // timeout / DNS / safety-block / invalid key / overloaded / generic)
            // via the pure-Swift `ChatErrorMessageMapper`. The old case statement
            // only recognized Gemini SDK types and translated the rest into one
            // generic "tijdelijk probleem", so offline situations and
            // revoked keys could not be told apart.
            if let error = finalError {
                let userFacingMessage = ChatErrorMessageMapper.userFacingMessage(for: error)
                messages.append(ChatMessage(role: .ai, text: userFacingMessage, isError: true))
                // Mirror the error message in the banner state so screens without
                // a visible chat (such as Dashboard during pull-to-refresh) ALSO show feedback.
                lastAIErrorMessage = userFacingMessage
                isTyping = false
                self.currentRequestTask = nil
                self.activeRequestPrimaryModel = ""
                self.activeRequestFallbackModel = ""
                return
            }

            // Handle the successful response. M-1: the raw model response can echo
            // PHI — log only a non-identifying length signal, never the content.
            AppLoggers.coach.debug("Raw model response received (\(responseText?.count ?? 0, privacy: .public) chars)")

            // Use the robust JSON extractor: strip markdown and pull out the JSON object
            let cleanedJSON = Self.extractCleanJSON(from: responseText ?? "{}")

            var parsedPlan: SuggestedTrainingPlan?
            var motivationText: String

            if let data = cleanedJSON.data(using: .utf8) {
                do {
                    let plan = try JSONDecoder().decode(SuggestedTrainingPlan.self, from: data)
                    parsedPlan = plan

                    // SPRINT 13.4: motivation always visible in the chat.
                    // If the AI returns an empty field, show the fallbackMessage so
                    // there is always a human confirmation in the chat.
                    let trimmedMotivation = plan.motivation.trimmingCharacters(in: .whitespacesAndNewlines)
                    motivationText = trimmedMotivation.isEmpty
                        ? (fallbackMessage ?? String(localized: "Ik heb je schema bijgewerkt! Bekijk je overzicht."))
                        : trimmedMotivation

                    // Trigger callback if new preferences were found
                    if let prefs = plan.newPreferences, !prefs.isEmpty {
                        onNewPreferencesDetected?(prefs)
                    }

                    // Update the central plan (also stored in AppStorage).
                    // Story 33.2b: on a reset it goes via mergeReplannedPlan so
                    // moved sessions (`isSwapped`) remain leading over AI output.
                    switch pendingPlanUpdateMode {
                    case .replace:
                        trainingPlanManager?.updatePlan(plan)
                    case .mergePreservingSwaps:
                        trainingPlanManager?.mergeReplannedPlan(plan)
                    }
                    // Always reset after one use — prevents a later chat message
                    // from accidentally still being in merge mode.
                    pendingPlanUpdateMode = .replace

                    // Store the motivation for the dashboard insight block
                    if !motivationText.isEmpty {
                        latestCoachInsight = motivationText
                        lastAnalysisTimestamp = Date().timeIntervalSince1970
                    }
                } catch {
                    // JSON parsing failed: use the fallbackMessage if it was provided
                    // (e.g. on recovery plan or skip-workout calls), so raw JSON is never visible in the chat.
                    // For regular chat messages we show the cleaned text (prose without JSON blocks).
                    AppLoggers.coach.warning("JSON parsing failed: \(error.localizedDescription, privacy: .public)")
                    if let fallback = fallbackMessage {
                        motivationText = fallback
                    } else {
                        // Regular chat: show the cleaned response (without markdown tags) as text
                        motivationText = cleanedJSON.hasPrefix("{") ? String(localized: "Ik kon het schema niet correct verwerken. Probeer het opnieuw.") : cleanedJSON
                    }
                }
            } else {
                motivationText = fallbackMessage ?? String(localized: "Ik kon de reactie niet verwerken. Probeer het opnieuw.")
            }

            messages.append(ChatMessage(role: .ai, text: motivationText, suggestedPlan: parsedPlan))
            isTyping = false
            // Epic #51-A2/A6: housekeeping after successful completion — release the
            // Task handle and clear the active-model snapshot so the banner disappears
            // and the next cancel() does not accidentally hit a finished Task.
            self.currentRequestTask = nil
            self.activeRequestPrimaryModel = ""
            self.activeRequestFallbackModel = ""
        }
    }

    /// Epic #51-A6: cancels a running AI call (e.g. when the user
    /// leaves the Coach tab during the spinner). The catch in the Task catches
    /// the `CancellationError`, cleans up the typing state and lets no
    /// error bubble appear in the chat — a cancelled request must not
    /// feel like a failed call.
    func cancelOngoingRequest() {
        guard let task = currentRequestTask else { return }
        task.cancel()
        // Defensive: also reset the UI state synchronously so a directly
        // re-rendering ChatView does not briefly still show "Coach is aan het typen..."
        // before the Task itself reaches the cleanup branch.
        isTyping = false
        retryStatusMessage = ""
        currentRequestTask = nil
        activeRequestPrimaryModel = ""
        activeRequestFallbackModel = ""
    }

    /// Epic #51-A2: banner text that ChatView shows when the user switches Gemini
    /// model in Settings during an active answer. Returns
    /// `nil` as long as there is no change — then ChatView renders no banner.
    /// Deliberately a computed property so the value always reads fresh AppStorage
    /// values (the snapshot lives on `activeRequestPrimary/FallbackModel`).
    var modelSwitchNotice: String? {
        guard isTyping else { return nil }
        return ChatModelSwitchNotice.message(
            activePrimary: activeRequestPrimaryModel,
            activeFallback: activeRequestFallbackModel,
            configuredPrimary: AIModelAppStorageKey.resolvedPrimary(for: currentProvider),
            configuredFallback: AIModelAppStorageKey.resolvedFallback(for: currentProvider)
        )
    }
}
