import Foundation

/// Protocol for the secure storage and manipulation of API tokens (such as Strava, Intervals.icu).
/// Using a protocol makes the Keychain logic mockable for unit tests.
protocol TokenStore {
    func saveToken(_ token: String, forService service: String) throws
    func getToken(forService service: String) throws -> String?
    func deleteToken(forService service: String) throws
}

/// Native Keychain error definitions.
enum KeychainError: Error {
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case unhandledError(status: OSStatus)
    case itemNotFound
}
