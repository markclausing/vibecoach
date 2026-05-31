import Foundation
import SwiftUI
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

    // Read the user's preference regarding the primary data source (Sprint 7.4)
    @AppStorage("selectedDataSource") private var selectedDataSource: DataSource = .healthKit

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

    /// Epic 14.4: Cache of today's Vibe Score for injection into AI prompts.
    /// Gets filled from DashboardView (on onAppear) so the AI always knows the current
    /// recovery status — even without direct SwiftData access in ChatViewModel.
    @AppStorage("vibecoach_todayVibeScoreContext") private var todayVibeScoreContext: String = ""

    /// Epic 18.1: Cache of the subjective feedback (RPE + mood) of the last workout.
    /// Gets filled from DashboardView as soon as an ActivityRecord has a rating.
    @AppStorage("vibecoach_lastWorkoutFeedbackContext") private var lastWorkoutFeedbackContext: String = ""

    /// Epic 17: Cache of the active blueprint status per goal for injection into AI prompts.
    /// Contains open and satisfied critical workouts so the coach can adjust accordingly.
    @AppStorage("vibecoach_blueprintContext") private var blueprintContext: String = ""

    /// Epic 17.1: Cache of the PeriodizationEngine status per goal.
    /// Contains the current training phase + success criteria + progress for targeted phase coaching.
    @AppStorage("vibecoach_periodizationContext") private var periodizationContext: String = ""

    /// Timestamp of the last successful coach analysis (Unix timestamp).
    /// Used to automatically refresh on a new day.
    @AppStorage("vibecoach_lastAnalysisTimestamp") var lastAnalysisTimestamp: Double = 0

    /// Epic 18: Cache of the daily symptom scores — pain figures per body area.
    @AppStorage("vibecoach_symptomContext") private var symptomContext: String = ""

    /// Epic 21: Cache of the 7-day weather forecast — gets filled by WeatherManager.
    /// Gets injected into the AI prompt so the coach takes outdoor activities into account.
    @AppStorage("vibecoach_weatherContext") var weatherContext: String = ""

    /// Epic 32 Story 32.3c: cache of significant physiological patterns in recent
    /// workouts (decoupling, drift, cadence-fade, slow HR recovery). Gets filled
    /// from `DashboardView.refreshWorkoutPatternsContext()` based on the
    /// `WorkoutSample` data of the past 7 days, so the coach can proactively
    /// talk about it in a chat turn.
    @AppStorage("vibecoach_workoutPatternsContext") var workoutPatternsContext: String = ""

    /// Epic 45 Story 45.3: richer per-workout context over the past 14 days
    /// (date, sport, sessionType, duration, TRIMP, avg HR, optionally power, and
    /// detector output per workout). Complement to `workoutPatternsContext` (1-line
    /// pulse over 7 days): the pulse signals THAT something is up, this block gives the
    /// coach the specific evidence per workout so plan adjustments refer
    /// to concrete sessions ("op 28 april reed je een tempo-rit met decoupling…").
    /// Gets filled from `DashboardView.refreshChatContextCaches()`.
    @AppStorage("vibecoach_workoutHistoryContext") var workoutHistoryContext: String = ""

    /// Epic 23 Sprint 1: Cache of the gap analysis per active goal.
    /// Contains the difference between expected and actual TRIMP/km at this moment in the preparation.
    @AppStorage("vibecoach_gapAnalysisContext") private var gapAnalysisContext: String = ""

    /// Epic Doel-Intenties: Cache of the intent instructions per active goal.
    /// Contains the generated coachingInstruction per goal (format, intent, VibeScore adjustment).
    @AppStorage("vibecoach_intentContext") private var intentContext: String = ""

    /// Epic 23 Sprint 2: Cache of the future projection per goal (Future Projection Engine).
    /// Answers the question: "When does the athlete reach the Peak Phase based on his growth rate?"
    /// Gets filled via `cacheProjections(_:)` from GoalsListView and injected into the AI prompt.
    @AppStorage("vibecoach_projectionContext") private var projectionContext: String = ""

    /// Epic 24 Sprint 1: Cache of the physiological profile + nutrition plan for today/tomorrow.
    /// Gets filled via `refreshNutritionContext()` and injected into every AI prompt.
    @AppStorage("vibecoach_nutritionContext") private var nutritionContext: String = ""

    /// Story 33.2a: cache of manually moved workouts (`isSwapped == true`)
    /// so the coach knows in every prompt which sessions the user deliberately
    /// shifted and does not force them back in subsequent suggestions.
    @AppStorage("vibecoach_userOverrideContext") private var userOverrideContext: String = ""

    /// Story 33.4: cache of the Intent-vs-Execution analysis for the most recent workout.
    /// Empty string = no recent comparable workout (no plan match, or insufficient data).
    @AppStorage("vibecoach_intentExecutionContext") private var intentExecutionContext: String = ""

    /// Epic 24 Sprint 3: One-time coach notice on a detected profile change (e.g. age).
    /// Gets written by `PhysicalProfileSection` and injected into the next AI prompt.
    /// Gets cleared after the prompt is built so the notice appears only once.
    @AppStorage("vibecoach_profileUpdateNote") var profileUpdateNote: String = ""

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
            fallbackMessage: "Ik heb je week opnieuw ingedeeld rondom je verplaatste sessies. Bekijk je overzicht.",
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
    /// [DOEL INTENTIES EN BENADERING] section with format, intent and VibeScore instructions.
    func cacheIntentContext(_ results: [PeriodizationResult]) {
        intentContext = IntentContextFormatter.format(results: results)
    }

    /// Epic 23 Sprint 1: Writes the gap analysis (difference planned vs. realized) to the AppStorage cache.
    /// The coach uses this to give concrete adjustment advice:
    /// "Je ligt X km achter op schema — deze week 15% meer volume om dat in te halen."
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
    /// "Op basis van je huidige tempo ben je pas in juli klaar voor de marathon."
    func cacheProjections(_ projections: [GoalProjection]) {
        projectionContext = FutureProjectionService.buildCoachContext(from: projections)
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
        print("🥗 [Nutrition] Context bijgewerkt: \(profile.coachSummary)")
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
            // No nutrition plan for rest days
            guard workout.activityType.lowercased() != "rust" else { return nil }

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
    /// - No score filled in + active UserPreference → show as 'onbekend, score nog niet ingevuld'
    func cacheSymptomContext(_ symptoms: [Symptom], preferences: [UserPreference] = []) {
        symptomContext = SymptomContextFormatter.format(symptoms: symptoms, preferences: preferences)

        // Debug: print the full injury section that goes to Gemini
        print("━━━ 🩺 [Injury Section → Gemini] ━━━")
        print(symptomContext)
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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
        let systemInstruction = ChatScopeInstruction.text + """
            Jij bent een samenwerkende, meedenkende en proactieve AI fitness-coach.
            Je analyseert niet alleen vermoeidheid, maar je helpt de gebruiker actief om de eerstvolgende stap te plannen richting hun gestelde doelen.
            Stel je op als een slimme trainingspartner — niet als een waarschuwende dokter.

            KRITIEKE GEDRAGSREGEL — CONTEXT RESPONSIVITEIT:
            Reageer ALTIJD specifiek op het LAATSTE bericht van de gebruiker. Herhaal nooit alleen de algemene status.
            - Als de gebruiker een specifieke training noemt (bijv. 'avondwandeling', 'intervaltraining'), reageer dan op die specifieke training.
            - Als je het schema aanpast, BEVESTIG dit dan expliciet en concreet: 'Ik heb je geplande intervaltraining voor morgen verschoven naar donderdag vanwege je kuitklachten.' Noem de dag, de activiteit en de reden.
            - Geef nooit een algemeen overzicht als de vraag specifiek is. Wees direct en persoonlijk.

            KRITIEKE REGEL — VIBE SCORE AUTORITEIT:
            De gebruiker heeft een lokaal berekende Vibe Score (0-100) die slaap en HRV combineert. Deze score is de enige objectieve maatstaf voor herstel.
            - Baseer je oordeel over vermoeidheid UITSLUITEND op de Vibe Score die je in de context ontvangt.
            - Score ≥ 80: benader de gebruiker als goed hersteld. Ook als de slaap iets korter was dan ideaal.
            - Score 50-79: wees voorzichtig maar niet alarmerend. Prioriteer Zone 2 en lagere intensiteit.
            - Score < 50: dwing rust of actief herstel af. Dit is een harde rode vlag.
            - Weerspreek de Vibe Score NOOIT op basis van je eigen inschatting van de slaaptijd of andere factoren.

            KRITIEKE REGEL — RPE DISCREPANTIE (Epic 18):
            De gebruiker kan na een training een subjectieve inspanningsscore (RPE 1-10) invullen.
            - Als de TRIMP van een workout laag of gemiddeld is (bijv. <60 TRIMP) maar de RPE ≥8: dit is een ernstig vroeg waarschuwingssignaal voor overtraining of naderende ziekte. Adviseer direct extra rust en verhoog de intensiteit van het plan NIET.
            - Als RPE laag is (1-4) terwijl TRIMP hoog is: de atleet heeft een goede dag — benut dit in je planning.
            - Combineer de RPE altijd met de Vibe Score voor een volledig beeld.

            KRITIEKE REGEL — PERIODISERING & FASE-COACHING (Sprint 17.2):
            Je ontvangt per doel de huidige TrainingPhase, de SuccesCriteria en de behaalde/openstaande status.
            Gebruik deze data ACTIEF in je antwoorden:
            - COMPLIMENTEN (🎉 COMPLIMENT TRIGGER): Als een fase-eis behaald is, open je antwoord dan met een oprecht, specifiek compliment. Noem de behaalde prestatie bij naam (bijv. 'Geweldig — je hebt afgelopen week een 28 km loop neergezet, exact wat de Build-fase vereist!').
            - URGENTIE (🚨 KRITIEKE MIJLPAAL ACHTERSTAND): Als een kritieke eis (bijv. de langste sessie) niet behaald is, wees dan direct maar motiverend. Noem de exacte afstand of TRIMP die nog ontbreekt. Plan de betreffende mijlpaal als EERSTE PRIORITEIT in het schema.
            - SCHEMA-VERANTWOORDINGSPLICHT: Als je het schema aanpast vanwege blessure, overbelasting of andere reden, MOET je altijd uitleggen hoe de fase-eisen ondanks de aanpassing nog steeds haalbaar zijn. Voorbeeld: 'Ik vervang je hardloopsessie door een lange fietsrit, maar de aerobe basis voor de Marathon Blueprint bewaken we zo: op zaterdag plannen we een 26 km duurloop zodra je kuit hersteld is.'
            - Wees streng maar motiverend — de coach staat naast de sporter, niet erboven.

            KRITIEKE REGEL — BLESSURE & SPORT INTERACTIE:
            De dagelijkse pijnscores en beperkingen staan UITSLUITEND in de [ACTUELE KLACHTEN] context die je bij elke interactie ontvangt.
            Dat blok is de 'Single Source of Truth' — volg de HARD CONSTRAINTS daarin strikt op.
            - Als een 🚫 HARD CONSTRAINT aanwezig is: pas het schema ALTIJD aan, benoem de beperking expliciet ('Gezien je kuitpijn van 7/10 plannen we GEEN hardloopsessies deze week').
            - Als een ✅ HERSTELD melding aanwezig is: vier dit in je Insight en stel voorzichtige opbouw voor.
            - Als een gebied 'score nog niet ingevuld vandaag' heeft: wees voorzichtig, maar leg geen absolute verboden op.
            - Zijn er GEEN klachten vermeld? Dan mag je het schema volledig op basis van de blueprint en trainingsfase plannen.

            KRITIEKE REGEL — WEERSGESTUURDE DAGPLANNING (Epic 21):
            Je ontvangt de 7-daagse weersverwachting in de context. Gebruik dit ACTIEF bij het opstellen of aanpassen van het schema.
            - Kijk ALTIJD naar de komende 3 dagen. Als een sleuteltraining (lange rit, tempo-run, interval) vandaag door ⚠️ SLECHT BUITENWEER niet buiten kan, maar morgen of overmorgen de omstandigheden ideaal zijn, stel dan EXPLICIET voor om de trainingen van die dagen om te wisselen.
            - Benoem de dagwissel ALTIJD in het `motivation` veld: "Ik zie dat het zaterdag 75% kans op regen heeft maar zondag helder en windstil is. Ik heb je 60 km duurrit naar zondag verplaatst en zet vandaag een kortere Zone 2-sessie van 45 min op de indoor trainer."
            - Als de zware sleuteltraining naar morgen of overmorgen verschuift: verlaag de TRIMP voor de huidige dag BEWUST zodat de atleet uitgerust aan de sleuteltraining begint. Adviseer max. 40-50% van het normale dagdoel als 'oplaad-dag'. Benoem dit: "Vandaag houden we je TRIMP laag zodat je morgen vers aan de start staat."
            - Windsnelheid > 30 km/u is specifiek relevant voor fietsen: adviseer altijd naar een dag met minder wind te verschuiven als er een alternatief in de komende 3 dagen zit.
            - Als er géén betere dag in het venster van 3 dagen is: stel een indoor-variant voor (trainer, zwemmen, krachttraining) met expliciete vermelding van de weersreden.

            KRITIEKE REGEL — DUBBELE TRAINING & DAGPLANNING (anti-double-day):
            Plan NOOIT meer dan één workout per dag. Dit is een absolute, harde beperking.
            Uitzonderingen zijn alleen toegestaan als aan BEIDE voorwaarden is voldaan:
              (a) de wekelijkse TRIMP-target is aantoonbaar onhaalbaar met één sessie per dag, EN
              (b) de tweede sessie is een actieve herstelblok (TRIMP ≤ 30, uitsluitend Zone 1/wandelen).

            CONFLICTRESOLUTIE — wanneer meerdere trainingen dezelfde dag claimen:
            Volg deze prioriteitsvolgorde strikt:
              1. Krachttraining heeft de hoogste prioriteit; een concurrerende duurtraining vervalt of schuift.
              2. Als de duurtraining een cruciale mijlpaal vertegenwoordigt (bijv. de vereiste 60 km-rit voor de fietsblueprint binnen 7 dagen), schuift de krachttraining naar de dichtstbijzijnde vrije dag.
              3. Een rustdag mag nooit worden omgezet in een trainingsdag alleen om een verplaatste training op te vangen — respecteer de rustdagen in het wekelijkse patroon.
              4. Als geen vrije dag beschikbaar is: annuleer de lagere-prioriteit training volledig en compenseer via het weekvolume op de overige dagen (max. 10–15% meer TRIMP per dag).

            VERPLICHTE UITLEGPLICHT bij dagconflicten:
            Als je een training annuleert of verschuift om een dubbele dag te voorkomen, MOET je dit in het `motivation` veld expliciet benoemen.
            Gebruik dit exact als template: "Ik heb de geplande [naam training] van [dag] laten vervallen / verschoven naar [nieuwe dag], zodat je alle focus kunt leggen op [behouden training]. [Optioneel: waarom die training de prioriteit had]."
            Voorbeeld: "Ik heb de geplande herstelrit van dinsdag laten vervallen, zodat je alle focus kunt leggen op je krachttraining. Fietsen staat vrijdag terug in het schema."

            KRITIEKE BEPERKING — WANDELEN:
            Wandelen mag uitsluitend als herstel-activiteit bij blessures of een Vibe Score < 50.
            Een wandelsessie mag NOOIT langer zijn dan 60 minuten. Stel in de JSON altijd suggestedDurationMinutes ≤ 60 in voor wandelingen.

            Belangrijke context voor je analyse:
            Wij berekenen lokaal een Banister TRIMP (Training Impulse) score om de trainingsbelasting te bepalen (niet de traditionele TSS die op 100/uur cap).
            - Een TRIMP van 70-100 is een pittige, solide training.
            - Een TRIMP van 100-140 is een zeer zware training, maar dit is op zichzelf geen teken van overtraining.

            BELANGRIJK: Zodra je een schema of status voor de komende 7 dagen plant of analyseert, MOET je antwoord een JSON object bevatten (eventueel in een codeblock) dat voldoet aan deze structuur:
            {
                "motivation": "Schrijf hier een empathische, beschrijvende analyse van maximaal 3 zinnen. Begin met een DIRECTE reactie op het laatste bericht van de gebruiker (benoem de specifieke activiteit). Leg daarna het WAAROM uit achter je strategische keuzes. Als je een aanpassing maakt in het schema, bevestig dit expliciet ('Ik heb X verschoven naar Y omdat...'). Als je een dubbele dag hebt opgelost door een training te annuleren of te verschuiven, benoem dit altijd: 'Ik heb [training] van [dag] laten vervallen/verschoven naar [dag], zodat je alle focus kunt leggen op [behouden training].' Geef de gebruiker het gevoel dat de coach écht meedenkt en écht luistert.",
                "workouts": [
                    {
                        "dateOrDay": "Maandag",
                        "activityType": "Hardlopen",
                        "suggestedDurationMinutes": 45,
                        "targetTRIMP": 60,
                        "description": "Herstel na de lange duurloop",
                        "heartRateZone": "Zone 2",
                        "targetPace": "5:30 min/km",
                        "reasoning": "Zone 2 herstelloop om de aerobe basis te bewaken. TRIMP 60 = 75% van het wekelijkse Build-fase doel."
                    }
                ],
                "newPreferences": [
                    {
                        "text": "Ik heb last van mijn knie",
                        "expirationDate": "2024-05-20"
                    }
                ]
            }
            Extra instructie voor `reasoning` (Sprint 17.3): Vul voor ELKE workout het `reasoning` veld in met een korte, feitelijke verklaring (max. 1 zin) waarom deze training in het schema staat. Baseer dit op de fase, de succescriteria en het doel. Bijv: "60 km = langste-sessie-eis (60%) in de Build-fase voor je fietsdoel." of "Zone 2 herstelloop om de aerobe basis te bewaken." Laat dit veld NOOIT leeg.

            Extra instructie voor `newPreferences`: Als je opmerkt dat de gebruiker een vaste regel, langetermijnvoorkeur, of tijdelijke kwaal/blessure doorgeeft in hun LAATSTE bericht, vul dit array dan aan. Schat in of dit feit permanent is (zoals een vaste sportdag) of tijdelijk (zoals spierpijn, een lichte blessure of kramp). Als het tijdelijk is, bereken dan een logische verloopdatum (bijv. 1 of 2 weken vanaf vandaag) en retourneer deze in de JSON onder `expirationDate` als een "YYYY-MM-DD" string. Laat `expirationDate` leeg (null) bij permanente regels. Herhaal geen regels die je al kent.
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
            return "Geen actueel gepland schema bekend."
        }

        var planString = "Dit is mijn momenteel geplande schema (vergelijk je advies altijd hiermee):\n"
        for workout in decodedPlan.workouts {
            planString += "- \(workout.dateOrDay): \(workout.activityType) "
            if workout.suggestedDurationMinutes > 0 {
                planString += "(\(workout.suggestedDurationMinutes) min)"
            }
            if let trimp = workout.targetTRIMP {
                planString += " [Doel TRIMP: \(trimp)]"
            }
            planString += "\n"
        }
        return planString
    }

    /// Generates a context-prefix string based on the given athletic profile.
    /// Epic #44 story 44.6: builds the `[TRAININGSDREMPELS]` block based on the
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
            lines.append("- Rust HR: \(Int(rest.value)) BPM (\(thresholdSourceLabel(rest.source)))")
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

        var block = "[TRAININGSDREMPELS (persoonlijk profiel):\n"
        block += lines.joined(separator: "\n")
        if let zonesLine {
            block += "\n\(zonesLine)"
        }
        block += """

        Gedragsregels:
        1. Interpreteer "rustig"/"easy"/"recovery" altijd in de context van DEZE drempels — niet populatie-gemiddelden. Een gebruiker met max 200 BPM die op 146 BPM traint, zit in Z2, niet Z3.
        2. Bij subjectieve feedback over inspanning: koppel aan de zone, niet alleen aan het BPM-getal ("145 BPM is voor jou Z2 — dat klopt met 'rustig'").
        3. Bij plan-aanpassingen waar zones expliciet genoemd worden, gebruik de bovenstaande BPM-grenzen voor de instructie aan de gebruiker.]
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
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        prefix += "[HUIDIGE DATUM: Vandaag is het \(dateFormatter.string(from: now)). Gebruik dit voor je berekeningen rondom 'expirationDate'.]\n\n"

        // Epic 14.4: Inject the Vibe Score as hard context — the AI MUST follow this (see system instruction)
        if todayVibeScoreContext == VibeScoreContextFormatter.noVibeDataSentinel {
            // No Watch data available — give the coach an explicit instruction to communicate this correctly
            prefix += "[HERSTELSTATUS VANDAAG: Er is geen objectieve biometrische data beschikbaar (gebruiker droeg de Apple Watch waarschijnlijk niet 's nachts). Vertrouw volledig op de Symptom Tracker scores en de geplande doelen. Gebruik NOOIT zinnen als 'Ik zie aan je HRV dat...' of 'Je biometrie geeft aan...'. Zeg in plaats daarvan: 'Omdat we vandaag geen Watch-data hebben, gaan we uit van je eigen gevoel en de ingevoerde scores.']\n\n"
        } else if !todayVibeScoreContext.isEmpty {
            prefix += "[HERSTELSTATUS VANDAAG: \(todayVibeScoreContext) Volg de kritieke regel over de Vibe Score autoriteit strikt.]\n\n"
        }

        // Epic 18.1: Inject the subjective feedback (RPE + mood) of the last workout
        if !lastWorkoutFeedbackContext.isEmpty {
            prefix += "[SUBJECTIEVE FEEDBACK LAATSTE WORKOUT: \(lastWorkoutFeedbackContext) Let op discrepanties: als TRIMP laag is maar RPE ≥8, is dit een vroeg signaal van overtraining of naderende ziekte.]\n\n"
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
            [ACTUELE KLACHTEN — SINGLE SOURCE OF TRUTH (dagelijks bijgewerkt door de gebruiker):
            \(symptomContext)
            Gedragsregels:
            1. 🚫 HARD CONSTRAINT aanwezig → volg de beperking strikt. Benoem de blessure en het alternatief expliciet.
            2. ✅ HERSTELD aanwezig → open je Insight met een feestelijke bevestiging. Stel voorzichtige opbouw voor (bijv. 'Begin met 20 min Zone 1, bouw volgende week op naar normaal volume').
            3. Score ≥7 → extra voorzichtig; overweeg een volledige rustdag of alternatieve sport.
            4. Score gedaald t.o.v. gisteren → benoem dit als positief teken van herstel.]
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
            [FYSIOLOGISCHE PATRONEN IN RECENTE WORKOUTS:
            \(workoutPatternsContext)
            Gedragsregels:
            1. Als de gebruiker een vraag stelt over recente trainingen, refereer dan aan deze patronen waar relevant — wees concreet, geen lijst van technische termen.
            2. Bij significant cardiac drift + decoupling: vraag of het bewust drempel-werk was, of dat er externe oorzaken speelden (hitte, slaap, stress).
            3. Trage HR-recovery is een vermoeidheid-signaal — combineer met TRIMP en VibeScore voordat je herstel adviseert.
            4. Noem deze patronen NIET ongevraagd in elke turn; alleen wanneer de gebruiker reflecteert op recente uitvoering of trainingsplan-aanpassingen vraagt.]
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
            [RECENTE TRAINING — 14 DAGEN (nieuwste eerst):
            \(workoutHistoryContext)
            Gedragsregels:
            1. Refereer specifiek aan datum + sessietype bij elke workout-aanhaal ("op 18 april in je tempo-rit met cardiac drift 8% …"). Geen vage termen als "recent".
            2. Bij ≥3 opeenvolgende workouts met aerobic_decoupling of cardiac_drift: stel sub-LTHR werk voor en motiveer met de specifieke data uit deze lijst.
            3. Gebruik deze data alléén bij reflectie/schema-vragen/doelanalyse — niet ongevraagd in elke turn opnoemen.
            4. Combineer met [TRAININGSDREMPELS] voor zone-correcte interpretatie van de gem-HR. Gebruik dezelfde zone-terminologie ("Zone 2"/"Z2", "Zone 3"/"Z3", "LTHR") — verzin geen nieuwe labels.
            5. Weeg deze data tegen [ACTUELE KLACHTEN]. Bij actieve blessure: interpreteer patronen zoals cardiac_drift voorzichtiger (kan herstel-vermoeidheid zijn, niet trainingsbehoefte). Suggereer geen volume-verhogingen als de gebruiker herstellende is.]
            """
            prefix += historyBlock + "\n\n"
        }

        // Epic 21: Inject the 7-day weather forecast for outdoor-activities coaching
        if !weatherContext.isEmpty {
            let weatherBlock = """
            [WEERSOMSTANDIGHEDEN KOMENDE 7 DAGEN (locatie gebruiker):
            \(weatherContext)
            Gedragsregels:
            1. DAGWISSEL STRATEGIE: Als een dag met ⚠️ SLECHT BUITENWEER een sleuteltraining heeft, kijk dan naar de komende 3 dagen. Is er een betere dag? Wissel dan EXPLICIET van dag en benoem dit in het `motivation` veld.
            2. TRIMP-VOORBEREIDING: Als de sleuteltraining naar morgen of overmorgen verschuift, adviseer vandaag max. 40-50% TRIMP als 'oplaad-dag'. Noem dit expliciet.
            3. Wees altijd specifiek over percentages: niet "het kan regenen" maar "Zaterdag 72% neerslag → ik verplaats de 60 km naar zondag (5% neerslag, windstil)".
            4. Wind > 30 km/u = relevant voor fietsen. Zoek altijd een windstillere dag als die er is.
            5. Temperatuur < 5°C of > 30°C → tip over kleding of hydratatie.
            6. Goed weer hoef je niet te vermelden tenzij het een bonus is ("Zondag ziet er ideaal uit — perfect voor je lange rit").]
            """
            prefix += weatherBlock + "\n\n"
        }

        // Epic 17 / Sprint 17.2: Inject the blueprint + periodization context
        // and print the full content to the console for debugging.
        let hasBlueprintData  = !blueprintContext.isEmpty
        let hasPeriodization  = !periodizationContext.isEmpty

        if hasBlueprintData {
            prefix += "[SPORTWETENSCHAPPELIJKE EISEN (BLUEPRINT):\n\(blueprintContext)\nInstructie: Controleer ALTIJD of de gebruiker op schema ligt voor zijn kritieke trainingen. Als er een openstaande (❌) eis is met een naderende deadline, maak dit dan expliciet in je advies en plan de betreffende training in.]\n\n"
        }

        if hasPeriodization {
            prefix += "[PERIODISERING — FASE, SUCCESCRITERIA & COACH-GEDRAG:\n\(periodizationContext)\n\nCoach-gedragsregels voor deze context:\n1. COMPLIMENTEN (🎉): Als een COMPLIMENT TRIGGER aanwezig is, open je antwoord dan hiermee. Noem de behaalde prestatie bij naam.\n2. URGENTIE (🚨): Als een KRITIEKE MIJLPAAL ACHTERSTAND aanwezig is, wees dan direct en motiverend. Noem de exacte afstand of TRIMP die nog ontbreekt, en plan dit als eerste prioriteit in het schema.\n3. SCHEMA-AANPASSING: Als je het schema aanpast, verklaar dan altijd hoe de fase-eisen ondanks de aanpassing nog steeds haalbaar zijn (SCHEMA-VERANTWOORDINGSPLICHT).]\n\n"
        }

        // Epic Doel-Intenties: inject the intent and format instructions as a separate section.
        // This tells the coach HOW to train (cruising vs. performing, stage ride vs. one-day)
        // and whether stretch-pace trainings are safe based on the current VibeScore.
        if !intentContext.isEmpty {
            let intentBlock = """
            [DOEL INTENTIES EN BENADERING — LEES DIT VÓÓR JE HET SCHEMA OPSTELT:
            \(intentContext)

            Bindende coach-regels:
            1. INTENTIE HEEFT PRIORITEIT: Pas het schema ALTIJD aan op de intentie en het formaat. Een 'uitlopen'-doel krijgt NOOIT interval- of tempotraining tenzij expliciet gevraagd.
            2. BACK-TO-BACK (meerdaagse etappe): Plan zware sessies op opeenvolgende dagen (bijv. Za+Zo). Verlaag single-session piekbelasting t.o.v. een eendaagse race.
            3. STRETCH GOAL VEILIGHEID: Als '✅ DOELTIJD' aanwezig is, plan dan één temposessie per week op doelsnelheid. Als '🔴 DOELTIJD' aanwezig is, schrap alle tempo-elementen en ga terug naar pure duurtraining.
            4. VIBE SCORE OVERRIDE: Als VibeScore < 65 wordt vermeld, heeft herstel absolute prioriteit — schrap intensieve elementen ongeacht de rest van het plan.]
            """
            prefix += intentBlock + "\n\n"
        }

        // Epic 23 Sprint 1: Inject the gap analysis with TRIMPTranslator hints
        if !gapAnalysisContext.isEmpty {
            let gapBlock = """
            [GAP ANALYSE — BLUEPRINT VS. WERKELIJKHEID (Epic 23):
            \(gapAnalysisContext)
            Coach-gedragsregels:
            1. TRIMP-VERTALING (VERPLICHT): Als er een 📈 VOLUME-BIJSTURING staat met een "X TRIMP ≈ +Y min …"-hint, gebruik dan ALTIJD die vertaling. Noem NOOIT een los TRIMP-getal zonder de bijbehorende tijdsindicatie. Correct: "Je hebt deze week zo'n 8 TRIMP extra nodig — dat is ongeveer +4 minuten op je zaterdag-rit." Fout: "Je hebt 8 TRIMP tekort."
            2. KOPPEL AAN HET SCHEMA: Vertaal de bijsturing altijd naar een aanpassing van een bestaande trainingsdag. Bijv. "Verleng je dinsdag-duurloop met 5 minuten" of "Rij zaterdag 10 minuten langer door na de bekende route."
            3. Als er een 🚴 KM-BIJSTURING staat: geef een concreet weekschema met extra km per training, niet als abstract totaal.
            4. Als de atleet voorloopt op schema: complimenteer kort en adviseer consistentie — geen extra volume voorschrijven.
            5. Verbind altijd aan de fase: bijsturing in de Taper-fase is onwenselijk — adviseer dan om het tekort NIET in te halen maar door te gaan met het tapering-schema.]
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

        // Debug: print the full blueprint and periodization context that goes to Gemini
        if hasBlueprintData || hasPeriodization {
            print("━━━ 🧠 [Blueprint Context → Gemini] ━━━")
            if hasBlueprintData { print("[BLUEPRINT]\n\(blueprintContext)") }
            if hasPeriodization { print("[PERIODISERING]\n\(periodizationContext)") }
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }

        // Epic 16: Inject the training phase per active goal — the AI MUST follow the phase instructions strictly
        let activeGoalsWithPhase = activeGoals.compactMap { goal -> (FitnessGoal, TrainingPhase)? in
            guard let phase = goal.currentPhase else { return nil }
            return (goal, phase)
        }
        if !activeGoalsWithPhase.isEmpty {
            prefix += "[PERIODISERING — ACTIEVE TRAININGSFASES:\n"
            for (goal, phase) in activeGoalsWithPhase {
                let weeksLeft = goal.weeksRemaining(from: now)
                let weeksLeftStr = String(format: "%.1f", weeksLeft)
                // Compute the phase-corrected weekly target (linear baseline × multiplier)
                let linearRate = goal.computedTargetTRIMP / max(0.1, weeksLeft)
                let adjustedTarget = Int((linearRate * phase.multiplier).rounded())
                prefix += "• Doel '\(goal.title)' (\(weeksLeftStr) weken resterend): \(phase.aiInstruction)\n"
                prefix += "  Wiskundig aangepaste wekelijkse TRIMP-target: \(adjustedTarget) TRIMP/week (multiplier: ×\(String(format: "%.2f", phase.multiplier))). Houd je strikt aan deze target.\n"
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

            prefix += "[CONTEXT ATLEET: Heeft een piekprestatie van \(peakDistanceKm) km in \(peakDurationMin) minuten. Traint gemiddeld \(weeklyVolumeMin) minuten per week (gem. laatste 4 weken), en heeft \(p.daysSinceLastTraining) dagen geleden voor het laatst getraind."

            // SPRINT 6.3: Overtraining warning
            if p.isRecoveryNeeded {
                prefix += " URGENT: De atleet vertoont tekenen van overtraining op basis van recent volume. Wees streng, adviseer actief om rust te nemen en analyseer deze training puur op herstel."
            }

            // SPRINT 9.3: Pace Baseline Injection
            if let avgPaceInSeconds = p.averagePacePerKmInSeconds {
                let minutes = avgPaceInSeconds / 60
                let seconds = avgPaceInSeconds % 60
                let paceString = String(format: "%d:%02d", minutes, seconds)
                prefix += " Belangrijke fysiologische context: Het actuele gemiddelde hardlooptempo van de gebruiker ligt rond de \(paceString) min/km (bovenkant Zone 2). Gebruik dit als absolute baseline om realistische 'targetPace' doelen voor de komende trainingen te berekenen."
            }

            prefix += " Neem dit mee in je analyse over herstel en prestatie.]\n\n"
        }

        guard !prefix.isEmpty else { return "" }
        prefix += "[VRAAG]: "
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
            "RECOVERY CONTEXT — Mijn doel(en) lopen achter op schema. Maak een geleidelijk herstelplan:",
            ""
        ]

        // Epic 14.4: Inject the Vibe Score so the recovery plan respects the current recovery status
        if todayVibeScoreContext == VibeScoreContextFormatter.noVibeDataSentinel {
            systemLines.append("HERSTELSTATUS VANDAAG: Geen Watch-data beschikbaar. Baseer het herstelplan op de Symptom Tracker scores en eigen gevoel van de gebruiker.")
            systemLines.append("")
        } else if !todayVibeScoreContext.isEmpty {
            systemLines.append("HERSTELSTATUS VANDAAG: \(todayVibeScoreContext) Pas de intensiteit van het herstelplan STRIKT aan op deze score (zie systeeminstructie).")
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
                horizonAdvice = "Het evenement is \(weeksText) weken weg. PRIORITEIT: Base Building. Verhoog het wekelijkse volume heel geleidelijk — streef naar +\(gradualWeeklyIncrease) TRIMP/week over de komende maanden. Geen paniektrainingen."
            } else if risk.weeksRemaining > 4 {
                horizonAdvice = "Het evenement is \(weeksText) weken weg. Verhoog het volume gecontroleerd, maar bouw nog geen volledige piekbelasting op."
            } else {
                horizonAdvice = "Het evenement is \(weeksText) weken weg. Focus op efficiënte, kwaliteitsvolle trainingen — geen drastische volumestijging meer."
            }

            systemLines.append("• Doel: '\(risk.title)'")
            systemLines.append("  - Actuele burn rate: \(currentRate) TRIMP/week")
            systemLines.append("  - Benodigde burn rate (ideaal): \(Int(risk.requiredWeeklyRate)) TRIMP/week")
            systemLines.append("  - Wekelijks tekort: \(deficit) TRIMP")
            systemLines.append("  - Weken resterend: \(weeksText)")
            systemLines.append("  - Horizon advies: \(horizonAdvice)")
            systemLines.append("")

            // Compute the maximum allowed weekly volume (10-15% rule)
            let maxAllowedRate = Int(Double(currentRate) * 1.12) // 12% = middle of 10-15%
            systemLines.append("  ⛔️ HARDE FYSIOLOGISCHE GRENS: De totale wekelijkse TRIMP voor de komende week mag NOOIT meer zijn dan \(maxAllowedRate) TRIMP (\(currentRate) × 1.12). Dit is de 10-15% progressieregel om overtraining te voorkomen. Dit is niet onderhandelbaar.")
            systemLines.append("")
        }
        systemLines.append(contentsOf: [
            "Geef me een concreet, haalbaar herstelplan voor de komende 7 dagen.",
            "Het plan moet:",
            "1. De 10-15% progressieregel strikt respecteren — liever iets te conservatief dan te agressief.",
            "2. Het tekort uitsmeren over meerdere weken als het evenement ver weg is (zie horizon advies hierboven).",
            "3. Extra volume verdelen via frequentie (extra rustdag omzetten in een lichte sessie) i.p.v. één megasessie.",
            "4. Altijd het volledige 7-daagse schema retourneren in JSON-formaat.",
            "",
            "⛔️ EXTRA INTENSITEITSLIMIETEN (niet onderhandelbaar):",
            "- Binnensessies (indoor fietsen, roeien, zwemmen) mogen NOOIT langer zijn dan 60 minuten, tenzij het doel expliciet een duurtraining van >90 min vereist.",
            "- Geen enkele individuele sessie mag meer dan 40% hoger in TRIMP zijn dan het gemiddelde van de afgelopen 7 dagen. Voorkomen van extreme pieken is prioriteit."
        ])

        let systemPrompt = systemLines.joined(separator: "\n")

        // The text the user sees in the chat (concise and understandable)
        let goalTitles = atRiskGoals.map { "'\($0.title)'" }.joined(separator: " en ")
        let userFacingText = "Los de achterstand op voor \(goalTitles) en geef me een bijgestuurd schema."

        sendHiddenSystemMessage(
            systemText: systemPrompt,
            userText: userFacingText,
            fallbackMessage: "Ik heb je herstelplan klaar! Bekijk je overzicht — het schema is bijgewerkt om je weer op schema te brengen.",
            contextProfile: contextProfile,
            activeGoals: activeGoals,
            activePreferences: activePreferences
        )
    }

    /// Handles rejecting (skipping) a specific suggested workout (Rest Day).
    func skipWorkout(_ workout: SuggestedWorkout, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        let systemPrompt = "Ik sla de training '\(workout.activityType)' op \(workout.dateOrDay) over. Herbereken de week en schuif de belasting door. BELANGRIJK: Retourneer in je JSON-output altijd het volledige 7-daagse schema (inclusief alle ongewijzigde andere dagen), en niet alleen de aangepaste dag."
        let userFacingText = "Ik sla de geplande \(workout.activityType) op \(workout.dateOrDay) over."
        sendHiddenSystemMessage(systemText: systemPrompt, userText: userFacingText, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
    }

    /// Handles the request for an alternative workout.
    func requestAlternativeWorkout(_ workout: SuggestedWorkout, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        let systemPrompt = "Ik vind de geplande training '\(workout.activityType)' op \(workout.dateOrDay) niet leuk. Geef me een alternatief voor \(workout.dateOrDay) dat een vergelijkbare trainingsprikkel geeft. BELANGRIJK: Retourneer in je JSON-output altijd het volledige 7-daagse schema (inclusief alle ongewijzigde andere dagen), en niet alleen de aangepaste dag."
        let userFacingText = "Geef me een alternatief voor de \(workout.activityType) op \(workout.dateOrDay)."
        sendHiddenSystemMessage(systemText: systemPrompt, userText: userFacingText, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
    }

    /// Sends a message where the UI shows a simple text, but the payload contains the technical prompt.
    /// If JSON parsing fails, `fallbackMessage` is shown instead of the raw AI text —
    /// so that on recovery plan / skip-workout calls raw JSON never appears in the chat.
    private func sendHiddenSystemMessage(
        systemText: String,
        userText: String,
        fallbackMessage: String = "Ik heb je schema bijgewerkt! Bekijk je overzicht voor het nieuwe plan.",
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
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
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

        var lines: [String] = [storedPlanContext, "\nDit zijn mijn meest recente voltooide trainingen (inclusief rustdagen):"]

        // Inject Goals explicitly
        let uncompletedGoals = activeGoals.filter { !$0.isCompleted }
        if uncompletedGoals.isEmpty {
            lines.append("- Mijn opgeslagen doelen: Geen specifieke doelen.")
        } else {
            let goalsString = uncompletedGoals.map { goal in
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                let dateStr = formatter.string(from: goal.targetDate)
                let sport = goal.sportCategory?.displayName ?? "Sport"
                return "\(goal.title) (\(sport)) voor \(dateStr)"
            }.joined(separator: ", ")
            lines.append("- Mijn opgeslagen doelen: \(goalsString)")
        }

        lines.append("- Mijn belasting (afgelopen \(days) dagen):")
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
                        lines.append("- Dag \(emptyDaysStreak[0]): Rust")
                    } else {
                        lines.append("- Dag \(emptyDaysStreak.first!) t/m \(emptyDaysStreak.last!): Rust")
                    }
                    emptyDaysStreak.removeAll()
                }

                var dayName = "Dag \(displayDay)"
                if dayOffset == 0 {
                    dayName += " (Vandaag)"
                } else if dayOffset == 1 {
                    dayName += " (Gisteren)"
                }

                for workout in dailyWorkouts {
                    lines.append("- \(dayName): \(workout.durationMinutes) min \(workout.name) (TRIMP: \(workout.trimp))")
                }
            } else {
                emptyDaysStreak.append(displayDay)
            }
        }

        if !emptyDaysStreak.isEmpty {
            if emptyDaysStreak.count == 1 {
                lines.append("- Dag \(emptyDaysStreak[0]): Rust")
            } else {
                lines.append("- Dag \(emptyDaysStreak.first!) t/m \(emptyDaysStreak.last!): Rust")
            }
        }

        lines.append("Totale Cumulatieve TRIMP: \(totalTrimp)")

        lines.append("\nInstructie voor de Coach:")

        let dateString = now.formatted(date: .complete, time: .omitted)
        lines.append("LET OP: Vandaag is het \(dateString). Het nieuwe 7-daagse schema MOET vanaf vandaag beginnen. Verwijder dagen in het verleden en vul de week aan.")
        lines.append("KRITIEK: Sorteer de workouts in het JSON-array ALTIJD chronologisch — dag 1 (vandaag) eerst, dag 7 (over 6 dagen) als laatste. Nooit andersom, nooit willekeurig.")
        lines.append("Vergelijk deze recente activiteiten met het actuele schema hierboven. Is het resterende schema voor deze week nog steeds optimaal en realistisch? Zo niet, herbereken het schema (retourneer altijd alle 7 dagen) en geef een korte motivatie of feedback op mijn recente trainingen.")

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
                    print("⚠️ Geen of lege HealthKit workouts gevonden, terugvallen op Strava.")
                } catch {
                    print("⚠️ Fout bij ophalen HealthKit data (\(error.localizedDescription)), terugvallen op Strava.")
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
                print("⚠️ Geen of lege HealthKit workouts gevonden, terugvallen op Strava.")
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
            } else {
                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: "Ik kon geen recente trainingen vinden in HealthKit of je Strava account."))
                    isFetchingWorkout = false
                }
            }
        } catch {
            if !isFallback {
                print("⚠️ Fout bij ophalen HealthKit data (\(error.localizedDescription)), terugvallen op Strava.")
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
            } else {
                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: "Ik kon geen recente trainingen vinden. HealthKit fout: \(error.localizedDescription)"))
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
                    print("⚠️ Geen recente Strava activiteit gevonden. Reverse fallback naar HealthKit.")
                    await fetchHealthKitRecentWorkouts(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
                    return
                }

                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: "Ik kon geen recente trainingen vinden in HealthKit of je Strava account."))
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
                print("⚠️ Strava API fout (\(error)). Reverse fallback naar HealthKit.")
                await fetchHealthKitRecentWorkouts(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
                return
            }

            var errorMsg = "Fout bij ophalen van data: "
            switch error {
            case .missingToken: errorMsg += "Je bent niet ingelogd op Strava. Ga naar instellingen om te koppelen."
            case .unauthorized: errorMsg += "Je Strava sessie is verlopen. Koppel opnieuw in de instellingen."
            case .rateLimited(let retryAfter):
                let f = DateFormatter()
                f.locale = Locale(identifier: "nl_NL")
                f.dateFormat = "HH:mm"
                errorMsg += "Strava-limiet bereikt — hervat om \(f.string(from: retryAfter))."
            case .networkError(let desc): errorMsg += "Netwerkfout (\(desc))."
            case .decodingError(let desc): errorMsg += "Data onleesbaar (\(desc))."
            case .invalidResponse: errorMsg += "Ongeldig antwoord van de server."
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
    /// 2. If the string still does not start with `{` afterwards, find the first `{`
    ///    and the last `}` and extract only that part.
    /// 3. Trim whitespace.
    private func extractCleanJSON(from rawText: String) -> String {
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

        // Step 2: If there is still prose before the JSON, extract the { ... } block directly
        if !text.hasPrefix("{") {
            if let startIndex = text.firstIndex(of: "{"),
               let endIndex = text.lastIndex(of: "}") {
                text = String(text[startIndex...endIndex])
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

            print("DEBUG PROMPT: \(text)")

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
                    retryStatusMessage = "Model tijdelijk overbelast — overschakelen naar lichtere variant..."
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

            // Handle the successful response
            print("DEBUG RAW RESPONSE: \(responseText ?? "nil")")

            // Use the robust JSON extractor: strip markdown and pull out the JSON object
            let cleanedJSON = extractCleanJSON(from: responseText ?? "{}")

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
                        ? (fallbackMessage ?? "Ik heb je schema bijgewerkt! Bekijk je overzicht.")
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
                    print("⚠️ JSON-parsing mislukt: \(error.localizedDescription)")
                    if let fallback = fallbackMessage {
                        motivationText = fallback
                    } else {
                        // Regular chat: show the cleaned response (without markdown tags) as text
                        motivationText = cleanedJSON.hasPrefix("{") ? "Ik kon het schema niet correct verwerken. Probeer het opnieuw." : cleanedJSON
                    }
                }
            } else {
                motivationText = fallbackMessage ?? "Ik kon de reactie niet verwerken. Probeer het opnieuw."
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
