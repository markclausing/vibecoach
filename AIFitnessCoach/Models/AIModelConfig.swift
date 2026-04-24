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
            AIModelDescriptor(id: "gemini-flash-lite-latest", displayName: "Gemini Flash Lite (latest)"),
        ],
        defaultPrimary: "gemini-flash-latest",
        defaultFallback: "gemini-flash-lite-latest"
    )
}

/// Centrale plek voor de Epic #35 AppStorage-sleutels. Zo voorkomen we
/// stringtypfouten tussen `SettingsView` en `ChatViewModel`.
enum AIModelAppStorageKey {
    static let primary = "vibecoach_primaryGeminiModel"
    static let fallback = "vibecoach_fallbackGeminiModel"

    static let defaultPrimary = "gemini-flash-latest"
    static let defaultFallback = "gemini-flash-lite-latest"

    /// Leest de door de gebruiker gekozen primaire modelnaam, met fallback naar
    /// `defaultPrimary` wanneer de sleutel (nog) niet gezet is. De `UserDefaults`-
    /// parameter is er zodat unit-tests een geïsoleerde suite kunnen injecteren.
    static func resolvedPrimary(in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: primary) ?? defaultPrimary
    }

    /// Zie `resolvedPrimary` — idem voor het fallback-model dat na een 503/429
    /// op het primaire model wordt gebruikt.
    static func resolvedFallback(in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: fallback) ?? defaultFallback
    }
}
