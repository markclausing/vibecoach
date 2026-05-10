import Foundation
import GoogleGenerativeAI

// MARK: - Epic 32 Story 32.3b: WorkoutInsightService
//
// Genereert een korte coaching-narrative bij één workout op basis van de patronen
// uit `WorkoutPatternDetector`. Aparte service (i.p.v. via `ChatViewModel`)
// omdat het een andere AI-rol is: per-workout fysiologische analyse, géén
// trainingsplan-aanpassing en géén JSON-respons. Eigen system-instruction
// houdt de prompt hier rond, zonder de chat-coach-instructie te vervuilen.
//
// Reuse: `GenerativeModelProtocol` zodat unit tests een mock kunnen injecteren.

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

    /// System-instruction. Bewust ander register dan de chat-coach: hier is de
    /// coach een fysiologisch analist die patronen samenbrengt tot een kort
    /// verhaal — geen oefenschema, geen vragen.
    /// Epic #44 update: leest sessie-type en persoonlijke zones uit de context
    /// zodat een opzettelijke threshold-/VO2max-sessie niet als "te hard" wordt
    /// geframed; alleen onverwacht hoge HR triggert een waarschuwende toon.
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

    Schrijf max. 3 zinnen die:
    1. De patronen verbinden met het sessie-type. Een **threshold- of vo2max-sessie**
       waarbij HR in Z4-Z5 belandt is precies wat de bedoeling was — frame dat als
       uitvoerings-check ("je hebt X minuten in Z4 doorgebracht — netjes binnen het
       drempel-bereik"), nooit als waarschuwing. Hetzelfde geldt voor een titel die
       intervaltraining/tempo/race aankondigt.
    2. Bij een **mismatch** tussen sessie-type en patronen (bv. "recovery"-sessie die
       in Z4 belandt, of een "endurance"-rit met zware drift): wijs op mogelijke
       externe factoren (hitte, slaap, beginnende ziekte, te ambitieus tempo gekozen).
       Eindig met een open vraag.
    3. Bij intentionele hoge intensiteit zonder mismatch: stel een kalibratie-vraag
       ("voelde dit als drempelwerk of zat er nog ruimte?"), geen oorzaak-zoektocht.

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

    **Weer tijdens de workout** (Epic #49): wanneer een `[WEER TIJDENS WORKOUT]`-
    blok aanwezig is, weeg temperatuur en luchtvochtigheid expliciet mee als
    verklaring voor drift, decoupling of verhoogde HR. Stel **geen** vragen
    meer als "was het warm?" — die informatie heb je al. Drempels: temperatuur
    >25°C of luchtvochtigheid >70% zijn relevante hitte-stress-grenzen voor
    cardiale drift. Bij koeler weer (<15°C) en matige drift: zoek de oorzaak
    elders (vermoeidheid, slaap, te ambitieus tempo). Geen weer-blok = de
    iPhone heeft geen metadata vastgelegd; vraag er **niet** naar, val terug
    op generieke aannames.

    Stijl: Nederlandstalig, tweede persoon, geen jargon zonder uitleg, geen lijsten of
    markdown. Eindig zonder "Als je vragen hebt..."-clichés.
    """

    private let primaryFactory: () -> GenerativeModelProtocol?
    private let fallbackFactory: () -> GenerativeModelProtocol?

    /// Default factories bouwen echte Gemini-modellen met dezelfde system-instruction;
    /// tests injecteren mocks. Fallback gebruikt het lichtere model — exact dezelfde
    /// strategie als `ChatViewModel.buildFallbackGenerativeModel()` zodat 503/429 op
    /// het primaire model niet meteen tot een gebruikersfout leidt.
    init(primaryFactory: @escaping () -> GenerativeModelProtocol? = WorkoutInsightService.makePrimaryModel,
         fallbackFactory: @escaping () -> GenerativeModelProtocol? = WorkoutInsightService.makeFallbackModel) {
        self.primaryFactory = primaryFactory
        self.fallbackFactory = fallbackFactory
    }

    static func makePrimaryModel() -> GenerativeModelProtocol? {
        makeModel(modelName: AIModelAppStorageKey.resolvedPrimary())
    }

    static func makeFallbackModel() -> GenerativeModelProtocol? {
        makeModel(modelName: AIModelAppStorageKey.resolvedFallback())
    }

    private static func makeModel(modelName: String) -> GenerativeModelProtocol? {
        let key = UserAPIKeyStore.read()
        guard !key.isEmpty else { return nil }
        let config = GenerationConfig()
        let options = RequestOptions(timeout: 30)
        let googleModel = GenerativeModel(
            name: modelName,
            apiKey: key,
            generationConfig: config,
            systemInstruction: ModelContent(role: "system", parts: [.text(systemInstruction)]),
            requestOptions: options
        )
        return RealGenerativeModel(model: googleModel)
    }

    /// Workout-context voor de AI-prompt. Velden zijn optioneel; wat onbekend
    /// is wordt simpelweg weggelaten zodat de prompt niet wordt vervuild met
    /// "onbekend" of nil-waarden.
    struct InsightContext {
        let sportLabel: String
        let durationMinutes: Int
        let sessionTypeLabel: String?
        let title: String?
        let zones: [HeartRateZone]?
        let maxHeartRate: Double?
        let lactateThresholdHR: Double?
        let ftp: Double?
        /// Epic #47: alle gedetecteerde pauze-recovery-events — ook positieve.
        /// Stelt de coach in staat om bij goede recovery positief te framen,
        /// los van het pin-systeem (dat alleen exceptions toont conform §1).
        let recoveryEvents: [RecoveryEventSummary]
        /// Epic #48: blueprint-status per actief doel (titel, weken-resterend,
        /// milestones ✅/❌). Output van `BlueprintContextFormatter.format(results:)`.
        /// nil/leeg → blok valt weg, coach noemt doelen niet.
        let goalsContext: String?
        /// Epic #48: periodisatie-fase per doel (Base/Build/Peak/Taper) +
        /// succescriteria. Joined `PeriodizationResult.coachingContext`-blokken.
        let periodizationContext: String?
        /// Epic #49: omgevings-temperatuur (°C) en luchtvochtigheid (%) op het
        /// moment van de workout, uit `HKMetadataKeyWeather*`. Beide nil → blok
        /// valt weg uit de prompt en de coach valt terug op generieke aannames
        /// over hitte/dehydratie.
        let temperatureCelsius: Double?
        let humidityPercent: Double?

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
             humidityPercent: Double? = nil) {
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
        }
    }

    /// Lichte struct voor de coach-prompt. Bevat alleen wat de AI nodig heeft:
    /// duur (in seconden) en drop (BPM). De `qualityLabel` wordt door de caller
    /// afgeleid uit de drop-ratio relatief aan referenceHR — zo houdt de service
    /// zelf geen drempel-kennis bij zich.
    struct RecoveryEventSummary: Equatable {
        let durationSeconds: TimeInterval
        let drop: Double
        let qualityLabel: String
    }

    /// Genereert een coaching-narrative voor de meegeleverde patronen + workout-context.
    /// Probeert eerst het primaire model; faalt dat op een retryable fout, dan
    /// volgt automatisch een poging op het fallback-model. Zo blijft de Coach-analyse
    /// werken bij een tijdelijke 503/429 op het primaire model.
    func generateInsight(patterns: [WorkoutPattern],
                         context: InsightContext) async throws -> String {
        guard let primary = primaryFactory() else { throw InsightError.missingAPIKey }

        let prompt = buildPrompt(patterns: patterns, context: context)

        do {
            return try await callModel(primary, prompt: prompt)
        } catch {
            // Task-cancellation = de view of een nieuwe call heeft ons gepasseerd.
            // Geen fallback proberen (zou ook gecancelled worden), CancellationError
            // doorgeven zodat de view 'm stilletjes kan negeren.
            if Self.isCancellation(error) { throw CancellationError() }

            // Authenticatie of content-blocking is per-key/per-prompt; de fallback gaat
            // dat niet oplossen. Direct doorgeven.
            if let mapped = mapError(error, retried: false), case .authenticationFailed = mapped {
                throw mapped
            }
            if let mapped = mapError(error, retried: false), case .contentBlocked = mapped {
                throw mapped
            }

            // Probeer fallback. Als die ook ontbreekt of valt, propageer de zwaarste fout.
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

    /// Detecteert SwiftUI/URLSession task-cancellation in alle vormen die we tegenkomen:
    /// rauwe `CancellationError`, `URLError.cancelled`, of een `URLError.cancelled` die
    /// in `GenerateContentError.internalError(underlying:)` ingewikkeld zit. We checken
    /// op `String(describing:)` als laatste vangnet voor het ingewikkelde geval.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let desc = String(describing: error)
        return desc.contains("Code=-999") || desc.contains("\"cancelled\"")
    }

    /// Internal voor `@testable` zichtbaarheid in `WorkoutInsightServiceTests`
    /// (Epic #48). Bouwt de complete prompt zonder daadwerkelijk een API-call
    /// te doen — handig voor unit-testen van blok-conditie's en formatting.
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

        // Drempels-blok pas toevoegen als minstens één bekende waarde gezet is —
        // bij geen profielwaarden valt de coach terug op generieke aannames.
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

        // Epic #47: pauze-gebaseerde recovery-events meegeven — ook positieve.
        // Coach kan dan bij vraag "hoe ging mijn rit?" het uitstekende herstel
        // benoemen ook als er geen pin is. Voor matig herstel verstevigt dit
        // de pattern-pin met de feitelijke pauze-context.
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

        // Epic #48: doelen-status (blueprint milestones per actief doel) en
        // periodisering (huidige fase + succescriteria per doel). Beide blokken
        // worden weggelaten als ze leeg/nil zijn — coach valt dan terug op pure
        // uitvoerings-analyse zonder doel-koppeling.
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

        // Epic #49: weer-context tijdens de workout. Alleen toevoegen als
        // minstens één van de twee beschikbaar is — coach valt anders terug
        // op generieke aannames i.p.v. naar hitte te vragen.
        if context.temperatureCelsius != nil || context.humidityPercent != nil {
            lines.append("")
            lines.append("[WEER TIJDENS WORKOUT]")
            if let temp = context.temperatureCelsius {
                lines.append("- Temperatuur: \(Int(temp.rounded()))°C")
            }
            if let humidity = context.humidityPercent {
                lines.append("- Luchtvochtigheid: \(Int(humidity.rounded()))%")
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

    /// Mapt SDK-fouten op gebruiker-vriendelijke `InsightError`-cases. Match op de
    /// case-naam via `String(describing:)` (bv. `promptBlockedError(...)`) plus op
    /// `localizedDescription` voor URLError + non-Google fouten. Logt de rauwe fout
    /// naar de console — als de UI "Onbekende AI-fout (...)" toont, kunnen we daar
    /// de case-naam aflezen en 'm in een volgende ronde mappen.
    private func mapError(_ error: Error, retried: Bool) -> InsightError? {
        let caseDescription = String(describing: error)
        let message = error.localizedDescription
        let combined = "\(caseDescription) \(message)".lowercased()

        AppLoggers.workoutInsight.error("AI-call failed (retried=\(retried, privacy: .public)): \(caseDescription, privacy: .public) | localized=\(message, privacy: .public)")

        // Specifieke Google-SDK cases — case-naam is stabieler dan localized text.
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
        // Onbekende case: geef de rauwe case-naam terug zodat we hem in de UI kunnen
        // aflezen en in een volgende iteratie expliciet mappen.
        return .unavailable(retried: retried, detail: "Onbekende AI-fout — \(caseDescription)")
    }
}
