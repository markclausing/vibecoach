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
    /// een auth-check — Google valideert de sleutel vóór de inferentie).
    private static let pingPrompt = "ok"

    /// Modelnaam — in lijn met `ChatViewModel.buildGenerativeModel` zodat we
    /// exact hetzelfde pad testen als de productie-chat gebruikt.
    private static let modelName = "gemini-flash-latest"

    /// Voer de validatie uit. Altijd op een Task-hop zodat de UI niet blokkeert.
    static func validateGeminiKey(_ key: String) async -> APIKeyValidationResult {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidKey }

        return await ping(modelName: modelName, key: trimmed)
    }

    /// Één enkele ping tegen de Gemini API.
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
                // 503/429 — rate-limited / overload.
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
