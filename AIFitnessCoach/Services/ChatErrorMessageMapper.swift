import Foundation

/// Epic #51-A5: vertaalt ruwe SDK-/netwerkfouten naar specifieke, actionable
/// gebruikers-meldingen. Voorheen werden de meeste niet-Gemini-fouten als één
/// generieke *"Er is een tijdelijk probleem"* gepresenteerd — gebruikers konden
/// daardoor offline-situaties, geblokkeerde sleutels en provider-overbelasting
/// niet uit elkaar houden, en wisten niet wat ze moesten doen.
///
/// Pure-Swift, geen framework-deps op het Gemini-SDK-type-niveau (de SDK is
/// optioneel beschikbaar; we matchen op `Error.localizedDescription` en
/// `URLError`-codes zodat tests zonder netwerk + zonder SDK kunnen draaien).
enum ChatErrorMessageMapper {

    /// Genereert de tekst die in de chat-bubble + dashboard-banner verschijnt
    /// bij een mislukte AI-call. Caller bepaalt op basis van het type fout of
    /// de helpers eerst een fallback-model proberen (zie ChatViewModel) —
    /// deze mapper is voor de definitieve melding nadat alle pogingen falen.
    static func userFacingMessage(for error: Error) -> String {
        // Epic #53: onze eigen provider-fout van de OpenAI/Claude/Mistral REST-
        // clients. Getypeerd, dus de eerste en meest specifieke check.
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .overloaded:           return Self.providerOverloaded
            case .authenticationFailed: return Self.invalidAPIKey
            case .contentBlocked:       return Self.promptBlocked
            case .http, .emptyResponse, .decodingFailed:
                return Self.providerGeneric
            }
        }

        // Volgorde: meest specifieke check eerst.
        if let urlError = error as? URLError {
            return message(for: urlError)
        }

        // Het Gemini-SDK-type `GenerateContentError` is niet door dit module
        // direct importeerbaar (zou een circulaire dep opleveren). We
        // herkennen 'm via de stringrepresentatie van het type, wat stabiel
        // is over SDK-minor-versies en testbaar zonder echte SDK-instantie.
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

    // MARK: - URLError-mapping

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

    // MARK: - GenerateContentError-mapping

    /// Matcht op de String-representatie van een `GenerateContentError`-case
    /// zodat we niet afhankelijk zijn van het exacte SDK-type. Stabiel over
    /// SDK-minor-versies.
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

    // MARK: - Vaste teksten

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
