import Foundation
import GoogleGenerativeAI

/// Resultaat van een minimale validatie-ping op een door de gebruiker ingevoerde
/// Gemini API-sleutel. We onderscheiden de scenario's waar de UI verschillend op
/// moet reageren: echt ongeldig (gebruiker corrigeren), rate-limited (later nog
/// eens), netwerkfout (offline), of onbekend (fallback-bericht).
enum APIKeyValidationResult: Equatable {
    /// De sleutel werkt — minstens één van de twee modellen accepteerde hem.
    case valid
    /// Google gaf een `invalidAPIKey`-fout voor zowel primair als fallback model.
    case invalidKey
    /// Geen netwerk of timeout — we kunnen geen uitspraak doen.
    case network
    /// Beide modellen zijn overbelast (503/429). Sleutel kan prima geldig zijn —
    /// de gebruiker moet het later opnieuw proberen.
    case rateLimited
    /// Alle andere foutpaden — we tonen de originele foutmelding verkort.
    case unknown(String)
}

/// Epic #31 / Sprint 31.7: Valideert BYOK API-sleutels met een minimale ping.
///
/// Dezelfde waterfall-strategie als `ChatViewModel.fetchAIResponse`:
/// 1. Probeer het primaire model (`gemini-2.5-flash`)
/// 2. Alleen bij `GenerateContentError.internalError` (503/429 overload)
///    schakelen we stil over naar `gemini-flash-latest`
///
/// Hierdoor wordt een geldige sleutel tijdens een Google-piek niet onterecht
/// als "ongeldig" gemarkeerd. Een echte `invalidAPIKey`-fout slaat direct door
/// — Google geeft die consistent op beide modellen.
struct APIKeyValidator {

    /// Minimale tekst om verbruik te beperken (1–2 tokens is voldoende voor
    /// een auth-check — Google valideert de sleutel vóór de inferentie).
    private static let pingPrompt = "ok"

    /// Modelnamen — in lijn met `ChatViewModel.buildGenerativeModel` en
    /// `buildFallbackGenerativeModel` zodat we exact hetzelfde pad testen als
    /// de productie-chat gebruikt.
    private static let primaryModelName  = "gemini-2.5-flash"
    private static let fallbackModelName = "gemini-flash-latest"

    /// Voer de validatie uit. Altijd op een Task-hop zodat de UI niet blokkeert.
    static func validateGeminiKey(_ key: String) async -> APIKeyValidationResult {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidKey }

        // Eerste poging: primair model.
        let primaryResult = await ping(modelName: primaryModelName, key: trimmed)

        switch primaryResult {
        case .valid, .invalidKey, .network, .unknown:
            return primaryResult
        case .rateLimited:
            // Primair model overbelast — probeer fallback net als in productie.
            let fallbackResult = await ping(modelName: fallbackModelName, key: trimmed)
            return fallbackResult
        }
    }

    /// Één enkele ping. Geïsoleerd zodat we hem voor primary én fallback kunnen
    /// hergebruiken zonder de switch-logica te dupliceren.
    private static func ping(modelName: String, key: String) async -> APIKeyValidationResult {
        let model = GenerativeModel(name: modelName, apiKey: key)
        let content = ModelContent(role: "user", parts: [.text(pingPrompt)])

        do {
            _ = try await model.generateContent([content])
            return .valid
        } catch let error as GenerateContentError {
            switch error {
            case .invalidAPIKey:
                return .invalidKey
            case .internalError:
                // 503/429 — rate-limited / overload. Laat de caller beslissen
                // of we naar de fallback overstappen.
                return .rateLimited
            default:
                return .unknown(error.localizedDescription)
            }
        } catch let urlError as URLError {
            // Netwerk-fouten: offline, timeout, DNS-issue — sleutel-oordeel kan niet.
            switch urlError.code {
            case .notConnectedToInternet, .timedOut, .networkConnectionLost, .dnsLookupFailed:
                return .network
            default:
                return .unknown(urlError.localizedDescription)
            }
        } catch {
            return .unknown(error.localizedDescription)
        }
    }
}
