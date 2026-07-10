import Foundation
import SwiftUI
import Combine

/// The viewmodel that tracks the chat state and handles actions.
///
/// Story 65.3: a thin `@MainActor` orchestrator. Prompt assembly lives in
/// `CoachPromptAssembler`, the PHI context cache in `CoachContextStore` (`context`),
/// the model construction in `CoachModelProvider` (`modelProvider`) and the response
/// parsing in `CoachResponseParser`.
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
    /// Status message during a retry attempt. Empty if no retry is running.
    @Published var retryStatusMessage: String = ""
    /// True if we are currently fetching Strava data via the explicit button.
    @Published var isFetchingWorkout: Bool = false
    /// User-friendly error message from the last AI call. `nil` as soon as a new call
    /// starts or completes successfully. Screens without a chat (Dashboard pull-to-refresh)
    /// use this to show a banner — otherwise a timeout would fail silently.
    @Published var lastAIErrorMessage: String?

    /// Epic #51-A2: snapshot of the primary/fallback model names in use for the current
    /// `fetchAIResponse` call. Compared by the UI with the current AppStorage choice to
    /// show a banner if the user switches model during `isTyping`.
    @Published private(set) var activeRequestPrimaryModel: String = ""
    @Published private(set) var activeRequestFallbackModel: String = ""

    // MARK: - Collaborators (Story 65.3 decomposition)

    /// Owns the AI model construction + lazy cache (`CoachModelProvider`).
    private let modelProvider: CoachModelProvider

    /// Owns the PHI context cache in SwiftData. Views call `viewModel.context.cacheX(...)`.
    let context = CoachContextStore()

    /// The model against which we run AI requests (delegated to `modelProvider`).
    private var model: GenerativeModelProtocol { modelProvider.model }

    /// Epic #53: the currently active provider (from AppStorage) — for the model-name
    /// snapshot and the `modelSwitchNotice`.
    private var currentProvider: AIProvider { AIProvider.current() }

    /// Epic #51-A6: handle to the running AI Task so `cancelOngoingRequest()` can cancel it
    /// when the user leaves the Coach tab (or sends a new message before the previous one).
    private var currentRequestTask: Task<Void, Never>?

    /// Service for HealthKit (Sprint 7.2) — kept for the nutrition-context profile fetch.
    private let healthKitManager: HealthKitManager

    /// Orchestrates the HealthKit/Strava fetch waterfall for `analyzeCurrentStatus`.
    private let statusAnalyzer: CoachStatusAnalyzer

    /// Read the user's preference regarding the primary data source (Sprint 7.4).
    @AppStorage(AppStorageKeys.selectedDataSource) private var selectedDataSource: DataSource = .healthKit

    /// True if a usable API key is configured (delegated to `modelProvider`).
    var hasAPIKey: Bool { modelProvider.hasAPIKey }

    /// The shared state manager for the current training plan.
    private var trainingPlanManager: TrainingPlanManager?

    /// Stored data of the most recently generated plan (for the status-prompt reference).
    @AppStorage("latestSuggestedPlanData") private var latestSuggestedPlanData: Data = Data()
    /// Stored insight/motivation from the coach to highlight on the dashboard.
    @AppStorage("latestCoachInsight") private var latestCoachInsight: String = ""

    /// Risk data per goal for a recovery-plan request (Sprint 13.3). Lives on the assembler.
    typealias GoalRiskInfo = CoachPromptAssembler.GoalRiskInfo
    /// One completed workout day mapped from HealthKit/Strava for the status prompt.
    typealias DailyWorkout = CoachPromptAssembler.DailyWorkout

    /// Callback to send new preferences to the View so they get stored in SwiftData.
    var onNewPreferencesDetected: (([ExtractedPreference]) -> Void)?

    /// Sets the TrainingPlanManager.
    func setTrainingPlanManager(_ manager: TrainingPlanManager) {
        self.trainingPlanManager = manager
    }

    /// SPRINT 13.4: the most recently stored coach insight — ChatView's empty-chat welcome.
    var latestStoredInsight: String { latestCoachInsight }

    /// SPRINT 13.4: adds the most recent coach insight as a welcome message. Called only if
    /// `messages` is empty, so existing conversations are not disturbed.
    func injectWelcomeMessage(_ text: String) {
        guard messages.isEmpty, !text.isEmpty else { return }
        messages.append(ChatMessage(role: .ai, text: text))
    }

    /// Initializes the `ChatViewModel`.
    ///
    /// - Parameter aiModel: The AI service to be used. When nil the real provider client is
    ///   built lazily on the first request. Tests inject a mock here.
    init(aiModel: GenerativeModelProtocol? = nil,
         fitnessDataService: FitnessDataService = FitnessDataService(),
         healthKitManager: HealthKitManager = HealthKitManager(),
         fitnessCalculator: PhysiologicalCalculatorProtocol = PhysiologicalCalculator()) {
        self.healthKitManager = healthKitManager
        self.modelProvider = CoachModelProvider(injectedModel: aiModel)
        self.statusAnalyzer = CoachStatusAnalyzer(
            fitnessDataService: fitnessDataService,
            healthKitManager: healthKitManager,
            fitnessCalculator: fitnessCalculator
        )
    }

    // MARK: - Nutrition context (Epic 24)

    /// Epic 24 Sprint 1: Fetches the physiological profile via HealthKit and computes the
    /// nutrition plan for today's and tomorrow's workouts. Result is cached and injected.
    func refreshNutritionContext() async {
        let profileService = UserProfileService(healthStore: healthKitManager.healthStore)
        let profile = await profileService.fetchProfile()

        let todayWorkouts    = extractPlannedWorkouts(for: 0)
        let tomorrowWorkouts = extractPlannedWorkouts(for: 1)

        context.nutritionContext = NutritionService.buildCoachContext(
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

            let duration = workout.suggestedDurationMinutes > 0 ? workout.suggestedDurationMinutes : 45
            return (duration, zone)
        }
    }

    /// Removes the selected image from the input.
    func clearImage() {
        self.selectedImage = nil
    }

    // MARK: - Story 33.2b: Reset Schema

    /// Determines whether `updatePlan` or `mergeReplannedPlan` is used when a new plan comes
    /// back. Default `.replace` preserves the behaviour of requestRecoveryPlan / skipWorkout.
    private enum PlanUpdateMode {
        case replace
        case mergePreservingSwaps
    }
    private var pendingPlanUpdateMode: PlanUpdateMode = .replace

    /// Builds the context-prefix for the given invocation and consumes the one-time
    /// profile-update note (cleared after the build so the coach does not repeat it).
    private func buildContextPrefix(_ invocation: CoachInvocationContext) -> String {
        let prefix = CoachPromptAssembler.buildContextPrefix(
            context: context.snapshot(),
            profile: invocation.profile,
            activeGoals: invocation.activeGoals,
            activePreferences: invocation.activePreferences,
            workoutNotes: invocation.workoutNotesBlock,
            thresholdProfile: UserProfileService.cachedProfile()
        )
        context.profileUpdateNote = ""
        return prefix
    }

    // MARK: - Action requests

    /// Story 33.2b: asks the AI to re-plan the rest of the week around the manually moved
    /// sessions. The response is merged by `TrainingPlanManager.mergeReplannedPlan(_:)` so
    /// overrides are guaranteed to remain.
    func requestPlanReset(swappedWorkouts: [SuggestedWorkout],
                          invocation: CoachInvocationContext = .empty) {
        // Prevent parallel resets — isTyping catches most cases, but the mode flag too.
        guard !isTyping else { return }

        let (systemText, userText) = PlanResetPromptBuilder.build(swappedWorkouts: swappedWorkouts)
        pendingPlanUpdateMode = .mergePreservingSwaps
        sendHiddenSystemMessage(
            systemText: systemText,
            userText: userText,
            fallbackMessage: String(localized: "Ik heb je week opnieuw ingedeeld rondom je verplaatste sessies. Bekijk je overzicht."),
            invocation: invocation
        )
    }

    /// Asks the AI for a concrete recovery plan for goals that are behind. Injects the
    /// recovery context so the coach can directly produce an adjusted plan.
    func requestRecoveryPlan(atRiskGoals: [GoalRiskInfo], invocation: CoachInvocationContext = .empty) {
        guard !atRiskGoals.isEmpty else { return }

        let systemPrompt = CoachPromptAssembler.recoveryPlanSystemPrompt(
            atRiskGoals: atRiskGoals,
            vibeContext: context.todayVibeScoreContext,
            workoutNotes: invocation.workoutNotesBlock
        )

        // The text the user sees in the chat (concise and understandable)
        let goalTitles = atRiskGoals.map { "'\($0.title)'" }.joined(separator: " en ")
        let userFacingText = String(localized: "Los de achterstand op voor \(goalTitles) en geef me een bijgestuurd schema.")

        sendHiddenSystemMessage(
            systemText: systemPrompt,
            userText: userFacingText,
            fallbackMessage: String(localized: "Ik heb je herstelplan klaar! Bekijk je overzicht — het schema is bijgewerkt om je weer op schema te brengen."),
            invocation: invocation
        )
    }

    /// Handles rejecting (skipping) a specific suggested workout (Rest Day).
    func skipWorkout(_ workout: SuggestedWorkout, invocation: CoachInvocationContext = .empty) {
        let systemPrompt = "The user is skipping the workout '\(workout.activityType)' on \(workout.dateOrDay). Recompute the week and shift the load forward. IMPORTANT: In your JSON output always return the full 7-day schedule (including all unchanged other days), not just the adjusted day."
        let userFacingText = String(localized: "Ik sla de geplande \(workout.activityType) op \(workout.dateOrDay) over.")
        sendHiddenSystemMessage(systemText: systemPrompt, userText: userFacingText, invocation: invocation)
    }

    /// Handles the request for an alternative workout.
    func requestAlternativeWorkout(_ workout: SuggestedWorkout, invocation: CoachInvocationContext = .empty) {
        let systemPrompt = "The user doesn't like the planned workout '\(workout.activityType)' on \(workout.dateOrDay). Give an alternative for \(workout.dateOrDay) that provides a comparable training stimulus. IMPORTANT: In your JSON output always return the full 7-day schedule (including all unchanged other days), not just the adjusted day."
        let userFacingText = "Geef me een alternatief voor de \(workout.activityType) op \(workout.dateOrDay)."
        sendHiddenSystemMessage(systemText: systemPrompt, userText: userFacingText, invocation: invocation)
    }

    /// Sends a message where the UI shows a simple text, but the payload contains the
    /// technical prompt. If JSON parsing fails, `fallbackMessage` is shown instead of the
    /// raw AI text — so raw JSON never appears in the chat on hidden system calls.
    private func sendHiddenSystemMessage(
        systemText: String,
        userText: String,
        fallbackMessage: String = String(localized: "Ik heb je schema bijgewerkt! Bekijk je overzicht voor het nieuwe plan."),
        invocation: CoachInvocationContext = .empty
    ) {
        messages.append(ChatMessage(role: .user, text: userText))
        isTyping = true

        let contextPrefix = buildContextPrefix(invocation)
        let payloadText = "\(contextPrefix)\(systemText)"

        fetchAIResponse(for: payloadText, image: nil, fallbackMessage: fallbackMessage)
    }

    /// Sends the current text field (or the given text) and/or the selected image.
    func sendMessage(_ explicitText: String? = nil, invocation: CoachInvocationContext = .empty) {
        let textToUse = explicitText ?? inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageToSend = selectedImage?.downsample(to: 2048.0)

        guard !textToUse.isEmpty || imageToSend != nil else { return }
        // Prevent the user from sending a new message while the coach is still typing.
        guard !isTyping else { return }

        // 1. Create message from user for the UI (WITHOUT the invisible context prefix)
        let imageData = imageToSend?.jpegData(compressionQuality: 0.8)
        messages.append(ChatMessage(role: .user, text: textToUse, attachedImageData: imageData))

        isTyping = true
        inputText = ""
        clearImage()

        // 2. Build the final payload prompt
        let contextPrefix = buildContextPrefix(invocation)

        // Combine explicitly injected goals into user text if applicable for plain chat
        var finalUserText = textToUse
        let uncompletedGoals = invocation.activeGoals.filter { !$0.isCompleted }
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
    func retryLastMessage(invocation: CoachInvocationContext = .empty) {
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

        sendMessage(lastUserMessage.text, invocation: invocation)
    }

    // MARK: - Status analysis (HealthKit / Strava)

    /// Fetches the status via the selected source for the past X days (delegated to
    /// `CoachStatusAnalyzer`, which applies the source/fallback waterfall). On success the
    /// status prompt is assembled and sent invisibly; otherwise the analyzer's message shows.
    func analyzeCurrentStatus(days: Int = 7, invocation: CoachInvocationContext = .empty) {
        guard !isFetchingWorkout else { return }
        isFetchingWorkout = true

        Task {
            let outcome = await statusAnalyzer.fetchRecentWorkouts(days: days, source: selectedDataSource)
            switch outcome {
            case .workouts(let dailyWorkouts):
                let uiPrompt = CoachPromptAssembler.currentStatusPrompt(workouts: dailyWorkouts, days: days, activeGoals: invocation.activeGoals, storedPlanData: latestSuggestedPlanData)
                isTyping = true
                isFetchingWorkout = false
                let contextPrefix = buildContextPrefix(invocation)
                fetchAIResponse(for: "\(contextPrefix)\(uiPrompt)", image: nil)
            case .message(let text):
                messages.append(ChatMessage(role: .ai, text: text))
                isFetchingWorkout = false
            }
        }
    }

    // MARK: - AI request

    /// Sends the request asynchronously to the AI model with the correct content payload.
    ///
    /// - Parameter fallbackMessage: If JSON parsing fails (e.g. on hidden system calls), this
    ///   message is shown instead of the raw AI text — to prevent JSON becoming visible.
    func fetchAIResponse(for text: String, image: UIImage?, fallbackMessage: String? = nil) {
        // Epic 20: BYOK — block if no valid API key is configured. Exception: an injected
        // custom model (mock) skips the key check so tests don't fail on a missing key.
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

        // Epic #51-A2: snapshot the model names for THIS call so the UI can show the banner
        // if the user switches model during isTyping.
        activeRequestPrimaryModel = AIModelAppStorageKey.resolvedPrimary(for: currentProvider)
        activeRequestFallbackModel = AIModelAppStorageKey.resolvedFallback(for: currentProvider)

        // Epic #51-A6: clean up any previous Task should the user send a new question before
        // the previous one is back (defensive against a race condition → duplicate answers).
        currentRequestTask?.cancel()

        currentRequestTask = Task { [weak self] in
            guard let self = self else { return }
            var promptParts: [AIPromptPart] = []
            if !text.isEmpty {
                promptParts.append(.text(text))
            }
            if let image = image, let imageData = image.jpegData(compressionQuality: 0.8) {
                promptParts.append(.imageData(imageData, mimeType: "image/jpeg"))
            }

            // M-1: the assembled prompt is the entire PHI corpus — never log its content.
            // Log only a non-identifying length signal for debugging.
            AppLoggers.coach.debug("Prompt assembled (\(text.count, privacy: .public) chars)")

            // Waterfall: primary model first. On 503/429 (overload) we silently switch to the
            // fallback model — lighter by default, more often available during peaks. Other
            // errors (invalid key, blocked, network) fall straight through to the UI.
            var responseText: String?
            var finalError: Error?

            do {
                responseText = try await model.generateContent(promptParts)
            } catch {
                if AIProviderError.isOverload(error) {
                    retryStatusMessage = String(localized: "Model tijdelijk overbelast — overschakelen naar lichtere variant...")
                    let fallbackModel = modelProvider.fallbackModel()
                    do {
                        responseText = try await fallbackModel.generateContent(promptParts)
                    } catch {
                        finalError = error
                    }
                } else {
                    finalError = error
                }
            }

            retryStatusMessage = ""

            // Epic #51-A6: if the Task was cancelled meanwhile (user left the Coach tab or
            // sent a new question), do NOT show an error bubble — just reset typing state.
            if Task.isCancelled || finalError is CancellationError {
                self.isTyping = false
                self.currentRequestTask = nil
                self.activeRequestPrimaryModel = ""
                self.activeRequestFallbackModel = ""
                return
            }

            // Epic #51-A5: specific messages per error category via `ChatErrorMessageMapper`.
            if let error = finalError {
                let userFacingMessage = ChatErrorMessageMapper.userFacingMessage(for: error)
                messages.append(ChatMessage(role: .ai, text: userFacingMessage, isError: true))
                // Mirror in the banner state so screens without a visible chat also show feedback.
                lastAIErrorMessage = userFacingMessage
                isTyping = false
                self.currentRequestTask = nil
                self.activeRequestPrimaryModel = ""
                self.activeRequestFallbackModel = ""
                return
            }

            // M-1: the raw model response can echo PHI — log only a length signal.
            AppLoggers.coach.debug("Raw model response received (\(responseText?.count ?? 0, privacy: .public) chars)")

            let parsed = CoachResponseParser.parse(rawResponse: responseText, fallbackMessage: fallbackMessage)

            if let plan = parsed.plan {
                // Trigger callback if new preferences were found
                if let prefs = plan.newPreferences, !prefs.isEmpty {
                    onNewPreferencesDetected?(prefs)
                }

                // Update the central plan. Story 33.2b: on a reset it goes via
                // mergeReplannedPlan so moved sessions (`isSwapped`) stay leading.
                switch pendingPlanUpdateMode {
                case .replace:
                    trainingPlanManager?.updatePlan(plan)
                case .mergePreservingSwaps:
                    trainingPlanManager?.mergeReplannedPlan(plan)
                }
                // Always reset after one use — prevents a later chat message from staying in merge mode.
                pendingPlanUpdateMode = .replace

                // Store the motivation for the dashboard insight block
                if !parsed.motivation.isEmpty {
                    latestCoachInsight = parsed.motivation
                    context.lastAnalysisTimestamp = Date().timeIntervalSince1970
                }
            }

            messages.append(ChatMessage(role: .ai, text: parsed.motivation, suggestedPlan: parsed.plan))
            isTyping = false
            // Epic #51-A2/A6: housekeeping after successful completion.
            self.currentRequestTask = nil
            self.activeRequestPrimaryModel = ""
            self.activeRequestFallbackModel = ""
        }
    }

    /// Epic #51-A6: cancels a running AI call (e.g. when the user leaves the Coach tab during
    /// the spinner). A cancelled request must not feel like a failed call — no error bubble.
    func cancelOngoingRequest() {
        guard let task = currentRequestTask else { return }
        task.cancel()
        // Defensive: also reset the UI state synchronously so a re-rendering ChatView does not
        // briefly still show "Coach is aan het typen..." before the Task reaches cleanup.
        isTyping = false
        retryStatusMessage = ""
        currentRequestTask = nil
        activeRequestPrimaryModel = ""
        activeRequestFallbackModel = ""
    }

    /// Epic #51-A2: banner text that ChatView shows when the user switches model in Settings
    /// during an active answer. Returns `nil` while there is no change. Computed so it always
    /// reads fresh AppStorage (the snapshot lives on `activeRequestPrimary/FallbackModel`).
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
