import Foundation
@testable import AIFitnessCoach

class MockNetworkSession: NetworkSession {
    var dataToReturn: Data?
    var responseToReturn: URLResponse?
    var errorToThrow: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = errorToThrow {
            throw error
        }

        guard let data = dataToReturn, let response = responseToReturn else {
            throw URLError(.badServerResponse)
        }

        return (data, response)
    }
}
