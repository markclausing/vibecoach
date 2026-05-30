import Foundation

// MARK: - Epic #53: Provider-neutrale abstractie

/// Een SDK-onafhankelijke representatie van één onderdeel van een AI-prompt.
/// Vóór Epic #53 leunde het protocol direct op `GoogleGenerativeAI.ModelContent.Part`,
/// waardoor de hele inferentie-laag aan Gemini vastzat. Dit value-type ontkoppelt
/// de call-sites van de SDK zodat OpenAI/Claude/Mistral-clients hetzelfde protocol
/// kunnen implementeren. Iedere provider-client mapt deze parts naar zijn eigen
/// wire-formaat (zie `AIModelFactory`).
public enum AIPromptPart {
    /// Platte tekst (de gebruikersvraag + geïnjecteerde context-prefix).
    case text(String)
    /// Binaire afbeeldingsdata met bijbehorende MIME-type (bijv. `image/jpeg`).
    case imageData(Data, mimeType: String)
}

/// Provider-agnostische fout die de REST-clients (OpenAI/Claude/Mistral) gooien.
/// `ChatViewModel`, `WorkoutInsightService` en `ChatErrorMessageMapper` mappen deze
/// naar de juiste fallback-/UI-afhandeling, zodat de 503/429-waterfall en de
/// auth-foutdetectie niet langer Gemini-SDK-specifiek zijn.
///
/// Transport-fouten (offline, timeout, DNS) worden bewust **niet** in dit type
/// gevangen — die laten we als `URLError` doorbubbelen zodat de bestaande
/// `ChatErrorMessageMapper`-URLError-mapping ze afhandelt.
public enum AIProviderError: Error, Equatable {
    /// HTTP 429/503/529 — provider tijdelijk overbelast. Triggert de fallback-waterfall.
    case overloaded
    /// HTTP 401/403 of een ongeldige/ingetrokken sleutel.
    case authenticationFailed
    /// De respons werd door een veiligheidsfilter geblokkeerd.
    case contentBlocked
    /// Een andere niet-2xx-statuscode.
    case http(status: Int)
    /// 2xx, maar geen bruikbare tekst in de respons-body.
    case emptyResponse
    /// De respons-body kon niet ontleed worden naar het verwachte JSON-schema.
    case decodingFailed
}

extension AIProviderError {
    /// True als een fout een tijdelijke overbelasting is en het zin heeft om het
    /// fallback-model te proberen. Herkent zowel onze eigen `.overloaded` als de
    /// Gemini-SDK `GenerateContentError.internalError` (via stringrepresentatie,
    /// zodat dit module geen `import GoogleGenerativeAI` nodig heeft).
    public static func isOverload(_ error: Error) -> Bool {
        if let providerError = error as? AIProviderError, providerError == .overloaded {
            return true
        }
        let description = String(describing: error).lowercased()
        return description.contains("internalerror")
            || description.contains("503")
            || description.contains("429")
            || description.contains("529")
    }
}

/// Een protocol dat de benodigde functionaliteiten van een Generatief AI-model
/// abstraheert. Dit stelt ons in staat om de implementatie te vervangen door een
/// mock voor Unit Testing, én om per provider (Gemini/OpenAI/Claude/Mistral) een
/// eigen client achter hetzelfde contract te zetten.
public protocol GenerativeModelProtocol {
    /// Genereert content op basis van de meegeleverde, SDK-onafhankelijke parts.
    ///
    /// - Parameter parts: Een array van `AIPromptPart` (tekst en/of afbeeldingen).
    /// - Returns: Een tekstuele reactie gegenereerd door het AI-model.
    func generateContent(_ parts: [AIPromptPart]) async throws -> String?
}

/// Marker-protocol voor een échte provider-client (geen test-mock). `ChatViewModel`
/// gebruikt dit om de API-sleutel-gate (`hasAPIKey`) uitsluitend op live clients toe
/// te passen — geïnjecteerde mocks (`MockGenerativeModel`, `UITestMockGenerativeModel`)
/// conformeren bewust niet, zodat tests niet op een ontbrekende sleutel struikelen.
public protocol RealAIProviderClient {}
