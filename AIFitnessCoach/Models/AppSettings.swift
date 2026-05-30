import Foundation

// MARK: - Epic 20: BYOK Multi-Provider Support

/// The AI provider the user has configured for the coach.
/// All four providers are usable since Epic #53; see `isSupported`.
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

    /// Short name for compact UI (segmented picker, connection subtitle).
    var shortName: String {
        switch self {
        case .gemini:    return "Gemini"
        case .openAI:    return "OpenAI"
        case .anthropic: return "Claude"
        case .mistral:   return "Mistral"
        }
    }

    /// Placeholder text in the SecureField so the user knows the expected format.
    var keyPlaceholder: String {
        switch self {
        case .gemini:    return "AIzaSy..."
        case .openAI:    return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .mistral:   return "..."
        }
    }

    /// Direct URL where the user can create an API key.
    var getKeyURL: URL? {
        switch self {
        case .gemini:    return URL(string: "https://aistudio.google.com/app/apikey")
        case .openAI:    return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .mistral:   return URL(string: "https://console.mistral.ai/api-keys")
        }
    }

    /// True if this provider is fully integrated and directly usable.
    /// Epic #53 sprint B: all four providers are now usable — per-provider
    /// key storage (53.3), model defaults (53.4) and validation (53.5) are in place.
    /// The provider-specific model *pickers* (53.6) and onboarding (53.7) followed in
    /// sprint C; non-Gemini providers use their default model until they pick one.
    var isSupported: Bool {
        true
    }
}

extension AIProvider {
    /// AppStorage/UserDefaults key holding the active provider choice.
    /// A single source of truth so views (`@AppStorage`) and logic (`current(in:)`)
    /// share the same key.
    static let appStorageKey = "vibecoach_aiProvider"

    /// The provider currently chosen by the user. Defaults to `.gemini`
    /// when the key is not (yet) set or contains an unknown value.
    static func current(in defaults: UserDefaults = .standard) -> AIProvider {
        AIProvider(rawValue: defaults.string(forKey: appStorageKey) ?? "") ?? .gemini
    }
}

/// The data source chosen by the user for the physiological analyses and history.
enum DataSource: String, CaseIterable, Identifiable {
    case healthKit = "Apple HealthKit"
    case strava = "Strava API"

    var id: String { self.rawValue }
}
