import XCTest
@testable import AIFitnessCoach

/// Unit tests voor StravaAuthService (Epic 27).
///
/// Dekt vier scenario's:
///   1. checkAuthStatus — met en zonder opgeslagen token
///   2. logout — tokens worden gewist uit de store
///   3. exchangeCodeForToken — succesvolle OAuth flow (mock JSON + 200)
///   4. exchangeCodeForToken — netwerk- en HTTP-fouten
@MainActor
final class StravaAuthServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Bouwt een HTTPURLResponse met de gegeven statuscode voor de token-endpoint.
    private func httpResponse(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://www.strava.com/oauth/token")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    /// Geldige Strava token JSON response.
    private func validTokenJSON(
        accessToken: String = "test_access_token",
        refreshToken: String = "test_refresh_token",
        expiresAt: Int = 9999999999
    ) -> Data {
        """
        {
          "access_token": "\(accessToken)",
          "refresh_token": "\(refreshToken)",
          "expires_at": \(expiresAt)
        }
        """.data(using: .utf8)!
    }

    // MARK: - 1. checkAuthStatus

    func testCheckAuthStatus_WithToken_IsAuthenticated() throws {
        // Given: een geldig token in de store
        let store = MockTokenStore()
        try store.saveToken("valid_token", forService: "StravaToken")

        // When
        let service = StravaAuthService(tokenStore: store)

        // Then
        XCTAssertTrue(service.isAuthenticated, "Met een opgeslagen token moet isAuthenticated true zijn.")
    }

    func testCheckAuthStatus_WithoutToken_IsNotAuthenticated() {
        // Given: lege token store
        let store = MockTokenStore()

        // When
        let service = StravaAuthService(tokenStore: store)

        // Then
        XCTAssertFalse(service.isAuthenticated, "Zonder token moet isAuthenticated false zijn.")
    }

    // MARK: - 2. logout

    func testLogout_ClearsAllTokensAndSetsNotAuthenticated() throws {
        // Given: alle drie Strava tokens aanwezig
        let store = MockTokenStore()
        try store.saveToken("access",  forService: "StravaToken")
        try store.saveToken("refresh", forService: "StravaRefreshToken")
        try store.saveToken("123456",  forService: "StravaTokenExpiresAt")
        let service = StravaAuthService(tokenStore: store)
        XCTAssertTrue(service.isAuthenticated)

        // When
        service.logout()

        // Then: alle tokens verwijderd, sessie beëindigd
        XCTAssertFalse(service.isAuthenticated)
        XCTAssertNil(try store.getToken(forService: "StravaToken"))
        XCTAssertNil(try store.getToken(forService: "StravaRefreshToken"))
        XCTAssertNil(try store.getToken(forService: "StravaTokenExpiresAt"))
    }

    // MARK: - 3. exchangeCodeForToken: succes

    func testExchangeCodeForToken_ValidResponse_SetsAuthenticated() async throws {
        // Given: mock netwerk geeft geldige JSON terug met status 200
        let store   = MockTokenStore()
        let network = MockNetworkSession()
        network.dataToReturn     = validTokenJSON()
        network.responseToReturn = httpResponse(status: 200)
        let service = StravaAuthService(tokenStore: store, session: network)

        // When
        await service.exchangeCodeForToken(code: "auth_code_abc")

        // Then: tokens opgeslagen, sessie actief, geen fout
        XCTAssertTrue(service.isAuthenticated,  "Na succesvolle exchange moet isAuthenticated true zijn.")
        XCTAssertNil(service.authError,         "Geen authError verwacht bij succesvolle exchange.")
        XCTAssertEqual(try store.getToken(forService: "StravaToken"),          "test_access_token")
        XCTAssertEqual(try store.getToken(forService: "StravaRefreshToken"),   "test_refresh_token")
        XCTAssertEqual(try store.getToken(forService: "StravaTokenExpiresAt"), "9999999999")
    }

    func testExchangeCodeForToken_ValidResponse_TokensStoredCorrectly() async throws {
        // Given: andere token-waarden om te verifiëren dat exact de JSON-waarden worden opgeslagen
        let store   = MockTokenStore()
        let network = MockNetworkSession()
        network.dataToReturn     = validTokenJSON(accessToken: "acc123", refreshToken: "ref456", expiresAt: 1700000000)
        network.responseToReturn = httpResponse(status: 200)
        let service = StravaAuthService(tokenStore: store, session: network)

        // When
        await service.exchangeCodeForToken(code: "some_code")

        // Then: de exacte waarden uit de JSON staan in de keychain
        XCTAssertEqual(try store.getToken(forService: "StravaToken"),          "acc123")
        XCTAssertEqual(try store.getToken(forService: "StravaRefreshToken"),   "ref456")
        XCTAssertEqual(try store.getToken(forService: "StravaTokenExpiresAt"), "1700000000")
    }

    // MARK: - 4. exchangeCodeForToken: fouten

    func testExchangeCodeForToken_NetworkError_SetsAuthError() async {
        // Given: netwerk gooit een URLError
        let store   = MockTokenStore()
        let network = MockNetworkSession()
        network.errorToThrow = URLError(.notConnectedToInternet)
        let service = StravaAuthService(tokenStore: store, session: network)

        // When
        await service.exchangeCodeForToken(code: "code_xyz")

        // Then: authError is gezet, niet geauthenticeerd
        XCTAssertFalse(service.isAuthenticated, "Na een netwerk-fout mag de sessie niet actief zijn.")
        XCTAssertNotNil(service.authError,      "authError moet worden gezet bij een netwerk-fout.")
    }

    func testExchangeCodeForToken_HTTP401_SetsAuthError() async {
        // Given: server antwoordt met 401 Unauthorized
        let store   = MockTokenStore()
        let network = MockNetworkSession()
        network.dataToReturn     = Data()
        network.responseToReturn = httpResponse(status: 401)
        let service = StravaAuthService(tokenStore: store, session: network)

        // When
        await service.exchangeCodeForToken(code: "expired_code")

        // Then: authError bevat de statuscode, niet geauthenticeerd
        XCTAssertFalse(service.isAuthenticated)
        XCTAssertNotNil(service.authError, "authError moet worden gezet bij HTTP 401.")
        XCTAssertTrue(service.authError?.contains("401") == true,
                      "authError moet de HTTP statuscode 401 vermelden.")
    }

    func testExchangeCodeForToken_HTTP500_SetsAuthError() async {
        // Given: server-fout 500
        let store   = MockTokenStore()
        let network = MockNetworkSession()
        network.dataToReturn     = Data()
        network.responseToReturn = httpResponse(status: 500)
        let service = StravaAuthService(tokenStore: store, session: network)

        // When
        await service.exchangeCodeForToken(code: "some_code")

        // Then
        XCTAssertFalse(service.isAuthenticated)
        XCTAssertTrue(service.authError?.contains("500") == true,
                      "authError moet de HTTP statuscode 500 vermelden.")
    }

    func testExchangeCodeForToken_MalformedJSON_SetsAuthError() async {
        // Given: server stuurt geldige 200 maar ongeldige JSON
        let store   = MockTokenStore()
        let network = MockNetworkSession()
        network.dataToReturn     = "{ not valid json }".data(using: .utf8)!
        network.responseToReturn = httpResponse(status: 200)
        let service = StravaAuthService(tokenStore: store, session: network)

        // When
        await service.exchangeCodeForToken(code: "code_abc")

        // Then: decode-fout → authError gezet, geen tokens opgeslagen
        XCTAssertFalse(service.isAuthenticated)
        XCTAssertNotNil(service.authError, "authError moet worden gezet bij ongeldige JSON.")
        XCTAssertNil(try? store.getToken(forService: "StravaToken"),
                     "Bij ongeldige JSON mogen er geen tokens zijn opgeslagen.")
    }

    func testExchangeCodeForToken_NetworkError_NoTokensSaved() async {
        // Given: netwerk-fout voordat er data ontvangen wordt
        let store   = MockTokenStore()
        let network = MockNetworkSession()
        network.errorToThrow = URLError(.timedOut)
        let service = StravaAuthService(tokenStore: store, session: network)

        // When
        await service.exchangeCodeForToken(code: "code")

        // Then: keychain blijft leeg
        XCTAssertNil(try? store.getToken(forService: "StravaToken"),
                     "Bij een netwerk-fout mogen er geen tokens zijn opgeslagen.")
    }

    // MARK: - 5. H-01: OAuth state (CSRF)

    func testMakeAuthorizationURL_IncludesStateQueryItem() {
        // Given: een willekeurige state en vaste client-gegevens
        let state = "abc-123-xyz"

        // When
        let url = StravaAuthService.makeAuthorizationURL(
            clientId: "12345",
            callbackScheme: "aifitnesscoach",
            state: state
        )

        // Then: de URL bevat exact deze state én alle andere vereiste OAuth-parameters
        XCTAssertNotNil(url)
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "state" })?.value, state)
        XCTAssertEqual(items.first(where: { $0.name == "client_id" })?.value, "12345")
        XCTAssertEqual(items.first(where: { $0.name == "response_type" })?.value, "code")
    }

    func testValidateCallbackState_MatchingState_ReturnsTrue() {
        // Given: callback-URL met een state die matcht
        let state = UUID().uuidString
        let url = URL(string: "aifitnesscoach://localhost?code=abc&state=\(state)")!

        // Then
        XCTAssertTrue(StravaAuthService.validateCallbackState(callbackURL: url, expectedState: state))
    }

    func testValidateCallbackState_MismatchingState_ReturnsFalse() {
        // Given: callback stuurt een andere state dan we hadden verzonden (CSRF-poging)
        let url = URL(string: "aifitnesscoach://localhost?code=abc&state=aanvaller-state")!

        // Then
        XCTAssertFalse(StravaAuthService.validateCallbackState(callbackURL: url, expectedState: "onze-verwachte-state"))
    }

    func testValidateCallbackState_MissingState_ReturnsFalse() {
        // Given: callback zonder state — mogelijk ouderwetse of kwaadwillende call
        let url = URL(string: "aifitnesscoach://localhost?code=abc")!

        // Then
        XCTAssertFalse(StravaAuthService.validateCallbackState(callbackURL: url, expectedState: "verwacht"))
    }

    func testValidateCallbackState_NilExpectedState_ReturnsFalse() {
        // Given: we hadden geen state gegenereerd — dan mogen we nooit een callback vertrouwen
        let url = URL(string: "aifitnesscoach://localhost?code=abc&state=xyz")!

        // Then
        XCTAssertFalse(StravaAuthService.validateCallbackState(callbackURL: url, expectedState: nil))
    }

    func testValidateCallbackState_EmptyExpectedState_ReturnsFalse() {
        // Given: lege string als verwachte state — zelfde semantiek als nil
        let url = URL(string: "aifitnesscoach://localhost?code=abc&state=")!

        // Then
        XCTAssertFalse(StravaAuthService.validateCallbackState(callbackURL: url, expectedState: ""))
    }
}

/// M-08: tests voor de notification-payload whitelist.
/// Verifieert dat alleen onze eigen payload-vormen worden toegelaten en
/// dat onbekende of gemanipuleerde payloads netjes genegeerd worden.
final class NotificationPayloadWhitelistTests: XCTestCase {

    func testAllowed_TypeGoalRisk_ReturnsTrue() {
        let payload: [AnyHashable: Any] = ["type": "goalRisk"]
        XCTAssertTrue(AppDelegate.isAllowedNotificationPayload(payload))
    }

    func testAllowed_TypeRecoveryPlan_ReturnsTrue() {
        let payload: [AnyHashable: Any] = ["type": "recovery_plan"]
        XCTAssertTrue(AppDelegate.isAllowedNotificationPayload(payload))
    }

    func testDenied_UnknownType_ReturnsFalse() {
        // Type die wij niet ondersteunen — moet stil worden genegeerd
        let payload: [AnyHashable: Any] = ["type": "promotion"]
        XCTAssertFalse(AppDelegate.isAllowedNotificationPayload(payload))
    }

    func testDenied_EmptyPayload_ReturnsFalse() {
        let payload: [AnyHashable: Any] = [:]
        XCTAssertFalse(AppDelegate.isAllowedNotificationPayload(payload))
    }

    func testDenied_UnrelatedKeys_ReturnsFalse() {
        // Payload met random keys — typisch voor een marketing- of phishing-push
        let payload: [AnyHashable: Any] = ["url": "https://evil.example", "title": "Klik hier"]
        XCTAssertFalse(AppDelegate.isAllowedNotificationPayload(payload))
    }

    /// Regression-test: sinds de Node.js-webhook-backend is verwijderd mogen
    /// `activityId`-payloads niet meer als geldig worden beschouwd. Een push
    /// met alleen een `activityId` moet dus stil worden genegeerd.
    func testDenied_ActivityIdOnly_ReturnsFalse() {
        let payload: [AnyHashable: Any] = ["activityId": Int64(12345)]
        XCTAssertFalse(AppDelegate.isAllowedNotificationPayload(payload))
    }
}
