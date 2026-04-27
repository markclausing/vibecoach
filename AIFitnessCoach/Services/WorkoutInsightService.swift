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
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Geen API-sleutel ingesteld. Open Instellingen → AI Coach om er één toe te voegen."
            case .noPatterns:
                return "Deze workout heeft geen significante fysiologische patronen — geen analyse nodig."
            case .generationFailed(let detail):
                return "AI-analyse mislukt: \(detail)"
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

    private let modelFactory: () -> GenerativeModelProtocol?

    /// Default factory bouwt een echte Gemini-call met het primaire model.
    /// Tests injecteren een mock-factory.
    init(modelFactory: @escaping () -> GenerativeModelProtocol? = WorkoutInsightService.defaultModelFactory) {
        self.modelFactory = modelFactory
    }

    static let defaultModelFactory: () -> GenerativeModelProtocol? = {
        let key = UserAPIKeyStore.read()
        guard !key.isEmpty else { return nil }
        let config = GenerationConfig()
        let options = RequestOptions(timeout: 30)
        let googleModel = GenerativeModel(
            name: AIModelAppStorageKey.resolvedPrimary(),
            apiKey: key,
            generationConfig: config,
            systemInstruction: ModelContent(role: "system", parts: [.text(systemInstruction)]),
            requestOptions: options
        )
        return RealGenerativeModel(model: googleModel)
    }

    /// Genereert een coaching-narrative voor de meegeleverde patronen + workout-context.
    /// - Parameters:
    ///   - patterns: Significante en mildere patronen uit `WorkoutPatternDetector.detectAll`.
    ///   - sportLabel: Bv. "hardlopen", "fietsen" — gaat als context mee in de prompt.
    ///   - durationMinutes: Workout-duur, ondersteunt de coach in het verhaal.
    /// - Returns: Korte Nederlandstalige tekst.
    /// - Throws: `InsightError` bij ontbrekende key, lege patronen of API-fout.
    func generateInsight(patterns: [WorkoutPattern],
                         sportLabel: String,
                         durationMinutes: Int) async throws -> String {
        guard !patterns.isEmpty else { throw InsightError.noPatterns }
        guard let model = modelFactory() else { throw InsightError.missingAPIKey }

        let snippet = WorkoutPatternFormatter.promptSnippet(for: patterns) ?? ""
        let prompt = """
        Workout-context:
        - Sport: \(sportLabel)
        - Duur: \(durationMinutes) minuten

        Gedetecteerde patronen:
        \(snippet)

        Geef je analyse.
        """

        do {
            let response = try await model.generateContent([.text(prompt)])
            guard let text = response?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw InsightError.generationFailed("Lege respons van AI-model")
            }
            return text
        } catch let insightError as InsightError {
            throw insightError
        } catch {
            throw InsightError.generationFailed(error.localizedDescription)
        }
    }
}
