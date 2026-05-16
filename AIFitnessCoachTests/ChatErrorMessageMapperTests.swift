import XCTest
@testable import AIFitnessCoach

/// Epic #51-A5: borgt dat de mapper voor elke fout-categorie de juiste
/// specifieke melding teruggeeft. Voorheen werden de meeste niet-Gemini-fouten
/// als één generieke *"Er is een tijdelijk probleem"* gepresenteerd; deze suite
/// dekt de discriminatie tussen offline / timeout / DNS / safety / invalid-key /
/// overbelast / generiek af.
final class ChatErrorMessageMapperTests: XCTestCase {

    // MARK: - URLError-mapping

    func testNotConnectedToInternetMapsToOffline() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertEqual(ChatErrorMessageMapper.userFacingMessage(for: error), ChatErrorMessageMapper.networkOffline)
    }

    func testNetworkConnectionLostMapsToOffline() {
        let error = URLError(.networkConnectionLost)
        XCTAssertEqual(ChatErrorMessageMapper.userFacingMessage(for: error), ChatErrorMessageMapper.networkOffline)
    }

    func testTimedOutMapsToTimeoutMessage() {
        let error = URLError(.timedOut)
        XCTAssertEqual(ChatErrorMessageMapper.userFacingMessage(for: error), ChatErrorMessageMapper.networkTimeout)
    }

    func testDNSFailureMapsToHostUnreachable() {
        XCTAssertEqual(
            ChatErrorMessageMapper.userFacingMessage(for: URLError(.cannotFindHost)),
            ChatErrorMessageMapper.networkHostUnreachable
        )
        XCTAssertEqual(
            ChatErrorMessageMapper.userFacingMessage(for: URLError(.dnsLookupFailed)),
            ChatErrorMessageMapper.networkHostUnreachable
        )
    }

    func testCancelledMapsToRequestCancelled() {
        XCTAssertEqual(
            ChatErrorMessageMapper.userFacingMessage(for: URLError(.cancelled)),
            ChatErrorMessageMapper.requestCancelled
        )
    }

    func testUnknownURLErrorMapsToNetworkUnknown() {
        // Een URLError-code die niet expliciet wordt afgehandeld
        XCTAssertEqual(
            ChatErrorMessageMapper.userFacingMessage(for: URLError(.badURL)),
            ChatErrorMessageMapper.networkUnknown
        )
    }

    // MARK: - GenerateContentError-mapping (via type-name-string)

    /// Faux-class met dezelfde naam als het Gemini-SDK-type. De mapper matcht
    /// op `String(describing: type(of: error))` zodat we de echte SDK niet
    /// hoeven te koppelen in deze test.
    private final class GenerateContentError_PromptBlocked: Error {
        var localizedDescription: String { "promptBlocked: safety filter" }
    }

    private final class GenerateContentError_InvalidAPIKey: Error {
        var localizedDescription: String { "invalidAPIKey: missing api key" }
    }

    private final class GenerateContentError_InternalError: Error {
        var localizedDescription: String { "internalError 503 overload" }
    }

    private final class GenerateContentError_Generic: Error {
        var localizedDescription: String { "something else" }
    }

    func testPromptBlockedMapsToScopeAwareMessage() {
        let msg = ChatErrorMessageMapper.userFacingMessage(for: GenerateContentError_PromptBlocked())
        XCTAssertEqual(msg, ChatErrorMessageMapper.promptBlocked)
        XCTAssertTrue(msg.contains("veiligheidsfilters"))
    }

    func testInvalidAPIKeyDirectsUserToSettings() {
        let msg = ChatErrorMessageMapper.userFacingMessage(for: GenerateContentError_InvalidAPIKey())
        XCTAssertEqual(msg, ChatErrorMessageMapper.invalidAPIKey)
        XCTAssertTrue(msg.contains("Instellingen"))
    }

    func testInternalErrorMapsToProviderOverloaded() {
        let msg = ChatErrorMessageMapper.userFacingMessage(for: GenerateContentError_InternalError())
        XCTAssertEqual(msg, ChatErrorMessageMapper.providerOverloaded)
        XCTAssertTrue(msg.contains("30"))
    }

    func testGenericGenerateContentErrorFallsBackToProviderGeneric() {
        let msg = ChatErrorMessageMapper.userFacingMessage(for: GenerateContentError_Generic())
        XCTAssertEqual(msg, ChatErrorMessageMapper.providerGeneric)
    }

    // MARK: - Onbekende error

    private struct UnknownError: LocalizedError {
        var errorDescription: String? { "Something exotic happened" }
    }

    func testCompletelyUnknownErrorFallsBackToGeneric() {
        XCTAssertEqual(
            ChatErrorMessageMapper.userFacingMessage(for: UnknownError()),
            ChatErrorMessageMapper.generic
        )
    }

    /// Bevestigt dat de specifieke meldingen anders zijn dan elkaar — voorkomt
    /// dat een toekomstige edit per ongeluk twee categorieën samenvoegt tot
    /// dezelfde string (regressie naar "er is een tijdelijk probleem").
    func testAllMessagesAreDistinct() {
        let messages: Set<String> = [
            ChatErrorMessageMapper.networkOffline,
            ChatErrorMessageMapper.networkTimeout,
            ChatErrorMessageMapper.networkHostUnreachable,
            ChatErrorMessageMapper.networkUnknown,
            ChatErrorMessageMapper.requestCancelled,
            ChatErrorMessageMapper.promptBlocked,
            ChatErrorMessageMapper.invalidAPIKey,
            ChatErrorMessageMapper.providerOverloaded,
            ChatErrorMessageMapper.providerGeneric,
            ChatErrorMessageMapper.generic
        ]
        XCTAssertEqual(messages.count, 10, "Elke fout-categorie moet een unieke gebruikersmelding hebben.")
    }
}
