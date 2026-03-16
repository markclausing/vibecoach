import Foundation
@testable import AIFitnessCoach

final class MockTokenStore: TokenStore {
    var tokens: [String: String] = [:]

    func saveToken(_ token: String, forService service: String) throws {
        tokens[service] = token
    }

    func getToken(forService service: String) throws -> String? {
        return tokens[service]
    }

    func deleteToken(forService service: String) throws {
        tokens.removeValue(forKey: service)
    }
}
