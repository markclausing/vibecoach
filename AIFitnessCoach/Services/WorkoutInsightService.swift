import Foundation

// MARK: - Epic 32 Story 32.3b: WorkoutInsightService
//
// Generates a short coaching narrative for one workout based on the patterns
// from `WorkoutPatternDetector`. A separate service (instead of going through
// `ChatViewModel`) because it's a different AI role: per-workout physiological
// analysis, no training-plan adjustment and no JSON response. Its own system
// instruction keeps the prompt self-contained without polluting the chat-coach
// instruction.
//
// Reuse: `GenerativeModelProtocol` so unit tests can inject a mock.

final class WorkoutInsightService {

    enum InsightError: Error, LocalizedError, Equatable {
        case missingAPIKey
        case rateLimited(retried: Bool)
        case authenticationFailed
        case contentBlocked
        case timedOut(retried: Bool)
        case unavailable(retried: Bool, detail: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Geen API-sleutel ingesteld. Open Instellingen → AI Coach om er één toe te voegen."
            case .rateLimited(let retried):
                let suffix = retried ? " (primair én fallback-model)" : ""
                return "AI-quotum bereikt\(suffix). Probeer het over een paar minuten opnieuw."
            case .authenticationFailed:
                return "Je API-sleutel werkt niet. Controleer 'm in Instellingen → AI Coach."
            case .contentBlocked:
                return "AI heeft de analyse geblokkeerd om veiligheidsredenen."
            case .timedOut(let retried):
                let suffix = retried ? " (primair én fallback-model)" : ""
                return "AI reageert niet op tijd\(suffix). Probeer het zo opnieuw."
            case .unavailable(let retried, let detail):
                let prefix = retried ? "AI-analyse niet beschikbaar (primair én fallback-model gefaald)" : "AI-analyse niet beschikbaar"
                return "\(prefix). \(detail)"
            }
        }
    }

    /// System instruction. Deliberately a different register than the chat coach:
    /// here the coach is a physiological analyst who brings patterns together into
    /// a short narrative — no exercise schedule, no questions.
    /// Epic #44 update: reads session type and personal zones from the context so
    /// an intentional threshold/VO2max session isn't framed as "too hard"; only an
    /// unexpectedly high HR triggers a cautionary tone.
    /// Epic #52 update: hard rule that the analysis never ends with a question —
    /// this view has no chat function, so any open question would hang unanswered.
    /// Epic #37 story 37.3: computed so the reply-language directive reflects the current
    /// language preference at call time. The instruction body stays English (maintainability).
    private static var systemInstruction: String {
        let replyLanguage = AppLanguage.currentPromptLanguageName
        return """
    LANGUAGE — ABSOLUTE RULE: Write your entire analysis in \(replyLanguage), second person.
    The instructions below are in English for maintainability; your output to the user is always \(replyLanguage).

    You are a sports-physiology analyst who interprets patterns in a workout.

    You receive:
    - Patterns with severity (MILD/MODERATE/SIGNIFICANT) and numeric values
      (drift percentage, BPM drop, cadence drop).
    - Workout context: sport, duration, session type (recovery/endurance/tempo/threshold/
      vo2max), optionally the title.
    - The user's personal training thresholds (max HR, LTHR, FTP) and HR zones
      — use these to interpret "high" or "easy" correctly. An HR that is high for an
      average user may be normal Z2/Z3 for THIS user.

    **Important — no questions.** This analysis appears on a detail view without a
    chat function. NEVER ask the user a question (no calibration question, no open
    question about how it felt, no "was het warm?"). Always close with an observation,
    conclusion or finding. The user cannot reply here.

    Write at most 3 sentences that:
    1. Connect the patterns to the session type. A **threshold or vo2max session**
       where HR lands in Z4-Z5 is exactly the intent — frame that as an execution
       check ("je hebt X minuten in Z4 doorgebracht — netjes binnen het drempel-bereik"),
       never as a warning. The same applies to a title announcing interval/tempo/race.
    2. On a **mismatch** between session type and patterns (e.g. a "recovery" session
       that lands in Z4, or an "endurance" ride with heavy drift): name possible
       external factors (heat, sleep, oncoming illness, too ambitious a pace) and
       close with the most likely explanation as a statement — not as a question.
    3. On intentional high intensity without a mismatch: give an execution observation
       ("je hebt 18 minuten in je drempelzone doorgebracht — die intentie is geleverd").
       No calibration question, no cause hunt.

    **No patterns** detected? The ride was metrically fine — no drift, fade or slow
    recovery. Then write a short, **positive** execution confirmation based on
    duration, session type and any recovery events. E.g. "Een nette duurrit van 2 uur
    in je endurance-zone, met goed parasympatisch herstel tijdens je pauze." No worry
    questions, no aimless small talk — just briefly confirm what went well. Pick one
    concrete observation (zone behaviour, recovery, duration fit) and leave the rest out.

    **Recovery events** (pauses within the ride) are a separate signal layer. An
    "uitstekend" label = strong parasympathetic recovery; name it positively if it's
    relevant to the patterns. A "matig"/"slecht" label reinforces fatigue or heat
    suspicions from the patterns — use it as supporting evidence, not as a standalone
    pin. No recovery events = the ride had no rest window; don't mention it.

    **Goal status** and **periodization** (Epic #48): when present, explicitly connect
    the execution to the active goal and the current phase. For example "past in je
    Build-fase voor de marathon, en deze 32km nadert je 28km long-run-mijlpaal" or
    "goede tempo-sessie in je Peak-fase, nog 1 ✅ van de 4 om te halen". Don't list all
    blocks — pick one concrete link that supports your analysis. No active goal or no
    blueprint = don't mention it.

    **Weather during the workout** (Epic #49 + Epic #52): when a `[WEER TIJDENS
    WORKOUT]` block is present, explicitly weigh temperature and humidity as an
    explanation for drift, decoupling or elevated HR. Do NOT ask questions like "was
    het warm?" anymore — you already have that information. Thresholds: temperature
    >25°C or humidity >70% are relevant heat-stress bounds for cardiac drift. **On
    heat (>25°C) or high humidity (>70%) together with drift/decoupling: name the
    weather condition explicitly as a (co-)cause in your analysis — e.g. "Bij 28°C en
    72% luchtvochtigheid is een HR-drift van 6% verwacht; je conditie was niet de
    bottleneck."**

    **Range vs. snapshot (Epic #52):** With a **range** block you see peak + avg over
    the full workout window (e.g. "Piek 22°C, gem. 19°C; luchtvocht piek 94%, gem.
    88%"). Then use **the peak** as the lower bound for heat-stress evaluation — a ride
    that started at 9am at 15°C but ran up to a 22°C peak counts as a 22°C ride for
    heat analysis, not a 15°C ride. With a **snapshot** block (a single temperature
    and/or humidity without peak/avg context) that's a snapshot of ride start — reflect
    that implicitly by not drawing strong conclusions about heat impact on longer rides,
    unless that single reading is already > 25°C.

    On cooler weather (peak <15°C) and moderate drift: look for the cause elsewhere
    (fatigue, sleep, too ambitious a pace) and do NOT name cool weather as the
    explanation. No weather block = the iPhone recorded no metadata and there were no
    coords to query Open-Meteo; fall back to generic assumptions.

    **Cadence (Epic #52, running only):** With a `[CADENCE]` block you see avg and/or
    peak cadence in steps per minute (spm). Use this as one signal for running
    efficiency and fatigue, not as a normative judgement — there is no universal
    "ideal" (athletes run anywhere between 160 and 200 spm depending on conditions and
    build). Relevant observations:
    - **avg < 160 spm**: relatively low cadence; on longer rides overstriding may play
      a role, but only link it if there's also a corresponding pattern (cadence fade
      or decoupling). No standalone cadence nitpicking if the execution was otherwise clean.
    - **avg > 180 spm**: brisk, short steps; name it positively if the session also
      flowed well (no drift, good HR recovery).
    - **peak - avg > 20 spm**: there was a sprint or surge; mentionable if there was
      also an HR spike or interval structure from the session type. Not if the user
      did an easy endurance run — then it was probably a traffic-light restart or similar.
    No `[CADENCE]` block = no cadence data; do NOT ask for it.

    Style: \(replyLanguage), second person, no jargon without explanation, no lists or markdown.
    End without "Als je vragen hebt..." clichés. **Never end with a question mark** —
    this view has no chat. Close with a conclusion or observation.
    """
    }

    private let primaryFactory: () -> GenerativeModelProtocol?
    private let fallbackFactory: () -> GenerativeModelProtocol?

    /// Default factories build real Gemini models with the same system instruction;
    /// tests inject mocks. The fallback uses the lighter model — exactly the same
    /// strategy as `ChatViewModel.buildFallbackGenerativeModel()` so a 503/429 on
    /// the primary model doesn't immediately surface as a user error.
    init(primaryFactory: @escaping () -> GenerativeModelProtocol? = WorkoutInsightService.makePrimaryModel,
         fallbackFactory: @escaping () -> GenerativeModelProtocol? = WorkoutInsightService.makeFallbackModel) {
        self.primaryFactory = primaryFactory
        self.fallbackFactory = fallbackFactory
    }

    static func makePrimaryModel() -> GenerativeModelProtocol? {
        let provider = AIProvider.current()
        return makeModel(provider: provider, modelName: AIModelAppStorageKey.resolvedPrimary(for: provider))
    }

    static func makeFallbackModel() -> GenerativeModelProtocol? {
        let provider = AIProvider.current()
        return makeModel(provider: provider, modelName: AIModelAppStorageKey.resolvedFallback(for: provider))
    }

    private static func makeModel(provider: AIProvider, modelName: String) -> GenerativeModelProtocol? {
        let key = UserAPIKeyStore.read(for: provider)
        guard !key.isEmpty else { return nil }
        // Epic #53: provider-agnostic via the `AIModelFactory`. `jsonMode = false`
        // — the Coach analysis is free text, no JSON schema. Timeout 30s as before.
        // The key + model name belong to the active provider.
        return AIModelFactory.makeModel(
            provider: provider,
            modelName: modelName,
            systemInstruction: systemInstruction,
            jsonMode: false,
            timeout: 30,
            apiKey: key
        )
    }

    /// Workout context for the AI prompt. Fields are optional; whatever is unknown
    /// is simply omitted so the prompt isn't polluted with "unknown" or nil values.
    struct InsightContext {
        let sportLabel: String
        let durationMinutes: Int
        let sessionTypeLabel: String?
        let title: String?
        let zones: [HeartRateZone]?
        let maxHeartRate: Double?
        let lactateThresholdHR: Double?
        let ftp: Double?
        /// Epic #47: all detected pause-recovery events — positive ones too.
        /// Lets the coach frame good recovery positively, independent of the pin
        /// system (which only shows exceptions per §1).
        let recoveryEvents: [RecoveryEventSummary]
        /// Epic #48: blueprint status per active goal (title, weeks remaining,
        /// milestones ✅/❌). Output of `BlueprintContextFormatter.format(results:)`.
        /// nil/empty → block is dropped, coach doesn't mention goals.
        let goalsContext: String?
        /// Epic #48: periodization phase per goal (Base/Build/Peak/Taper) +
        /// success criteria. Joined `PeriodizationResult.coachingContext` blocks.
        let periodizationContext: String?
        /// Epic #49: ambient temperature (°C) and humidity (%) at the moment of
        /// the workout, from `HKMetadataKeyWeather*`. Both nil → block is dropped
        /// from the prompt and the coach falls back to generic assumptions about
        /// heat/dehydration. For records with GPS coords Epic #52 takes precedence
        /// (hourly range), but this snapshot remains the fallback path for HK-only
        /// rides without recorded coords.
        let temperatureCelsius: Double?
        let humidityPercent: Double?
        /// Epic #52: hourly weather aggregate over the full workout window.
        /// Peak (warmest hour during the ride) and average for both temperature
        /// and humidity. When present this range takes precedence over the
        /// snapshot — a 90-min run that started at 9:43 at 15°C but ran up to a
        /// 22°C peak is fairly evaluated as a 22°C ride.
        /// All subfields optional; nil → block is dropped.
        let peakTempCelsius: Double?
        let avgTempCelsius: Double?
        let peakHumidityPercent: Double?
        let avgHumidityPercent: Double?
        /// Epic #52: cadence (steps per minute) during a run. Average over
        /// non-zero samples (rest buckets excluded) + peak (95th percentile to
        /// flatten sprint spikes). Only present for running workouts; cycling
        /// cadence is not included in this prompt today. Both nil → block is dropped.
        let averageCadenceSPM: Double?
        let peakCadenceSPM: Double?

        init(sportLabel: String,
             durationMinutes: Int,
             sessionTypeLabel: String? = nil,
             title: String? = nil,
             zones: [HeartRateZone]? = nil,
             maxHeartRate: Double? = nil,
             lactateThresholdHR: Double? = nil,
             ftp: Double? = nil,
             recoveryEvents: [RecoveryEventSummary] = [],
             goalsContext: String? = nil,
             periodizationContext: String? = nil,
             temperatureCelsius: Double? = nil,
             humidityPercent: Double? = nil,
             peakTempCelsius: Double? = nil,
             avgTempCelsius: Double? = nil,
             peakHumidityPercent: Double? = nil,
             avgHumidityPercent: Double? = nil,
             averageCadenceSPM: Double? = nil,
             peakCadenceSPM: Double? = nil) {
            self.sportLabel = sportLabel
            self.durationMinutes = durationMinutes
            self.sessionTypeLabel = sessionTypeLabel
            self.title = title
            self.zones = zones
            self.maxHeartRate = maxHeartRate
            self.lactateThresholdHR = lactateThresholdHR
            self.ftp = ftp
            self.recoveryEvents = recoveryEvents
            self.goalsContext = goalsContext
            self.periodizationContext = periodizationContext
            self.temperatureCelsius = temperatureCelsius
            self.humidityPercent = humidityPercent
            self.peakTempCelsius = peakTempCelsius
            self.avgTempCelsius = avgTempCelsius
            self.peakHumidityPercent = peakHumidityPercent
            self.avgHumidityPercent = avgHumidityPercent
            self.averageCadenceSPM = averageCadenceSPM
            self.peakCadenceSPM = peakCadenceSPM
        }
    }

    /// Lightweight struct for the coach prompt. Contains only what the AI needs:
    /// duration (in seconds) and drop (BPM). The `qualityLabel` is derived by the
    /// caller from the drop ratio relative to referenceHR — this way the service
    /// itself holds no threshold knowledge.
    struct RecoveryEventSummary: Equatable {
        let durationSeconds: TimeInterval
        let drop: Double
        let qualityLabel: String
    }

    /// Generates a coaching narrative for the given patterns + workout context.
    /// Tries the primary model first; if it fails on a retryable error, an attempt
    /// on the fallback model follows automatically. This keeps the Coach analysis
    /// working during a temporary 503/429 on the primary model.
    func generateInsight(patterns: [WorkoutPattern],
                         context: InsightContext) async throws -> String {
        guard let primary = primaryFactory() else { throw InsightError.missingAPIKey }

        let prompt = buildPrompt(patterns: patterns, context: context)

        do {
            return try await callModel(primary, prompt: prompt)
        } catch {
            // Task cancellation = the view or a new call has superseded us.
            // Don't try the fallback (it would also be cancelled); pass on
            // CancellationError so the view can silently ignore it.
            if Self.isCancellation(error) { throw CancellationError() }

            // Authentication or content blocking is per-key/per-prompt; the fallback
            // won't fix that. Pass it on directly.
            if let mapped = mapError(error, retried: false), case .authenticationFailed = mapped {
                throw mapped
            }
            if let mapped = mapError(error, retried: false), case .contentBlocked = mapped {
                throw mapped
            }

            // Try the fallback. If it's also missing or fails, propagate the worst error.
            guard let fallback = fallbackFactory() else {
                throw mapError(error, retried: false) ?? .unavailable(retried: false, detail: error.localizedDescription)
            }
            do {
                return try await callModel(fallback, prompt: prompt)
            } catch {
                if Self.isCancellation(error) { throw CancellationError() }
                throw mapError(error, retried: true) ?? .unavailable(retried: true, detail: error.localizedDescription)
            }
        }
    }

    /// Detects SwiftUI/URLSession task cancellation in all the forms we encounter:
    /// a raw `CancellationError`, `URLError.cancelled`, or a `URLError.cancelled`
    /// wrapped inside `GenerateContentError.internalError(underlying:)`. We check
    /// `String(describing:)` as a last-resort net for the wrapped case.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let desc = String(describing: error)
        return desc.contains("Code=-999") || desc.contains("\"cancelled\"")
    }

    /// Internal for `@testable` visibility in `WorkoutInsightServiceTests`
    /// (Epic #48). Builds the complete prompt without actually making an API call —
    /// handy for unit-testing block conditions and formatting.
    func buildPrompt(patterns: [WorkoutPattern], context: InsightContext) -> String {
        let snippet = WorkoutPatternFormatter.promptSnippet(for: patterns) ?? ""

        var lines: [String] = ["Workout context:"]
        lines.append("- Sport: \(context.sportLabel)")
        lines.append("- Duration: \(context.durationMinutes) minutes")
        if let session = context.sessionTypeLabel {
            lines.append("- Session type (classifier): \(session)")
        }
        if let title = context.title, !title.isEmpty {
            lines.append("- Title: \"\(title)\"")
        }

        // Only add the thresholds block when at least one known value is set —
        // with no profile values the coach falls back to generic assumptions.
        var thresholdLines: [String] = []
        if let max = context.maxHeartRate { thresholdLines.append("- Max HR: \(Int(max)) BPM") }
        if let lthr = context.lactateThresholdHR { thresholdLines.append("- LTHR: \(Int(lthr)) BPM") }
        if let ftp = context.ftp { thresholdLines.append("- FTP: \(Int(ftp)) W") }
        if let zones = context.zones, !zones.isEmpty {
            for zone in zones {
                thresholdLines.append("- Z\(zone.index) \(zone.name): \(zone.lowerBPM)-\(zone.upperBPM) BPM")
            }
        }
        if !thresholdLines.isEmpty {
            lines.append("")
            lines.append("Personal training thresholds:")
            lines.append(contentsOf: thresholdLines)
        }

        lines.append("")
        lines.append("Detected patterns:")
        lines.append(snippet.isEmpty ? "No significant patterns detected — execution was within expectation." : snippet)

        // Epic #47: pass along pause-based recovery events — positive ones too.
        // The coach can then, on "how did my ride go?", name the excellent
        // recovery even when there's no pin. For mediocre recovery this reinforces
        // the pattern pin with the actual pause context.
        if !context.recoveryEvents.isEmpty {
            lines.append("")
            lines.append("Recovery events (per pause):")
            for event in context.recoveryEvents {
                let mins = Int(event.durationSeconds.rounded()) / 60
                let secs = Int(event.durationSeconds.rounded()) % 60
                let dur = String(format: "%d:%02d", mins, secs)
                lines.append("- pause of \(dur), HR dropped \(Int(event.drop.rounded())) BPM (\(event.qualityLabel))")
            }
        }

        // Epic #48: goals status (blueprint milestones per active goal) and
        // periodization (current phase + success criteria per goal). Both blocks
        // are omitted when empty/nil — the coach then falls back to pure
        // execution analysis without a goal link.
        if let goals = context.goalsContext, !goals.isEmpty {
            lines.append("")
            lines.append("[GOALS-STATUS]")
            lines.append(goals)
        }
        if let phase = context.periodizationContext, !phase.isEmpty {
            lines.append("")
            lines.append("[PERIODIZATION]")
            lines.append(phase)
        }

        // Epic #49 + #52: weather context during the workout. The range (hourly peak
        // + avg) takes precedence over the snapshot when present — a 90-min run thus
        // picks up the heat during the ride, not just the single point at ride start.
        // Only add it when at least one of the fields is available.
        let hasRange = context.peakTempCelsius != nil
            || context.avgTempCelsius != nil
            || context.peakHumidityPercent != nil
            || context.avgHumidityPercent != nil
        let hasSnapshot = context.temperatureCelsius != nil || context.humidityPercent != nil
        if hasRange {
            lines.append("")
            lines.append("[WEATHER DURING WORKOUT — range]")
            if let peak = context.peakTempCelsius, let avg = context.avgTempCelsius {
                lines.append("- Temperature: peak \(Int(peak.rounded()))°C, avg \(Int(avg.rounded()))°C")
            } else if let peak = context.peakTempCelsius {
                lines.append("- Temperature: peak \(Int(peak.rounded()))°C")
            } else if let avg = context.avgTempCelsius {
                lines.append("- Temperature: avg \(Int(avg.rounded()))°C")
            }
            if let peak = context.peakHumidityPercent, let avg = context.avgHumidityPercent {
                lines.append("- Humidity: peak \(Int(peak.rounded()))%, avg \(Int(avg.rounded()))%")
            } else if let peak = context.peakHumidityPercent {
                lines.append("- Humidity: peak \(Int(peak.rounded()))%")
            } else if let avg = context.avgHumidityPercent {
                lines.append("- Humidity: avg \(Int(avg.rounded()))%")
            }
        } else if hasSnapshot {
            lines.append("")
            lines.append("[WEATHER DURING WORKOUT — snapshot]")
            if let temp = context.temperatureCelsius {
                lines.append("- Temperature: \(Int(temp.rounded()))°C")
            }
            if let humidity = context.humidityPercent {
                lines.append("- Humidity: \(Int(humidity.rounded()))%")
            }
        }

        // Epic #52: cadence context for running. Only shown with at least one of
        // the two values — otherwise the block is silently dropped.
        if context.averageCadenceSPM != nil || context.peakCadenceSPM != nil {
            lines.append("")
            lines.append("[CADENCE]")
            if let avg = context.averageCadenceSPM {
                lines.append("- Avg cadence: \(Int(avg.rounded())) spm")
            }
            if let peak = context.peakCadenceSPM {
                lines.append("- Peak cadence: \(Int(peak.rounded())) spm")
            }
        }

        lines.append("")
        lines.append("Provide your analysis.")
        return lines.joined(separator: "\n")
    }

    private func callModel(_ model: GenerativeModelProtocol, prompt: String) async throws -> String {
        let response = try await model.generateContent([.text(prompt)])
        guard let text = response?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw InsightError.unavailable(retried: false, detail: "Lege respons van AI-model.")
        }
        return text
    }

    /// Maps SDK errors to user-friendly `InsightError` cases. Matches on the case
    /// name via `String(describing:)` (e.g. `promptBlockedError(...)`) plus on
    /// `localizedDescription` for URLError + non-Google errors. Logs the raw error
    /// to the console — if the UI shows "Onbekende AI-fout (...)", we can read the
    /// case name there and map it in a later round.
    private func mapError(_ error: Error, retried: Bool) -> InsightError? {
        let caseDescription = String(describing: error)
        let message = error.localizedDescription
        let combined = "\(caseDescription) \(message)".lowercased()

        AppLoggers.workoutInsight.error("AI-call failed (retried=\(retried, privacy: .public)): \(caseDescription, privacy: .public) | localized=\(message, privacy: .public)")

        // Epic #53: typed mapping for the non-Gemini REST clients (OpenAI/Claude/
        // Mistral) that throw `AIProviderError`. Goes before the string matching so
        // we don't depend on the string representation.
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .overloaded:
                return .rateLimited(retried: retried)
            case .authenticationFailed:
                return .authenticationFailed
            case .contentBlocked:
                return .contentBlocked
            case .http(let status, let message):
                let suffix = message.map { " — \($0)" } ?? ""
                return .unavailable(retried: retried, detail: "AI-provider gaf HTTP \(status) terug.\(suffix)")
            case .emptyResponse:
                return .unavailable(retried: retried, detail: "Lege respons van AI-model.")
            case .decodingFailed:
                return .unavailable(retried: retried, detail: "Onverwacht antwoordformaat van de AI-provider.")
            }
        }

        // Specific Google-SDK cases — the case name is more stable than localized text.
        if combined.contains("invalidapikey") || combined.contains("api key") || combined.contains("unauthenticated") || combined.contains("unauthorized") {
            return .authenticationFailed
        }
        if combined.contains("promptblocked") || combined.contains("blocked") || combined.contains("safety") || combined.contains("harm") {
            return .contentBlocked
        }
        if combined.contains("quota") || combined.contains("rate") || combined.contains("429") || combined.contains("resource_exhausted") {
            return .rateLimited(retried: retried)
        }
        if combined.contains("timed out") || combined.contains("timeout") || (error as? URLError)?.code == .timedOut {
            return .timedOut(retried: retried)
        }
        if combined.contains("internalerror") || combined.contains("503") || combined.contains("server error") {
            return .unavailable(retried: retried, detail: "Google AI-server gaf een interne fout terug — meestal tijdelijk, probeer over een paar minuten opnieuw.")
        }
        if combined.contains("responsestoppedearly") {
            return .unavailable(retried: retried, detail: "AI stopte de respons voortijdig — pull-to-refresh om opnieuw te proberen.")
        }
        // Unknown case: return the raw case name so we can read it in the UI and
        // map it explicitly in a later iteration.
        return .unavailable(retried: retried, detail: "Onbekende AI-fout — \(caseDescription)")
    }
}
