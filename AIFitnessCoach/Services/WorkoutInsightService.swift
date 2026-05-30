import Foundation

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
    /// Epic #52 update: harde regel dat de analyse nooit met een vraag eindigt —
    /// deze view heeft geen chat-functie, dus elke open vraag blijft hangen
    /// zonder beantwoording.
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
        // Epic #53: provider-agnostisch via de `AIModelFactory`. `jsonMode = false`
        // — de Coach-analyse is vrije tekst, geen JSON-schema. Timeout 30s zoals
        // voorheen. Sleutel + modelnaam horen bij de actieve provider.
        return AIModelFactory.makeModel(
            provider: provider,
            modelName: modelName,
            systemInstruction: systemInstruction,
            jsonMode: false,
            timeout: 30,
            apiKey: key
        )
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
        /// over hitte/dehydratie. Voor records mét GPS-coords krijgt Epic #52
        /// voorrang (hourly-range), maar deze snapshot blijft het fallback-pad
        /// voor HK-only ritten zonder geregistreerde coords.
        let temperatureCelsius: Double?
        let humidityPercent: Double?
        /// Epic #52: hourly weer-aggregaat over het volledige workout-venster.
        /// Piek (warmste uur tijdens de rit) en gemiddelde voor zowel temperatuur
        /// als luchtvochtigheid. Wanneer aanwezig krijgt deze range voorrang
        /// op de snapshot — een 90-min run die om 9:43 bij 15°C startte maar
        /// onderweg naar 22°C piek liep, wordt fair als 22°C-rit geëvalueerd.
        /// Alle subvelden optioneel; nil → blok valt weg.
        let peakTempCelsius: Double?
        let avgTempCelsius: Double?
        let peakHumidityPercent: Double?
        let avgHumidityPercent: Double?
        /// Epic #52: cadens (steps per minute) tijdens een hardloop. Gemiddelde
        /// over niet-nul samples (rust-buckets uitgesloten) + piek (95e
        /// percentiel om sprintje-spikes af te vlakken). Alleen aanwezig voor
        /// running-workouts; cycling-cadens wordt vandaag niet in deze prompt
        /// meegenomen. Beide nil → blok valt weg.
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

        // Epic #49 + #52: weer-context tijdens de workout. Range (hourly piek + gem.)
        // krijgt voorrang op snapshot wanneer aanwezig — een 90-min run pikt zo de
        // warmte tijdens de rit op, niet alleen de single-point bij rit-start.
        // Alleen toevoegen als minstens één van de velden beschikbaar is.
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

        // Epic #52: cadens-context voor hardloop. Alleen toonbaar bij minstens
        // één van de twee waardes — anders valt het blok stil weg.
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

        // Epic #53: getypeerde mapping voor de niet-Gemini REST-clients (OpenAI/
        // Claude/Mistral) die `AIProviderError` gooien. Gaat vóór de string-matching
        // zodat we niet afhankelijk zijn van de stringrepresentatie.
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .overloaded:
                return .rateLimited(retried: retried)
            case .authenticationFailed:
                return .authenticationFailed
            case .contentBlocked:
                return .contentBlocked
            case .http(let status):
                return .unavailable(retried: retried, detail: "AI-provider gaf HTTP \(status) terug.")
            case .emptyResponse:
                return .unavailable(retried: retried, detail: "Lege respons van AI-model.")
            case .decodingFailed:
                return .unavailable(retried: retried, detail: "Onverwacht antwoordformaat van de AI-provider.")
            }
        }

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
