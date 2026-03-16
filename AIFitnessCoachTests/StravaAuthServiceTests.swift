import XCTest
@testable import AIFitnessCoach

@MainActor
final class StravaAuthServiceTests: XCTestCase {

    func testCheckAuthStatus_WithToken() throws {
        let store = MockTokenStore()
        try store.saveToken("valid_token", forService: "StravaToken")

        let service = StravaAuthService(tokenStore: store)

        XCTAssertTrue(service.isAuthenticated)
    }

    func testCheckAuthStatus_WithoutToken() throws {
        let store = MockTokenStore()
        let service = StravaAuthService(tokenStore: store)

        XCTAssertFalse(service.isAuthenticated)
    }

    func testLogout_ClearsTokens() throws {
        let store = MockTokenStore()
        try store.saveToken("valid_token", forService: "StravaToken")
        try store.saveToken("refresh", forService: "StravaRefreshToken")
        try store.saveToken("123", forService: "StravaTokenExpiresAt")

        let service = StravaAuthService(tokenStore: store)

        XCTAssertTrue(service.isAuthenticated)

        service.logout()

        XCTAssertFalse(service.isAuthenticated)
        XCTAssertNil(try store.getToken(forService: "StravaToken"))
        XCTAssertNil(try store.getToken(forService: "StravaRefreshToken"))
        XCTAssertNil(try store.getToken(forService: "StravaTokenExpiresAt"))
    }

    // As exchanging the code involves a private function called inside a closure of ASWebAuthenticationSession,
    // we cannot directly unit test `exchangeCodeForToken` without modifying its visibility or structure.
    // However, the above tests cover the status management and logout, which represent the core business logic surface.
}
