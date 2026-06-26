import Foundation

/// Epic #51-A5: translates raw errors into specific, actionable user messages.
/// Previously most non-Gemini errors were presented as one generic message —
/// users could not distinguish offline situations, blocked keys and provider
/// overload, and did not know what to do.
///
/// Story 61.8: removed the `GenerateContentError` string-matching branch — after
/// migrating Gemini to `GeminiRestClient`, all four providers throw `AIProviderError`
/// so the typed check is exhaustive.
enum ChatErrorMessageMapper {

    /// Generates the text shown in the chat bubble + dashboard banner
    /// on a failed AI call. The caller decides, based on the error type, whether
    /// to first try a fallback model (see ChatViewModel) —
    /// this mapper is for the final message after all attempts fail.
    static func userFacingMessage(for error: Error) -> String {
        // All four providers (Gemini/OpenAI/Anthropic/Mistral) throw AIProviderError.
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .overloaded:           return Self.providerOverloaded
            case .authenticationFailed: return Self.invalidAPIKey
            case .contentBlocked:       return Self.promptBlocked
            case .http, .emptyResponse, .decodingFailed:
                return Self.providerGeneric
            }
        }

        if let urlError = error as? URLError {
            return message(for: urlError)
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
