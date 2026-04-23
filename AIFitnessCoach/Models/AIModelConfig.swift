import Foundation

/// Epic #35 — Dynamische Gemini model-selectie.
///
/// Deze types mappen 1-op-1 op het JSON-schema dat de Cloudflare Worker
/// `/ai/models` retourneert. De app cachet de lijst lokaal zodat een
/// tijdelijke netwerkstoring de Settings-UI niet leeg laat.
struct AIModelDescriptor: Codable, Identifiable, Equatable, Hashable {
    /// Gemini modelnaam zoals de Google SDK hem verwacht (bijv. `gemini-flash-latest`).
    let id: String
    let displayName: String
    let description: String
    /// Nil = "zonder specifieke aanbeveling". `"primary"` / `"fallback"`
    /// wordt in de UI als hint-label bij het model getoond.
    let recommendedRole: String?
}

struct AIModelCatalog: Codable, Equatable {
    let models: [AIModelDescriptor]
    let defaultPrimary: String
    let defaultFallback: String
}

/// Fallback-catalogus wanneer de Worker (nog) niet is bijgewerkt of de
/// eerste fetch faalt. Deze modellen reflecteren de live productie-defaults
/// uit `ChatViewModel.buildGenerativeModel`.
extension AIModelCatalog {
    static let builtInFallback = AIModelCatalog(
        models: [
            AIModelDescriptor(
                id: "gemini-flash-latest",
                displayName: "Gemini Flash (latest)",
                description: "Snelste recente Flash-variant. Standaard primair model.",
                recommendedRole: "primary"
            ),
            AIModelDescriptor(
                id: "gemini-flash-lite-latest",
                displayName: "Gemini Flash Lite (latest)",
                description: "Lichter model, vaak beschikbaar tijdens piekbelasting. Standaard fallback.",
                recommendedRole: "fallback"
            ),
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
