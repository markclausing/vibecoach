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
        case noPatterns
        case rateLimited(retried: Bool)
        case authenticationFailed
        case contentBlocked
        case timedOut(retried: Bool)
        case unavailable(retried: Bool, detail: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Geen API-sleutel ingesteld. Open Instellingen → AI Coach om er één toe te voegen."
            case .noPatterns:
                return "Deze workout heeft geen significante fysiologische patronen — geen analyse nodig."
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
    }

    /// Genereert een coaching-narrative voor de meegeleverde patronen + workout-context.
    /// Probeert eerst het primaire model; faalt dat op een retryable fout, dan
    /// volgt automatisch een poging op het fallback-model. Zo blijft de Coach-analyse
    /// werken bij een tijdelijke 503/429 op het primaire model.
    func generateInsight(patterns: [WorkoutPattern],
                         context: InsightContext) async throws -> String {
        guard !patterns.isEmpty else { throw InsightError.noPatterns }
        guard let primary = primaryFactory() else { throw InsightError.missingAPIKey }

        let prompt = buildPrompt(patterns: patterns, context: context)

        do {
            return try await callModel(primary, prompt: prompt)
        } catch {
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
                throw mapError(error, retried: true) ?? .unavailable(retried: true, detail: error.localizedDescription)
            }
        }
    }

    private func buildPrompt(patterns: [WorkoutPattern], context: InsightContext) -> String {
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
        lines.append(snippet)
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

    /// Mapt SDK-fouten op gebruiker-vriendelijke `InsightError`-cases. Werkt op basis
    /// van string-matching omdat `GoogleGenerativeAI.GenerateContentError` geen stabiele
    /// publieke discriminators heeft — keyword-matching dekt 503/429/auth/blocked
    /// en de timeout-paden uit `URLError`.
    private func mapError(_ error: Error, retried: Bool) -> InsightError? {
        let message = error.localizedDescription.lowercased()
        if message.contains("api key") || message.contains("api_key") || message.contains("unauthenticated") || message.contains("unauthorized") {
            return .authenticationFailed
        }
        if message.contains("quota") || message.contains("rate limit") || message.contains("429") {
            return .rateLimited(retried: retried)
        }
        if message.contains("blocked") || message.contains("safety") || message.contains("harm") {
            return .contentBlocked
        }
        if message.contains("timed out") || message.contains("timeout") || (error as? URLError)?.code == .timedOut {
            return .timedOut(retried: retried)
        }
        return nil
    }
}
