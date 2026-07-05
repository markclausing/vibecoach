import Foundation

/// Epic #70 story 70.3: orchestration of the per-workout chat ("Discuss this workout").
///
/// Deliberately SwiftData-free (§6): the view model owns the transient chat state and
/// the AI call; persistence flows through two callbacks owned by the SwiftData-owning
/// view (`WorkoutChatSection`) — the same split as `ChatViewModel` +
/// `onNewPreferencesDetected`. That keeps this class fully unit-testable with a
/// `MockGenerativeModel` and no model container.
///
/// The AI plumbing (lazy model cache, key resolution, `-UITesting` mock, overload
/// fallback waterfall) is reused from `CoachModelProvider`, with the narrower
/// `WorkoutChatScopeInstruction` injected as the system instruction.
@MainActor
final class WorkoutChatViewModel: ObservableObject {

    // MARK: - Workout identity

    /// The workout snapshot the chat is anchored to. A value type (not the
    /// `ActivityRecord` @Model) so the view model stays SwiftData-free.
    struct WorkoutInfo: Equatable {
        let activityID: String
        let name: String
        let date: Date
        let sportRaw: String
        let sessionTypeLabel: String?
        let trimp: Double?
        let movingTimeMinutes: Int
        let averageHeartrate: Double?
        let rpe: Int?
        let mood: String?
    }

    // MARK: - Published state

    @Published var messages: [ChatMessage] = []
    @Published var isTyping = false

    // MARK: - Persistence callbacks (owned by the SwiftData-owning view)

    /// Fired for every message that should be persisted as a `WorkoutChatEntry`
    /// (user messages and successful AI replies — error bubbles are transient).
    var onMessagePersisted: ((SenderRole, String, Date) -> Void)?
    /// Fired when the model distilled facts worth remembering. The view dedupes
    /// (containment check) and inserts `WorkoutChatFact`s.
    var onNewFactsDetected: (([WorkoutChatResponseParser.DistilledFact]) -> Void)?

    // MARK: - Private

    private let workout: WorkoutInfo
    private let modelProvider: CoachModelProvider
    private var currentRequestTask: Task<Void, Never>?

    /// - Parameters:
    ///   - workout: Snapshot of the workout this chat is anchored to.
    ///   - aiModel: Injected mock for tests; nil builds the real provider lazily.
    init(workout: WorkoutInfo, aiModel: GenerativeModelProtocol? = nil) {
        self.workout = workout
        self.modelProvider = CoachModelProvider(
            injectedModel: aiModel,
            systemInstructionBuilder: {
                WorkoutChatScopeInstruction.text(
                    workoutName: workout.name,
                    workoutDate: workout.date,
                    sportRaw: workout.sportRaw,
                    sessionTypeLabel: workout.sessionTypeLabel
                )
            }
        )
    }

    /// True if a usable API key is configured (or a mock is injected).
    var hasAPIKey: Bool { modelProvider.hasAPIKey }

    /// Seeds the in-memory thread from the persisted `WorkoutChatEntry`s. Idempotent:
    /// only seeds an empty thread, so a view re-appear doesn't duplicate messages.
    func loadHistory(_ entries: [(role: SenderRole, text: String, timestamp: Date)]) {
        guard messages.isEmpty else { return }
        messages = entries.map { ChatMessage(role: $0.role, text: $0.text, timestamp: $0.timestamp) }
    }

    // MARK: - Send

    /// Sends a user message about this workout.
    /// - Parameters:
    ///   - rawText: The user's input (clamped via `ChatInputValidator`).
    ///   - existingFactTexts: Current `WorkoutChatFact` texts for this workout,
    ///     injected per send by the view (they change as chips are deleted).
    func sendMessage(_ rawText: String, existingFactTexts: [String]) {
        let text = ChatInputValidator.clamp(rawText).clamped
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // BYOK gate, same exception as ChatViewModel: injected mocks skip the check.
        if modelProvider.model is RealAIProviderClient, !hasAPIKey {
            messages.append(ChatMessage(role: .ai,
                                        text: String(localized: "Je AI Coach slaapt. Voer een API-sleutel in via de Instellingen om hem wakker te maken."),
                                        isError: true))
            return
        }

        let now = Date()
        messages.append(ChatMessage(role: .user, text: text, timestamp: now))
        onMessagePersisted?(.user, text, now)
        isTyping = true

        // Defensive against double-sends: a new question supersedes the in-flight one.
        currentRequestTask?.cancel()
        currentRequestTask = Task { [weak self] in
            guard let self else { return }
            let prompt = self.buildPrompt(question: text, existingFactTexts: existingFactTexts)
            // M-1: the prompt embeds workout + condition data — log only a length signal.
            AppLoggers.coach.debug("Workout-chat prompt assembled (\(prompt.count, privacy: .public) chars)")

            // Waterfall: primary model first; on overload silently retry on the
            // lighter fallback. Other errors surface via ChatErrorMessageMapper.
            var responseText: String?
            var finalError: Error?
            do {
                responseText = try await self.modelProvider.model.generateContent([.text(prompt)])
            } catch {
                if AIProviderError.isOverload(error) {
                    do {
                        responseText = try await self.modelProvider.fallbackModel().generateContent([.text(prompt)])
                    } catch {
                        finalError = error
                    }
                } else {
                    finalError = error
                }
            }

            if Task.isCancelled || finalError is CancellationError {
                self.isTyping = false
                return
            }

            if let error = finalError {
                // Transient error bubble — shown, not persisted.
                let userFacingMessage = ChatErrorMessageMapper.userFacingMessage(for: error)
                self.messages.append(ChatMessage(role: .ai, text: userFacingMessage, isError: true))
                self.isTyping = false
                return
            }

            let parsed = WorkoutChatResponseParser.parse(
                rawResponse: responseText,
                fallbackMessage: String(localized: "Ik kon de reactie niet verwerken. Probeer het opnieuw.")
            )
            let replyDate = Date()
            self.messages.append(ChatMessage(role: .ai, text: parsed.reply, timestamp: replyDate))
            self.onMessagePersisted?(.ai, parsed.reply, replyDate)
            if !parsed.facts.isEmpty {
                self.onNewFactsDetected?(parsed.facts)
            }
            self.isTyping = false
        }
    }

    // MARK: - Prompt assembly

    /// Number of trailing thread messages included per request — enough for local
    /// conversational context without ballooning the prompt.
    private static let promptHistoryLimit = 12

    /// Builds the single text part for one request: workout data + remembered facts
    /// + recent thread + the new question. The `[WORKOUT DATA]` / `[REMEMBERED FACTS]`
    /// markers are local to this feature (emitted here, described in
    /// `WorkoutChatScopeInstruction`) — keep both sides identical (§13).
    private func buildPrompt(question: String, existingFactTexts: [String]) -> String {
        var blocks: [String] = []

        var dataLines = ["[WORKOUT DATA]"]
        let dateStr = AppDateFormatters.promptStyle(.medium).string(from: workout.date)
        var identity = "- \(workout.name) — \(workout.sportRaw), \(dateStr)"
        if let session = workout.sessionTypeLabel { identity += ", session type: \(session)" }
        dataLines.append(identity)
        var metrics: [String] = []
        if let trimp = workout.trimp { metrics.append("TRIMP \(String(format: "%.0f", trimp))") }
        metrics.append("duration \(workout.movingTimeMinutes) min")
        if let hr = workout.averageHeartrate { metrics.append("avg HR \(String(format: "%.0f", hr)) BPM") }
        dataLines.append("- " + metrics.joined(separator: ", "))
        if workout.rpe != nil || workout.mood != nil {
            let rpeStr  = workout.rpe.map { "RPE \($0)/10" }
            let moodStr = workout.mood.map { "mood \($0)" }
            dataLines.append("- Check-in: " + [rpeStr, moodStr].compactMap { $0 }.joined(separator: ", "))
        }
        blocks.append(dataLines.joined(separator: "\n"))

        if !existingFactTexts.isEmpty {
            let factLines = ["[REMEMBERED FACTS]"] + existingFactTexts.map { "- \($0)" }
            blocks.append(factLines.joined(separator: "\n"))
        }

        // Trailing conversation (excluding the just-appended user message, re-added
        // below as the explicit question). Error bubbles are UI-only — skip them.
        let history = messages.dropLast().filter { !$0.isError }.suffix(Self.promptHistoryLimit)
        if !history.isEmpty {
            let historyLines = ["[CONVERSATION]"] + history.map { message in
                "\(message.role == .user ? "user" : "coach"): \(message.text)"
            }
            blocks.append(historyLines.joined(separator: "\n"))
        }

        blocks.append("user: \(question)")
        return blocks.joined(separator: "\n\n")
    }
}
