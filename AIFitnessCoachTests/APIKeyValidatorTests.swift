import XCTest
@testable import AIFitnessCoach

/// Epic #36 sub-task 36.3 — dekt de BYOK API-sleutel validatie. De daadwerkelijke
/// `validateGeminiKey()`-call is niet zonder netwerk te driven omdat hij direct
/// een `GenerativeModel` instantieert; daarom valideren we (a) de input-guards
/// en (b) de geëxtraheerde `classify(_:)` foutmapper, die alle scenario's bevat
/// waarop de UI-state-machine reageert.
final class APIKeyValidatorTests: XCTestCase {

    // MARK: - validateGeminiKey input guards

    func testValidate_EmptyKey_ReturnsInvalidKey() async {
        let result = await APIKeyValidator.validateGeminiKey("")
        XCTAssertEqual(result, .invalidKey,
                       "Een lege string mag nooit een API-call triggeren — meteen invalidKey terug.")
    }

    func testValidate_WhitespaceOnlyKey_ReturnsInvalidKey() async {
        let result = await APIKeyValidator.validateGeminiKey("   \n\t  ")
        XCTAssertEqual(result, .invalidKey,
                       "Pure whitespace moet als 'leeg' worden geïnterpreteerd na trim.")
    }

    // MARK: - classify: AIProviderError-paden (Epic #53)

    func testClassify_ProviderAuthFailed_ReturnsInvalidKey() {
        XCTAssertEqual(APIKeyValidator.classify(AIProviderError.authenticationFailed), .invalidKey)
    }

    func testClassify_ProviderOverloaded_ReturnsRateLimited() {
        XCTAssertEqual(APIKeyValidator.classify(AIProviderError.overloaded), .rateLimited)
    }

    func testClassify_ProviderHTTP_ReturnsUnknown() {
        guard case .unknown = APIKeyValidator.classify(AIProviderError.http(status: 500, message: "boom")) else {
            return XCTFail("HTTP 500 hoort .unknown te zijn.")
        }
    }

    // MARK: - classify: URLError-paden (netwerk)

    func testClassify_URLError_NotConnected_ReturnsNetwork() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertEqual(APIKeyValidator.classify(error), .network)
    }

    func testClassify_URLError_TimedOut_ReturnsNetwork() {
        let error = URLError(.timedOut)
        XCTAssertEqual(APIKeyValidator.classify(error), .network)
    }

    func testClassify_URLError_NetworkConnectionLost_ReturnsNetwork() {
        let error = URLError(.networkConnectionLost)
        XCTAssertEqual(APIKeyValidator.classify(error), .network)
    }

    func testClassify_URLError_DNSFailure_ReturnsNetwork() {
        let error = URLError(.dnsLookupFailed)
        XCTAssertEqual(APIKeyValidator.classify(error), .network)
    }

    func testClassify_URLError_OtherCode_ReturnsUnknown() {
        // Een minder-bekende URLError-code (bijv. .badServerResponse) hoort
        // als unknown te classificeren — we willen alleen écht netwerk-loze
        // gevallen als .network markeren.
        let error = URLError(.badServerResponse)
        let result = APIKeyValidator.classify(error)
        guard case .unknown = result else {
            return XCTFail("URLError.badServerResponse hoort .unknown te zijn, kreeg \(result)")
        }
    }

    // MARK: - classify: generieke Error fallback

    func testClassify_GenericError_ReturnsUnknown() {
        let error = NSError(
            domain: "VibeCoachTest",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Iets onverwachts"]
        )
        let result = APIKeyValidator.classify(error)
        guard case .unknown(let message) = result else {
            return XCTFail("Verwachtte .unknown voor een willekeurige NSError, kreeg \(result)")
        }
        XCTAssertEqual(message, "Iets onverwachts",
                       "De originele localizedDescription moet doorgegeven worden zodat de UI 'm kan tonen.")
    }

    // MARK: - APIKeyValidationResult Equatable contract

    /// `APIKeyValidationResult` heeft een associated value op `.unknown(String)`.
    /// We pinnen het Equatable-contract vast zodat een refactor van de cases
    /// niet stil de gelijkheidstesten van de UI-state-machine breekt.
    func testValidationResult_Equatable_DistinguishesUnknownByMessage() {
        XCTAssertEqual(APIKeyValidationResult.unknown("a"), .unknown("a"))
        XCTAssertNotEqual(APIKeyValidationResult.unknown("a"), .unknown("b"))
        XCTAssertNotEqual(APIKeyValidationResult.invalidKey, .network)
        XCTAssertNotEqual(APIKeyValidationResult.valid, .rateLimited)
    }
}
