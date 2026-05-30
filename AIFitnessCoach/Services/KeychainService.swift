import Foundation
import Security

/// Implements a simple, native wrapper over the iOS Keychain C API for storing sensitive data.
final class KeychainService: TokenStore {

    // Default instance for production
    static let shared = KeychainService()

    private init() {}

    func saveToken(_ token: String, forService service: String) throws {
        guard let tokenData = token.data(using: .utf8) else { return }

        // The delete query must NOT contain the specific new tokenData (kSecValueData) or accessibility,
        // otherwise the delete does not match the old stored token and you get a duplicate item error (-25299) on SecItemAdd.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service,
            kSecValueData as String: tokenData,
            // Stored data is only accessible while the device is unlocked.
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
