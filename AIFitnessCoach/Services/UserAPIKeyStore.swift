import Foundation

/// Central access to the user-entered AI provider API key
/// (BYOK — Epic 20). The key is stored in the iOS Keychain and never
/// again in `UserDefaults` — see `C-02` in the security audit.
///
/// Use `KeychainService.shared` in production; tests can inject their own
/// `TokenStore` via the `read/write/delete` helpers.
enum UserAPIKeyStore {

    /// Keychain service name for the user-provided AI API key.
    /// Deliberately separate from other keychain items (Strava tokens etc).
    ///
    /// **Legacy** since Epic #53: this was the only slot when only Gemini existed.
    /// The per-provider slots live under `serviceName(for:)`; the one-time
    /// `migrateToPerProviderKeysIfNeeded` moves this legacy entry to the
    /// Gemini slot. The no-arg `read/write/delete` keep working on this name for
    /// the existing migration tests.
    static let serviceName = "VibeCoach_UserAIKey"

    /// Per-provider Keychain service name (Epic #53). This way the user doesn't lose their
    /// OpenAI key when temporarily switching to Claude and back.
    static func serviceName(for provider: AIProvider) -> String {
        "\(serviceName)_\(provider.rawValue)"
    }

    /// Legacy `UserDefaults` key used for the AI key until Epic 20.
    /// After migration this entry is cleared; the constant lives here so
    /// migration logic and the UI test helper share the same source of truth.
    static let legacyUserDefaultsKey = "vibecoach_userAPIKey"

    // MARK: - Production helpers (KeychainService.shared)

    /// Reads the stored key from the Keychain. Returns an empty string
    /// when there is no key — this matches the old `@AppStorage` default
    /// so call sites don't have to check for `nil`.
    static func read() -> String {
        read(using: KeychainService.shared)
    }

    /// Stores a key in the Keychain. An empty string clears the entry
    /// (otherwise an unwanted empty string would remain).
    static func write(_ key: String) {
        write(key, using: KeychainService.shared)
    }

    /// Removes the key from the Keychain.
    static func delete() {
        delete(using: KeychainService.shared)
    }

    // MARK: - Dependency injection (for unit tests)

    static func read(using store: TokenStore) -> String {
        (try? store.getToken(forService: serviceName)) ?? ""
    }

    static func write(_ key: String, using store: TokenStore) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try store.deleteToken(forService: serviceName)
            } else {
                try store.saveToken(trimmed, forService: serviceName)
            }
        } catch {
            AppLoggers.userAPIKey.error("write faalde: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func delete(using store: TokenStore) {
        do {
            try store.deleteToken(forService: serviceName)
        } catch {
            AppLoggers.userAPIKey.error("delete faalde: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Per-provider (Epic #53)

    static func read(for provider: AIProvider) -> String {
        read(for: provider, using: KeychainService.shared)
    }

    static func write(_ key: String, for provider: AIProvider) {
        write(key, for: provider, using: KeychainService.shared)
    }

    static func delete(for provider: AIProvider) {
        delete(for: provider, using: KeychainService.shared)
    }

    static func read(for provider: AIProvider, using store: TokenStore) -> String {
        (try? store.getToken(forService: serviceName(for: provider))) ?? ""
    }

    static func write(_ key: String, for provider: AIProvider, using store: TokenStore) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = serviceName(for: provider)
        do {
            if trimmed.isEmpty {
                try store.deleteToken(forService: service)
            } else {
                try store.saveToken(trimmed, forService: service)
            }
        } catch {
            AppLoggers.userAPIKey.error("write(for:) faalde: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func delete(for provider: AIProvider, using store: TokenStore) {
        do {
            try store.deleteToken(forService: serviceName(for: provider))
        } catch {
            AppLoggers.userAPIKey.error("delete(for:) faalde: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Migration (C-02)

    /// One-time migration: if a key still lives in `UserDefaults`
    /// (from an earlier installation before this security fix), move it
    /// to the Keychain and clear the `UserDefaults` entry.
    ///
    /// Idempotent: if there is nothing to migrate this function does nothing. Called
    /// in `AIFitnessCoachApp.init()` on every cold start — the check
    /// is cheap and self-terminating.
    static func migrateFromUserDefaultsIfNeeded(
        store: TokenStore = KeychainService.shared,
        defaults: UserDefaults = .standard
    ) {
        guard let legacy = defaults.string(forKey: legacyUserDefaultsKey),
              !legacy.isEmpty else {
            return
        }

        do {
            try store.saveToken(legacy, forService: serviceName)
            // Only clear after the Keychain write succeeded — otherwise the
            // key would be lost entirely on an error.
            defaults.removeObject(forKey: legacyUserDefaultsKey)
            AppLoggers.userAPIKey.info("user API key gemigreerd van UserDefaults naar Keychain")
        } catch {
            AppLoggers.userAPIKey.error("migratie faalde, UserDefaults-entry blijft staan: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One-time migration (Epic #53): moves the legacy single key (`serviceName`)
    /// to the per-provider Gemini slot. Existing Gemini users keep their
    /// key without re-entering it.
    ///
    /// Idempotent: does nothing when the Gemini slot is already filled or the legacy slot
    /// is empty. Called after `migrateFromUserDefaultsIfNeeded` in
    /// `AIFitnessCoachApp.init()`.
    static func migrateToPerProviderKeysIfNeeded(store: TokenStore = KeychainService.shared) {
        let geminiService = serviceName(for: .gemini)
        let existingGemini = (try? store.getToken(forService: geminiService)) ?? ""
        guard existingGemini.isEmpty else { return }

        let legacy = (try? store.getToken(forService: serviceName)) ?? ""
        guard !legacy.isEmpty else { return }

        do {
            try store.saveToken(legacy, forService: geminiService)
            // Only clear the legacy entry after the write to the Gemini slot succeeded.
            try store.deleteToken(forService: serviceName)
            AppLoggers.userAPIKey.info("user API key gemigreerd naar per-provider Gemini-slot")
        } catch {
            AppLoggers.userAPIKey.error("per-provider migratie faalde, legacy-slot blijft staan: \(error.localizedDescription, privacy: .public)")
        }
    }
}
