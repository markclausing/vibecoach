import Foundation
@testable import AIFitnessCoach

class MockNetworkSession: NetworkSession {
    var dataToReturn: Data?
    var responseToReturn: URLResponse?
    var errorToThrow: Error?

    // For handling multiple requests in sequence (e.g. refresh then fetch)
    var sequenceResponses: [(Data, URLResponse)] = []
    var callCount = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1

        if let error = errorToThrow {
            throw error
        }

        if !sequenceResponses.isEmpty {
            return sequenceResponses.removeFirst()
        }

        guard let data = dataToReturn, let response = responseToReturn else {
            throw URLError(.badServerResponse)
        }

        return (data, response)
    }
}
