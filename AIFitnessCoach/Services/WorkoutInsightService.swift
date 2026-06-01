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
    private static let systemInstruction: String = """
    Je bent een sportfysiologisch analist die patronen in een workout interpreteert.

    Je ontvangt:
    - Patronen met severity (MILD/MODERATE/SIGNIFICANT) en numerieke waardes
      (drift-percentage, BPM-drop, cadence-daling).
    - Workout-context: sport, duur, sessie-type (recovery/endurance/tempo/threshold/
      vo2max), eventueel de titel.
    - Persoonlijke trainingsdrempels van de gebruiker (max-HR, LTHR, FTP) en HR-zones
      — gebruik deze om "hoog" of "rustig" correct te interpreteren. Een HR die
      voor een gemiddelde gebruiker hoog is, kan voor déze gebruiker normaal Z2/Z3 zijn.

    **Belangrijk — geen vragen.** Deze analyse verschijnt op een detail-view zonder
    chat-functie. Stel **nooit** een vraag aan de gebruiker (geen kalibratie-vraag,
    geen open vraag over hoe het voelde, geen "was het warm?"). Sluit altijd af met
    een observatie, conclusie of vaststelling. De gebruiker kan hier niet antwoorden.

    Schrijf max. 3 zinnen die:
    1. De patronen verbinden met het sessie-type. Een **threshold- of vo2max-sessie**
       waarbij HR in Z4-Z5 belandt is precies wat de bedoeling was — frame dat als
       uitvoerings-check ("je hebt X minuten in Z4 doorgebracht — netjes binnen het
       drempel-bereik"), nooit als waarschuwing. Hetzelfde geldt voor een titel die
       intervaltraining/tempo/race aankondigt.
    2. Bij een **mismatch** tussen sessie-type en patronen (bv. "recovery"-sessie die
       in Z4 belandt, of een "endurance"-rit met zware drift): noem mogelijke
       externe factoren (hitte, slaap, beginnende ziekte, te ambitieus tempo gekozen)
       en sluit af met de meest waarschijnlijke verklaring als statement — niet
       als vraag.
    3. Bij intentionele hoge intensiteit zonder mismatch: geef een uitvoerings-
       observatie ("je hebt 18 minuten in je drempelzone doorgebracht — die intentie
       is geleverd"). Geen kalibratie-vraag, geen oorzaak-zoektocht.

    **Geen patronen** gedetecteerd? De rit was metrisch in orde — geen drift, fade
    of trage recovery. Schrijf dan een korte, **positieve** uitvoerings-bevestiging
    op basis van duur, sessie-type en eventuele recovery-events. Bijv. "Een nette
    duurrit van 2 uur in je endurance-zone, met goed parasympatisch herstel tijdens
    je pauze." Geen zorgen-vragen, geen doelloze koetjes-en-kalfjes — gewoon kort
    bevestigen wat goed ging. Kies één concrete observatie (zone-gedrag, recovery,
    duur-passendheid) en laat de rest weg.

    **Recovery-events** (pauzes binnen de rit) zijn een aparte signaal-laag. Een
    "uitstekend"-label = sterk parasympatisch herstel; benoem dat positief als het
    relevant is voor de patronen. Een "matig"/"slecht"-label versterkt vermoeidheids-
    of hitte-vermoedens uit de patronen — gebruik het als ondersteunend bewijs, niet
    als losstaande pin. Geen recovery-events = de rit had geen rust-window; benoem
    het niet.

    **Doelen-status** en **periodisering** (Epic #48): wanneer aanwezig, verbind
    de uitvoering expliciet met het actieve doel en de huidige fase. Bijvoorbeeld
    "past in je Build-fase voor de marathon, en deze 32km nadert je 28km long-run-
    mijlpaal" of "goede tempo-sessie in je Peak-fase, nog 1 ✅ van de 4 om te halen".
    Niet alle blocks opsommen — kies één concrete koppeling die je analyse
    onderbouwt. Geen actief doel of geen blueprint = niet noemen.

    **Weer tijdens de workout** (Epic #49 + Epic #52): wanneer een `[WEER TIJDENS
    WORKOUT]`-blok aanwezig is, weeg temperatuur en luchtvochtigheid expliciet mee
    als verklaring voor drift, decoupling of verhoogde HR. Stel **geen** vragen
    meer als "was het warm?" — die informatie heb je al. Drempels: temperatuur
    >25°C of luchtvochtigheid >70% zijn relevante hitte-stress-grenzen voor
    cardiale drift. **Bij hitte (>25°C) of hoge luchtvochtigheid (>70%) samen
    met drift/decoupling: noem de weersconditie expliciet als (mede-)oorzaak in
    je analyse — bijv. "Bij 28°C en 72% luchtvochtigheid is een HR-drift van 6%
    verwacht; je conditie was niet de bottleneck."**

    **Range vs. snapshot (Epic #52):** Bij een **range**-blok zie je piek + gem.
    over het volledige workout-venster (bv. "Piek 22°C, gem. 19°C; luchtvocht
    piek 94%, gem. 88%"). Gebruik dan **de piek** als ondergrens voor hitte-
    stress-evaluatie — een rit die om 9u bij 15°C begon maar onderweg naar 22°C
    piek liep, telt voor hitte-analyse als een 22°C-rit, niet als een 15°C-rit.
    Bij een **snapshot**-blok (één temperatuur en/of luchtvochtigheid zonder
    piek/gem.-context) is dat een momentopname van rit-start — vermeld dat
    impliciet door geen sterke conclusies te trekken over hitte-impact bij
    langere ritten, tenzij die ene meting al > 25°C is.

    Bij koeler weer (piek <15°C) en matige drift: zoek de oorzaak elders
    (vermoeidheid, slaap, te ambitieus tempo) en noem koel weer **niet** als
    verklaring. Geen weer-blok = de iPhone heeft geen metadata vastgelegd en er
    waren geen coords om Open-Meteo te bevragen; val terug op generieke aannames.

    **Cadens (Epic #52, alleen running):** Bij een `[CADENS]`-blok zie je gem.
    en/of piek-cadens in steps per minute (spm). Gebruik dit als één signaal
    voor loop-efficiëntie en vermoeidheid, niet als normatief oordeel — er is
    geen universeel "ideaal" (atleten lopen overal tussen 160 en 200 spm naar
    omstandigheden en lichaamsbouw). Relevante observaties:
    - **gem. < 160 spm**: relatief lage cadens; bij langere ritten kan
      overstride een rol spelen, maar koppel het alléén als er ook een
      bijbehorende pattern is (cadence fade of decoupling). Geen losse
      cadens-bemoeienis als de uitvoering verder schoon was.
    - **gem. > 180 spm**: vlotte, korte stappen; benoem het positief als de
      sessie ook fluent verliep (geen drift, goede HR-recovery).
    - **piek - gem. > 20 spm**: er zat een sprintje of versnelling in;
      benoembaar als er ook een HR-spike of intervalstructuur uit het sessie-
      type bleek. Niet als de gebruiker een rustige duurloop deed — dan was
      het waarschijnlijk verkeerslicht-restart of vergelijkbaar.
    Geen `[CADENS]`-blok = geen cadens-data; vraag er **niet** naar.

    Stijl: Nederlandstalig, tweede persoon, geen jargon zonder uitleg, geen lijsten of
    markdown. Eindig zonder "Als je vragen hebt..."-clichés. **Eindig nooit met een
    vraagteken** — deze view heeft geen chat. Sluit af met een conclusie of observatie.
    """

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

        var lines: [String] = ["Workout-context:"]
        lines.append("- Sport: \(context.sportLabel)")
        lines.append("- Duur: \(context.durationMinutes) minuten")
        if let session = context.sessionTypeLabel {
            lines.append("- Sessie-type (classifier): \(session)")
        }
        if let title = context.title, !title.isEmpty {
            lines.append("- Titel: \"\(title)\"")
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
            lines.append("Persoonlijke trainingsdrempels:")
            lines.append(contentsOf: thresholdLines)
        }

        lines.append("")
        lines.append("Gedetecteerde patronen:")
        lines.append(snippet.isEmpty ? "Geen significante patronen gedetecteerd — uitvoering was binnen verwachting." : snippet)

        // Epic #47: pass along pause-based recovery events — positive ones too.
        // The coach can then, on "how did my ride go?", name the excellent
        // recovery even when there's no pin. For mediocre recovery this reinforces
        // the pattern pin with the actual pause context.
        if !context.recoveryEvents.isEmpty {
            lines.append("")
            lines.append("Recovery-events (per pauze):")
            for event in context.recoveryEvents {
                let mins = Int(event.durationSeconds.rounded()) / 60
                let secs = Int(event.durationSeconds.rounded()) % 60
                let dur = String(format: "%d:%02d", mins, secs)
                lines.append("- pauze van \(dur), HR daalde \(Int(event.drop.rounded())) BPM (\(event.qualityLabel))")
            }
        }

        // Epic #48: goals status (blueprint milestones per active goal) and
        // periodization (current phase + success criteria per goal). Both blocks
        // are omitted when empty/nil — the coach then falls back to pure
        // execution analysis without a goal link.
        if let goals = context.goalsContext, !goals.isEmpty {
            lines.append("")
            lines.append("[DOELEN-STATUS]")
            lines.append(goals)
        }
        if let phase = context.periodizationContext, !phase.isEmpty {
            lines.append("")
            lines.append("[PERIODISERING]")
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
            lines.append("[WEER TIJDENS WORKOUT — range]")
            if let peak = context.peakTempCelsius, let avg = context.avgTempCelsius {
                lines.append("- Temperatuur: piek \(Int(peak.rounded()))°C, gem. \(Int(avg.rounded()))°C")
            } else if let peak = context.peakTempCelsius {
                lines.append("- Temperatuur: piek \(Int(peak.rounded()))°C")
            } else if let avg = context.avgTempCelsius {
                lines.append("- Temperatuur: gem. \(Int(avg.rounded()))°C")
            }
            if let peak = context.peakHumidityPercent, let avg = context.avgHumidityPercent {
                lines.append("- Luchtvochtigheid: piek \(Int(peak.rounded()))%, gem. \(Int(avg.rounded()))%")
            } else if let peak = context.peakHumidityPercent {
                lines.append("- Luchtvochtigheid: piek \(Int(peak.rounded()))%")
            } else if let avg = context.avgHumidityPercent {
                lines.append("- Luchtvochtigheid: gem. \(Int(avg.rounded()))%")
            }
        } else if hasSnapshot {
            lines.append("")
            lines.append("[WEER TIJDENS WORKOUT — snapshot]")
            if let temp = context.temperatureCelsius {
                lines.append("- Temperatuur: \(Int(temp.rounded()))°C")
            }
            if let humidity = context.humidityPercent {
                lines.append("- Luchtvochtigheid: \(Int(humidity.rounded()))%")
            }
        }

        // Epic #52: cadence context for running. Only shown with at least one of
        // the two values — otherwise the block is silently dropped.
        if context.averageCadenceSPM != nil || context.peakCadenceSPM != nil {
            lines.append("")
            lines.append("[CADENS]")
            if let avg = context.averageCadenceSPM {
                lines.append("- Gem. cadens: \(Int(avg.rounded())) spm")
            }
            if let peak = context.peakCadenceSPM {
                lines.append("- Piek-cadens: \(Int(peak.rounded())) spm")
            }
        }

        lines.append("")
        lines.append("Geef je analyse.")
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
