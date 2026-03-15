import Foundation
import GoogleGenerativeAI

/// Een protocol dat de benodigde functionaliteiten van het Generative AI-model abstraheert.
/// Dit stelt ons in staat om de daadwerkelijke implementatie te vervangen door een mock voor Unit Testing.
public protocol GenerativeModelProtocol {
    /// Genereert content op basis van de meegeleverde input parts.
    ///
    /// - Parameter parts: Een array van `ModelContent` representaties.
    /// - Returns: Een tekstuele reactie gegenereerd door het AI-model.
    func generateContent(from parts: [ModelContent]) async throws -> String?
}

/// Een wrapper rondom de officiële `GoogleGenerativeAI.GenerativeModel`
/// om te voldoen aan het `GenerativeModelProtocol`.
public struct RealGenerativeModel: GenerativeModelProtocol {
    private let model: GenerativeModel

    /// Creëert een nieuwe instantie op basis van het achterliggende Google model.
    public init(model: GenerativeModel) {
        self.model = model
    }

    public func generateContent(from parts: [ModelContent]) async throws -> String? {
        let response = try await model.generateContent(parts)
        return response.text
    }
}
