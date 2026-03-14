import Foundation
import GoogleGenerativeAI

/// Een protocol dat de benodigde functionaliteiten van het Generative AI-model abstraheert.
/// Dit stelt ons in staat om de daadwerkelijke implementatie te vervangen door een mock voor Unit Testing.
public protocol GenerativeModelProtocol {
    /// Genereert content op basis van de meegeleverde array van input types (Strings, UIImages, etc).
    ///
    /// - Parameter parts: Een array van typen die `PartsRepresentable` conformeren.
    /// - Returns: Een tekstuele reactie gegenereerd door het AI-model.
    func generateContent(_ parts: [any PartsRepresentable]) async throws -> String?
}

/// Een wrapper rondom de officiële `GoogleGenerativeAI.GenerativeModel`
/// om te voldoen aan het `GenerativeModelProtocol`.
public struct RealGenerativeModel: GenerativeModelProtocol {
    private let model: GenerativeModel

    /// Creëert een nieuwe instantie op basis van het achterliggende Google model.
    public init(model: GenerativeModel) {
        self.model = model
    }

    public func generateContent(_ parts: [any PartsRepresentable]) async throws -> String? {
        // We mappen de array direct door naar de SDK method.
        // Omdat GenerativeModel.generateContent(_ parts: any ThrowingPartsRepresentable...) een variadische
        // functie is en [any PartsRepresentable] een array is, roepen we de [ModelContent] overlaad aan.
        let modelParts = parts.flatMap { $0.partsValue }
        let modelContent = ModelContent(role: "user", parts: modelParts)
        let response = try await model.generateContent([modelContent])
        return response.text
    }
}
