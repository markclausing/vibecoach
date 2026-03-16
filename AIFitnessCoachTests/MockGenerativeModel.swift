import Foundation
@testable import AIFitnessCoach
import GoogleGenerativeAI

/// Een mock implementatie van de AI voor het unit testen
class MockGenerativeModel: GenerativeModelProtocol {
    var responseToReturn: String?
    var delay: TimeInterval = 0.5
    var shouldThrowError: Bool = false

    enum MockError: Error {
        case genericError
    }

    var receivedParts: [ModelContent.Part] = []

    func generateContent(_ parts: [ModelContent.Part]) async throws -> String? {
        receivedParts = parts

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if shouldThrowError {
            throw MockError.genericError
        }

        return responseToReturn
    }
}
