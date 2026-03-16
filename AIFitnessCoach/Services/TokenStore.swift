import Foundation

/// Protocol voor de veilige opslag en manipulatie van API tokens (zoals Strava, Intervals.icu).
/// Door een protocol te gebruiken, is de Keychain logica mockbaar voor unit tests.
protocol TokenStore {
    func saveToken(_ token: String, forService service: String) throws
    func getToken(forService service: String) throws -> String?
    func deleteToken(forService service: String) throws
}

/// Native Keychain error definities.
enum KeychainError: Error {
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case unhandledError(status: OSStatus)
    case itemNotFound
}
