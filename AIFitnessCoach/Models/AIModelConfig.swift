import Foundation

/// Epic #35 — Dynamische Gemini model-selectie.
///
/// Deze types mappen 1-op-1 op het JSON-schema dat de Cloudflare Worker
/// `/ai/models` retourneert. De Worker haalt de lijst live op bij de Google
/// Generative Language API, filtert op `generateContent`-support en strippet
/// de `models/`-prefix zodat de `id` direct als `GenerativeModel(name:)` in de
/// Swift-SDK gebruikt kan worden.
struct AIModelDescriptor: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let displayName: String
}

struct AIModelCatalog: Codable, Equatable {
    let models: [AIModelDescriptor]
    let defaultPrimary: String
    let defaultFallback: String
}

/// Fallback-catalogus wanneer de Worker (nog) niet bereikbaar is of de
/// eerste fetch faalt. Reflecteert de modelnamen die vóór Epic #35 hardcoded
/// in `ChatViewModel` stonden, zodat een offline start niet stuk gaat.
extension AIModelCatalog {
    static let builtInFallback = AIModelCatalog(
        models: [
            AIModelDescriptor(id: "gemini-flash-latest", displayName: "Gemini Flash (latest)"),
            AIModelDescriptor(id: "gemini-flash-lite-latest", displayName: "Gemini Flash Lite (latest)")
        ],
        defaultPrimary: "gemini-flash-latest",
        defaultFallback: "gemini-flash-lite-latest"
    )

    /// Epic #53 — gecureerde statische catalogus per provider. Gemini gebruikt de
    /// dynamische Worker-catalogus (`AIModelCatalogService`) met `builtInFallback`
    /// als offline-vangnet; OpenAI/Claude/Mistral wijzigen hun modellijst traag
    /// genoeg dat een hardcoded, door ons gevalideerde lijst volstaat — geen
    /// extra netwerk-roundtrip nodig. `defaultPrimary` is het capabele model,
    /// `defaultFallback` het goedkopere model voor de 503/429-waterfall.
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

/// Centrale plek voor de Epic #35 AppStorage-sleutels. Zo voorkomen we
/// stringtypfouten tussen `SettingsView` en `ChatViewModel`.
enum AIModelAppStorageKey {
    /// Gemini behoudt de oorspronkelijke Epic #35-keys zodat de bestaande
    /// modelkeuze van gebruikers intact blijft. Andere providers krijgen een
    /// eigen, provider-gesuffixte key (zie `primaryKey(for:)`).
    static let primary = "vibecoach_primaryGeminiModel"
    static let fallback = "vibecoach_fallbackGeminiModel"

    static let defaultPrimary = "gemini-flash-latest"
    static let defaultFallback = "gemini-flash-lite-latest"

    // MARK: - Per-provider keys (Epic #53)

    /// AppStorage-key voor het primaire model van een provider. Gemini → de
    /// legacy-key (backward-compat); overige providers → `vibecoach_primaryModel_<raw>`.
    static func primaryKey(for provider: AIProvider) -> String {
        provider == .gemini ? primary : "vibecoach_primaryModel_\(provider.rawValue)"
    }

    /// Zie `primaryKey(for:)` — idem voor het fallback-model.
    static func fallbackKey(for provider: AIProvider) -> String {
        provider == .gemini ? fallback : "vibecoach_fallbackModel_\(provider.rawValue)"
    }

    /// Provider-aware resolutie van het primaire model, met fallback naar de
    /// gecureerde provider-default (`AIModelCatalog.builtIn(for:)`).
    static func resolvedPrimary(for provider: AIProvider, in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: primaryKey(for: provider)) ?? AIModelCatalog.builtIn(for: provider).defaultPrimary
    }

    /// Zie `resolvedPrimary(for:)` — idem voor het fallback-model.
    static func resolvedFallback(for provider: AIProvider, in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: fallbackKey(for: provider)) ?? AIModelCatalog.builtIn(for: provider).defaultFallback
    }

    // MARK: - Backward-compat (Gemini)

    /// Leest de door de gebruiker gekozen primaire modelnaam. Behouden no-arg
    /// variant = Gemini, zodat bestaande call-sites en tests ongewijzigd werken.
    static func resolvedPrimary(in defaults: UserDefaults = .standard) -> String {
        resolvedPrimary(for: .gemini, in: defaults)
    }

    /// Zie `resolvedPrimary` — idem voor het fallback-model.
    static func resolvedFallback(in defaults: UserDefaults = .standard) -> String {
        resolvedFallback(for: .gemini, in: defaults)
    }
}
