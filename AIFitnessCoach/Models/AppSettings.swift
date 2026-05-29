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
    /// Epic #53: de client-laag (factory + REST-clients) ondersteunt alle vier de
    /// providers, maar key-opslag-per-provider (53.3) en de Settings-/onboarding-UI
    /// (53.6/53.7) volgen in latere sprints. Tot die er zijn blijft Gemini de enige
    /// die de UI selecteerbaar maakt.
    var isSupported: Bool {
        self == .gemini
    }
}

/// De databron die door de gebruiker is gekozen voor de fysiologische analyses en historie.
enum DataSource: String, CaseIterable, Identifiable {
    case healthKit = "Apple HealthKit"
    case strava = "Strava API"

    var id: String { self.rawValue }
}
