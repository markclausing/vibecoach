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

    /// Beknopte system-instruction. Bewust ander register dan de chat-coach: hier
    /// is de coach een fysiologisch analist die patronen samenbrengt tot een
    /// kort verhaal — geen oefenschema, geen vragen.
    private static let systemInstruction: String = """
    Je bent een sportfysiologisch analist die patronen in een workout interpreteert.
    Je ontvangt een lijst gedetecteerde patronen met severity (MILD/MODERATE/SIGNIFICANT)
    en numerieke waardes (drift-percentage, BPM-drop). Geef een coaching-analyse van
    maximaal 3 zinnen die:

    1. De patronen samenbrengt tot één fysiologisch verhaal (bv. "decoupling + cardiac
       drift = aerobic ceiling overschreden").
    2. Een mogelijke oorzaak benoemt (intensiteit te hoog, hitte, slechte slaap,
       conditie-gat) — kies de waarschijnlijkste op basis van de waardes.
    3. Een concrete vervolgvraag of korte aanbeveling sluit, gericht op de gebruiker.

    Stijl: Nederlandstalig, tweede persoon ("je"), geen jargon zonder uitleg, geen lijsten,
    geen markdown. Eindig zonder "Als je vragen hebt..."-clichés.
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

    /// Genereert een coaching-narrative voor de meegeleverde patronen + workout-context.
    /// Probeert eerst het primaire model; faalt dat op een retryable fout, dan
    /// volgt automatisch een poging op het fallback-model. Zo blijft de Coach-analyse
    /// werken bij een tijdelijke 503/429 op het primaire model.
    func generateInsight(patterns: [WorkoutPattern],
                         sportLabel: String,
                         durationMinutes: Int) async throws -> String {
        guard !patterns.isEmpty else { throw InsightError.noPatterns }
        guard let primary = primaryFactory() else { throw InsightError.missingAPIKey }

        let prompt = buildPrompt(patterns: patterns, sportLabel: sportLabel, durationMinutes: durationMinutes)

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

    private func buildPrompt(patterns: [WorkoutPattern], sportLabel: String, durationMinutes: Int) -> String {
        let snippet = WorkoutPatternFormatter.promptSnippet(for: patterns) ?? ""
        return """
        Workout-context:
        - Sport: \(sportLabel)
        - Duur: \(durationMinutes) minuten

        Gedetecteerde patronen:
        \(snippet)

        Geef je analyse.
        """
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

        print("[WorkoutInsightService] AI-call failed (retried=\(retried)): \(caseDescription) | localized=\(message)")

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
