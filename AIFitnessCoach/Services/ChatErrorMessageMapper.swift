import Foundation

/// Epic #51-A5: translates raw SDK/network errors into specific, actionable
/// user messages. Previously most non-Gemini errors were presented as one
/// generic *"There is a temporary problem"* — users could therefore not
/// distinguish offline situations, blocked keys and provider overload,
/// and did not know what to do.
///
/// Pure-Swift, no framework deps at the Gemini-SDK type level (the SDK is
/// optionally available; we match on `Error.localizedDescription` and
/// `URLError` codes so tests can run without a network and without the SDK).
enum ChatErrorMessageMapper {

    /// Generates the text shown in the chat bubble + dashboard banner
    /// on a failed AI call. The caller decides, based on the error type, whether
    /// the helpers first try a fallback model (see ChatViewModel) —
    /// this mapper is for the final message after all attempts fail.
    static func userFacingMessage(for error: Error) -> String {
        // Epic #53: our own provider error from the OpenAI/Claude/Mistral REST
        // clients. Typed, so the first and most specific check.
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .overloaded:           return Self.providerOverloaded
            case .authenticationFailed: return Self.invalidAPIKey
            case .contentBlocked:       return Self.promptBlocked
            case .http, .emptyResponse, .decodingFailed:
                return Self.providerGeneric
            }
        }

        // Order: most specific check first.
        if let urlError = error as? URLError {
            return message(for: urlError)
        }

        // The Gemini-SDK type `GenerateContentError` is not directly importable
        // by this module (it would create a circular dep). We
        // recognise it via the string representation of the type, which is stable
        // across SDK minor versions and testable without a real SDK instance.
        let typeName = String(describing: type(of: error))
        if typeName.contains("GenerateContentError") {
            return message(forGenerateContentErrorDescription: String(describing: error))
        }

        let description = error.localizedDescription.lowercased()
        if description.contains("offline") || description.contains("internet") {
            return Self.networkOffline
        }
        if description.contains("timeout") || description.contains("timed out") {
            return Self.networkTimeout
        }

        return Self.generic
    }

    // MARK: - URLError mapping

    private static func message(for urlError: URLError) -> String {
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dataNotAllowed:
            return Self.networkOffline
        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return Self.networkHostUnreachable
        case .timedOut:
            return Self.networkTimeout
        case .cancelled:
            return Self.requestCancelled
        default:
            return Self.networkUnknown
        }
    }

    // MARK: - GenerateContentError mapping

    /// Matches on the String representation of a `GenerateContentError` case
    /// so we don't depend on the exact SDK type. Stable across
    /// SDK minor versions.
    private static func message(forGenerateContentErrorDescription raw: String) -> String {
        let lowered = raw.lowercased()
        if lowered.contains("promptblocked") || lowered.contains("safety") {
            return Self.promptBlocked
        }
        if lowered.contains("invalidapikey") || lowered.contains("api key") || lowered.contains("api-sleutel") {
            return Self.invalidAPIKey
        }
        if lowered.contains("internalerror") || lowered.contains("503") || lowered.contains("429") || lowered.contains("overbelast") {
            return Self.providerOverloaded
        }
        return Self.providerGeneric
    }

    // MARK: - Fixed texts

    static let networkOffline =
        "Geen internet — controleer je verbinding en probeer opnieuw."

    static let networkHostUnreachable =
        "Geen verbinding met de AI-provider. Controleer of je internet werkt (VPN, captive portal?) en probeer opnieuw."

    static let networkTimeout =
        "De verbinding met de AI-provider is te traag. Probeer het over een paar seconden opnieuw."

    static let networkUnknown =
        "Netwerkprobleem — controleer je verbinding en probeer opnieuw."

    static let requestCancelled =
        "Verzoek geannuleerd. Stuur je bericht opnieuw als je een antwoord wilt."

    static let promptBlocked =
        "Dit bericht is geblokkeerd door de veiligheidsfilters van de AI. Herformuleer je vraag of focus op je training/herstel."

    static let invalidAPIKey =
        "Je API-sleutel werkt niet meer. Open Instellingen → AI Coach Configuratie om hem opnieuw in te voeren."

    static let providerOverloaded =
        "De AI-provider is tijdelijk overbelast. Wacht 30 seconden en probeer opnieuw."

    static let providerGeneric =
        "De AI-provider gaf een onverwachte fout terug. Probeer het opnieuw."

    static let generic =
        "Er ging iets mis bij het versturen. Probeer het opnieuw."
}
