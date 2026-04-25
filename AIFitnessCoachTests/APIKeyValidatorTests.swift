import XCTest
import GoogleGenerativeAI
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

    // MARK: - classify: GenerateContentError-paden

    func testClassify_InvalidAPIKey_ReturnsInvalidKey() {
        let error: GenerateContentError = .invalidAPIKey(message: "API key not valid")
        XCTAssertEqual(APIKeyValidator.classify(error), .invalidKey)
    }

    func testClassify_InternalError_ReturnsRateLimited() {
        // .internalError wraps een onderliggende fout (503/429 van Google).
        // De wrapper-fout zelf maakt niet uit voor de classificatie.
        let underlying = NSError(domain: "GeminiTest", code: 503, userInfo: nil)
        let error = GenerateContentError.internalError(underlying: underlying)
        XCTAssertEqual(APIKeyValidator.classify(error), .rateLimited,
                       "503/429 hoort als rateLimited te classificeren — sleutel kan geldig zijn.")
    }

    func testClassify_PromptBlocked_ReturnsUnknown() {
        // `promptBlocked` heeft een associated value (`response`) — voor de
        // classificatie irrelevant; we verifiëren alleen de default-tak.
        // Het resultaat moet `.unknown` zijn met een niet-lege beschrijving.
        let blockedError = GenerateContentError.promptBlocked(response: GenerateContentResponse(candidates: []))
        let result = APIKeyValidator.classify(blockedError)
        guard case .unknown(let message) = result else {
            return XCTFail("Verwachtte .unknown, kreeg \(result)")
        }
        XCTAssertFalse(message.isEmpty,
                       "Voor unknown-paden moet er een (verkorte) beschrijving worden meegegeven.")
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
