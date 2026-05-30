import Foundation

// MARK: - Epic 20: BYOK Multi-Provider Support

/// De AI-provider die de gebruiker heeft geconfigureerd voor de coach.
/// Enkel Gemini is in Sprint 20.1 volledig geïntegreerd; de andere providers zijn
/// beschikbaar als keuze in de UI en worden stapsgewijs uitgerold.
enum AIProvider: String, CaseIterable, Identifiable {
    case gemini    = "gemini"
    case openAI    = "openai"
    case anthropic = "anthropic"
    case mistral   = "mistral"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini:    return "Google Gemini"
        case .openAI:    return "OpenAI GPT"
        case .anthropic: return "Anthropic Claude"
        case .mistral:   return "Mistral"
        }
    }

    /// Placeholder-tekst in het SecureField zodat de gebruiker weet wat het verwachte formaat is.
    var keyPlaceholder: String {
        switch self {
        case .gemini:    return "AIzaSy..."
        case .openAI:    return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .mistral:   return "..."
        }
    }

    /// Directe URL waar de gebruiker een gratis API-sleutel kan aanmaken.
    var getKeyURL: URL? {
        switch self {
        case .gemini:    return URL(string: "https://aistudio.google.com/app/apikey")
        case .openAI:    return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .mistral:   return URL(string: "https://console.mistral.ai/api-keys")
        }
    }

    /// True als deze provider volledig geïntegreerd is en direct bruikbaar is.
    /// Epic #53 sprint B: alle vier providers zijn nu bruikbaar — per-provider
    /// key-opslag (53.3), model-defaults (53.4) en validatie (53.5) staan. De
    /// provider-specifieke model-*pickers* (53.6) en onboarding (53.7) volgen nog;
    /// tot dan gebruiken niet-Gemini providers hun default-model.
    var isSupported: Bool {
        true
    }
}

extension AIProvider {
    /// AppStorage/UserDefaults-sleutel waarin de actieve provider-keuze leeft.
    /// Eén bron-van-waarheid zodat views (`@AppStorage`) en logica (`current(in:)`)
    /// dezelfde key delen.
    static let appStorageKey = "vibecoach_aiProvider"

    /// De op dit moment door de gebruiker gekozen provider. Defaultet naar `.gemini`
    /// wanneer de key (nog) niet gezet is of een onbekende waarde bevat.
    static func current(in defaults: UserDefaults = .standard) -> AIProvider {
        AIProvider(rawValue: defaults.string(forKey: appStorageKey) ?? "") ?? .gemini
    }
}

/// De databron die door de gebruiker is gekozen voor de fysiologische analyses en historie.
enum DataSource: String, CaseIterable, Identifiable {
    case healthKit = "Apple HealthKit"
    case strava = "Strava API"

    var id: String { self.rawValue }
}
