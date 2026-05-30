import Foundation
import GoogleGenerativeAI

/// Resultaat van een minimale validatie-ping op een door de gebruiker ingevoerde
/// Gemini API-sleutel. We onderscheiden de scenario's waar de UI verschillend op
/// moet reageren: echt ongeldig (gebruiker corrigeren), rate-limited (later nog
/// eens), netwerkfout (offline), of onbekend (fallback-bericht).
enum APIKeyValidationResult: Equatable {
    /// De sleutel werkt — het model accepteerde hem.
    case valid
    /// Google gaf een `invalidAPIKey`-fout terug.
    case invalidKey
    /// Geen netwerk of timeout — we kunnen geen uitspraak doen.
    case network
    /// Model is overbelast (503/429). Sleutel kan prima geldig zijn —
    /// de gebruiker moet het later opnieuw proberen.
    case rateLimited
    /// Alle andere foutpaden — we tonen de originele foutmelding verkort.
    case unknown(String)
}

/// Epic #31 / Sprint 31.7: Valideert BYOK API-sleutels met een minimale ping.
///
/// We gebruiken uitsluitend `gemini-flash-latest` — exact hetzelfde model als
/// `ChatViewModel.buildGenerativeModel` in productie. Google's `-latest` alias
/// wijst altijd naar de meest recente stabiele flash-versie en kent in praktijk
/// geen overload-pieken, waardoor een waterfall met een tweede model overbodig is.
struct APIKeyValidator {

    /// Minimale tekst om verbruik te beperken (1–2 tokens is voldoende voor
    /// een auth-check — de provider valideert de sleutel vóór de inferentie).
    private static let pingPrompt = "ok"

    /// Back-compat: valideert een Gemini-sleutel. Delegeert naar de provider-aware
    /// variant zodat call-sites die nog `validateGeminiKey` aanroepen blijven werken.
    static func validateGeminiKey(_ key: String) async -> APIKeyValidationResult {
        await validate(key, provider: .gemini)
    }

    /// Epic #53: valideert een BYOK-sleutel voor een willekeurige provider met een
    /// minimale ping via de `AIModelFactory`. Gebruikt het goedkoopste model
    /// (provider-default fallback) om verbruik te beperken. Altijd op een Task-hop
    /// zodat de UI niet blokkeert.
    static func validate(_ key: String, provider: AIProvider) async -> APIKeyValidationResult {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidKey }

        let modelName = AIModelCatalog.builtIn(for: provider).defaultFallback
        let model = AIModelFactory.makeModel(
            provider: provider,
            modelName: modelName,
            systemInstruction: "",
            jsonMode: false,
            timeout: 20,
            apiKey: trimmed
        )
        do {
            _ = try await model.generateContent([.text(pingPrompt)])
            return .valid
        } catch {
            return classify(error)
        }
    }

    /// Mapt een willekeurige Swift `Error` naar een `APIKeyValidationResult`.
    /// Apart blootgesteld zodat unit-tests de foutclassificatie kunnen valideren
    /// zonder een echte Gemini-call te hoeven doen — `ping(...)` zelf is door
    /// zijn directe `GenerativeModel`-init niet zonder netwerk te testen.
    static func classify(_ error: Error) -> APIKeyValidationResult {
        // Epic #53: onze eigen provider-fout van de OpenAI/Claude/Mistral REST-clients.
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .authenticationFailed:
                return .invalidKey
            case .overloaded:
                return .rateLimited
            case .http(let status, let message):
                return .unknown("HTTP \(status)\(message.map { ": \($0)" } ?? "")")
            case .contentBlocked, .emptyResponse, .decodingFailed:
                return .unknown(String(describing: providerError))
            }
        }

        if let generateError = error as? GenerateContentError {
            switch generateError {
            case .invalidAPIKey:
                return .invalidKey
            case .internalError:
                // 503/429 — rate-limited / overload.
                return .rateLimited
            default:
                return .unknown(generateError.localizedDescription)
            }
        }

        if let urlError = error as? URLError {
            // Netwerk-fouten: offline, timeout, DNS-issue — sleutel-oordeel kan niet.
            switch urlError.code {
            case .notConnectedToInternet, .timedOut, .networkConnectionLost, .dnsLookupFailed:
                return .network
            default:
                return .unknown(urlError.localizedDescription)
            }
        }

        return .unknown(error.localizedDescription)
    }
}
