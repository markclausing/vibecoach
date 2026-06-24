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
            // M-4: device-only accessibility. The item is readable only while the
            // device is unlocked AND never leaves this device — it is excluded from
            // encrypted backups and from a restore onto another device. All secrets
            // stored here (Strava access/refresh/expiry tokens + BYOK API keys) are
            // re-derivable on a fresh install (re-auth Strava, re-enter the key), so
            // device-only storage costs the user nothing and removes the long-lived
            // refresh token + billable key from backups entirely.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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
