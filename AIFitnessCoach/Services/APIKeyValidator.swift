import Foundation
import GoogleGenerativeAI

/// Result of a minimal validation ping on a user-entered
/// Gemini API key. We distinguish the scenarios the UI must react to differently:
/// genuinely invalid (have the user correct it), rate-limited (try later),
/// network error (offline), or unknown (fallback message).
enum APIKeyValidationResult: Equatable {
    /// The key works — the model accepted it.
    case valid
    /// Google returned an `invalidAPIKey` error.
    case invalidKey
    /// No network or timeout — we can't make a judgement.
    case network
    /// The model is overloaded (503/429). The key may well be valid —
    /// the user should try again later.
    case rateLimited
    /// All other error paths — we show the original error message, shortened.
    case unknown(String)
}

/// Epic #31 / Sprint 31.7: validates BYOK API keys with a minimal ping.
///
/// We use only `gemini-flash-latest` — the exact same model as
/// `ChatViewModel.buildGenerativeModel` in production. Google's `-latest` alias
/// always points to the most recent stable flash version and in practice knows
/// no overload spikes, making a waterfall with a second model unnecessary.
struct APIKeyValidator {

    /// Minimal text to limit usage (1–2 tokens is enough for
    /// an auth check — the provider validates the key before inference).
    private static let pingPrompt = "ok"

    /// Back-compat: validates a Gemini key. Delegates to the provider-aware
    /// variant so call sites that still call `validateGeminiKey` keep working.
    static func validateGeminiKey(_ key: String) async -> APIKeyValidationResult {
        await validate(key, provider: .gemini)
    }

    /// Epic #53: validates a BYOK key for any provider with a
    /// minimal ping via the `AIModelFactory`. Uses the cheapest model
    /// (provider-default fallback) to limit usage. Always on a Task hop
    /// so the UI doesn't block.
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

    /// Maps an arbitrary Swift `Error` to an `APIKeyValidationResult`.
    /// Exposed separately so unit tests can validate the error classification
    /// without making a real Gemini call — `ping(...)` itself cannot be
    /// tested without a network due to its direct `GenerativeModel` init.
    static func classify(_ error: Error) -> APIKeyValidationResult {
        // Epic #53: our own provider error from the OpenAI/Claude/Mistral REST clients.
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
            // Network errors: offline, timeout, DNS issue — no key judgement possible.
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
