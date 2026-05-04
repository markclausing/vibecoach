import Foundation

/// Centrale toegang tot de door de gebruiker ingevoerde AI-provider API-sleutel
/// (BYOK — Epic 20). De sleutel wordt opgeslagen in de iOS Keychain en nooit
/// meer in `UserDefaults` — zie `C-02` in de security-audit.
///
/// Gebruik `KeychainService.shared` in productie; tests kunnen een eigen
/// `TokenStore` injecteren via de `read/write/delete`-helpers.
enum UserAPIKeyStore {

    /// Keychain-service-naam voor de user-provided AI API key.
    /// Bewust gescheiden van andere keychain-items (Strava tokens etc).
    static let serviceName = "VibeCoach_UserAIKey"

    /// Legacy `UserDefaults`-key die tot Epic 20 werd gebruikt voor de AI-sleutel.
    /// Na migratie wordt deze entry gewist; de constant leeft hier zodat
    /// migratie-logica en UI-testhulp dezelfde bron-van-waarheid delen.
    static let legacyUserDefaultsKey = "vibecoach_userAPIKey"

    // MARK: - Productie helpers (KeychainService.shared)

    /// Leest de opgeslagen sleutel uit de Keychain. Retourneert een lege string
    /// wanneer er geen sleutel is — dit sluit aan op de oude `@AppStorage`-default
    /// zodat call-sites niet hoeven te checken op `nil`.
    static func read() -> String {
        read(using: KeychainService.shared)
    }

    /// Slaat een sleutel op in de Keychain. Een lege string wist de entry
    /// (anders zou een ongewenste lege string blijven staan).
    static func write(_ key: String) {
        write(key, using: KeychainService.shared)
    }

    /// Verwijdert de sleutel uit de Keychain.
    static func delete() {
        delete(using: KeychainService.shared)
    }

    // MARK: - Dependency injection (voor unit tests)

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

    // MARK: - Migratie (C-02)

    /// Eenmalige migratie: als er nog een sleutel in `UserDefaults` staat
    /// (vanuit een eerdere installatie vóór deze security-fix) verplaats die
    /// naar de Keychain en wis de `UserDefaults`-entry.
    ///
    /// Idempotent: als er niks te migreren is doet deze functie niks. Wordt
    /// aangeroepen in `AIFitnessCoachApp.init()` bij elke coldstart — de check
    /// is goedkoop en zelf-terminerend.
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
            // Pas wissen nádat de Keychain-write slaagde — anders raakt de
            // sleutel bij een fout volledig kwijt.
            defaults.removeObject(forKey: legacyUserDefaultsKey)
            AppLoggers.userAPIKey.info("user API key gemigreerd van UserDefaults naar Keychain")
        } catch {
            AppLoggers.userAPIKey.error("migratie faalde, UserDefaults-entry blijft staan: \(error.localizedDescription, privacy: .public)")
        }
    }
}
