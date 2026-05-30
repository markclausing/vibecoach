import Foundation

/// Epic #35 — Dynamic Gemini model selection.
///
/// These types map 1-to-1 onto the JSON schema the Cloudflare Worker
/// `/ai/models` returns. The Worker fetches the list live from the Google
/// Generative Language API, filters on `generateContent` support and strips
/// the `models/` prefix so the `id` can be used directly as `GenerativeModel(name:)`
/// in the Swift SDK.
struct AIModelDescriptor: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let displayName: String
}

struct AIModelCatalog: Codable, Equatable {
    let models: [AIModelDescriptor]
    let defaultPrimary: String
    let defaultFallback: String
}

/// Fallback catalog for when the Worker is (not yet) reachable or the
/// first fetch fails. Reflects the model names that were hardcoded in
/// `ChatViewModel` before Epic #35, so an offline start does not break.
extension AIModelCatalog {
    static let builtInFallback = AIModelCatalog(
        models: [
            AIModelDescriptor(id: "gemini-flash-latest", displayName: "Gemini Flash (latest)"),
            AIModelDescriptor(id: "gemini-flash-lite-latest", displayName: "Gemini Flash Lite (latest)")
        ],
        defaultPrimary: "gemini-flash-latest",
        defaultFallback: "gemini-flash-lite-latest"
    )

    /// Epic #53 — curated static catalog per provider. Gemini uses the
    /// dynamic Worker catalog (`AIModelCatalogService`) with `builtInFallback`
    /// as the offline safety net; OpenAI/Claude/Mistral change their model list
    /// slowly enough that a hardcoded, validated list suffices — no extra
    /// network round-trip needed. `defaultPrimary` is the capable model,
    /// `defaultFallback` the cheaper model for the 503/429 waterfall.
    static func builtIn(for provider: AIProvider) -> AIModelCatalog {
        switch provider {
        case .gemini:
            return builtInFallback
        case .openAI:
            return AIModelCatalog(
                models: [
                    AIModelDescriptor(id: "gpt-4.1", displayName: "GPT-4.1"),
                    AIModelDescriptor(id: "gpt-4.1-mini", displayName: "GPT-4.1 mini")
                ],
                defaultPrimary: "gpt-4.1",
                defaultFallback: "gpt-4.1-mini"
            )
        case .anthropic:
            return AIModelCatalog(
                models: [
                    AIModelDescriptor(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6"),
                    AIModelDescriptor(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5")
                ],
                defaultPrimary: "claude-sonnet-4-6",
                defaultFallback: "claude-haiku-4-5"
            )
        case .mistral:
            return AIModelCatalog(
                models: [
                    AIModelDescriptor(id: "mistral-large-latest", displayName: "Mistral Large"),
                    AIModelDescriptor(id: "mistral-small-latest", displayName: "Mistral Small")
                ],
                defaultPrimary: "mistral-large-latest",
                defaultFallback: "mistral-small-latest"
            )
        }
    }
}

/// Central place for the Epic #35 AppStorage keys. This prevents
/// string typos between `SettingsView` and `ChatViewModel`.
enum AIModelAppStorageKey {
    /// Gemini keeps the original Epic #35 keys so the existing model choice
    /// of users stays intact. Other providers get their own
    /// provider-suffixed key (see `primaryKey(for:)`).
    static let primary = "vibecoach_primaryGeminiModel"
    static let fallback = "vibecoach_fallbackGeminiModel"

    static let defaultPrimary = "gemini-flash-latest"
    static let defaultFallback = "gemini-flash-lite-latest"

    // MARK: - Per-provider keys (Epic #53)

    /// AppStorage key for a provider's primary model. Gemini → the
    /// legacy key (backward-compat); other providers → `vibecoach_primaryModel_<raw>`.
    static func primaryKey(for provider: AIProvider) -> String {
        provider == .gemini ? primary : "vibecoach_primaryModel_\(provider.rawValue)"
    }

    /// See `primaryKey(for:)` — same for the fallback model.
    static func fallbackKey(for provider: AIProvider) -> String {
        provider == .gemini ? fallback : "vibecoach_fallbackModel_\(provider.rawValue)"
    }

    /// Provider-aware resolution of the primary model, with a fallback to the
    /// curated provider default (`AIModelCatalog.builtIn(for:)`).
    static func resolvedPrimary(for provider: AIProvider, in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: primaryKey(for: provider)) ?? AIModelCatalog.builtIn(for: provider).defaultPrimary
    }

    /// See `resolvedPrimary(for:)` — same for the fallback model.
    static func resolvedFallback(for provider: AIProvider, in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: fallbackKey(for: provider)) ?? AIModelCatalog.builtIn(for: provider).defaultFallback
    }

    // MARK: - Backward-compat (Gemini)

    /// Reads the user's chosen primary model name. The retained no-arg
    /// variant = Gemini, so existing call sites and tests keep working.
    static func resolvedPrimary(in defaults: UserDefaults = .standard) -> String {
        resolvedPrimary(for: .gemini, in: defaults)
    }

    /// See `resolvedPrimary` — same for the fallback model.
    static func resolvedFallback(in defaults: UserDefaults = .standard) -> String {
        resolvedFallback(for: .gemini, in: defaults)
    }
}
