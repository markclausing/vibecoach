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
}
