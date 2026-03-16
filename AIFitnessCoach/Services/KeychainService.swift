import Foundation
import Security

/// Implementeert een simpele, native wrapper over iOS Keychain C-API voor opslaan van gevoelige gegevens.
final class KeychainService: TokenStore {

    // Standaard instantie voor productie
    static let shared = KeychainService()

    private init() {}

    func saveToken(_ token: String, forService service: String) throws {
        guard let tokenData = token.data(using: .utf8) else { return }

        // De query voor het verwijderen mag NIET de specifieke nieuwe tokenData (kSecValueData) of accessibility bevatten,
        // anders matcht de delete-functie de oude opgeslagen token niet en krijg je een duplicate item error (-25299) bij SecItemAdd.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service,
            kSecValueData as String: tokenData,
            // Opslaan is alleen toegankelijk wanneer het apparaat ontgrendeld is.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    func getToken(forService service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess {
            if let data = dataTypeRef as? Data, let token = String(data: data, encoding: .utf8) {
                return token
            }
        } else if status == errSecItemNotFound {
            return nil
        }

        throw KeychainError.unhandledError(status: status)
    }

    func deleteToken(forService service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}
