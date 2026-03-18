import XCTest
@testable import AIFitnessCoach

final class FitnessDataServiceTests: XCTestCase {

    func testFetchLatestActivity_Success() async throws {
        // Arrange
        let mockTokenStore = MockTokenStore()
        try mockTokenStore.saveToken("valid_token", forService: "StravaToken")
        // Set an expiration date far in the future so it doesn't trigger refresh
        let futureDate = Date().addingTimeInterval(3600).timeIntervalSince1970
        try mockTokenStore.saveToken(String(futureDate), forService: "StravaTokenExpiresAt")
        try mockTokenStore.saveToken("refresh_token", forService: "StravaRefreshToken")

        let mockSession = MockNetworkSession()
        let jsonResponse = """
        [
            {
                "id": 12345,
                "name": "Evening Ride",
                "distance": 25000.0,
                "moving_time": 3600,
                "average_heartrate": 145.0,
                "type": "Ride"
            }
        ]
        """
        mockSession.dataToReturn = jsonResponse.data(using: .utf8)
        mockSession.responseToReturn = HTTPURLResponse(url: URL(string: "https://strava.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let service = FitnessDataService(tokenStore: mockTokenStore, session: mockSession)

        // Act
        let result = try await service.fetchLatestActivity()

        // Assert
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "Evening Ride")
        XCTAssertEqual(result?.distance, 25000.0)
        XCTAssertEqual(result?.moving_time, 3600)
        XCTAssertEqual(result?.average_heartrate, 145.0)
    }

    func testFetchLatestActivity_MissingToken() async {
        // Arrange
        let mockTokenStore = MockTokenStore()
        // We do not save a token here

        let mockSession = MockNetworkSession()
        let service = FitnessDataService(tokenStore: mockTokenStore, session: mockSession)

        // Act & Assert
        do {
            _ = try await service.fetchLatestActivity()
            XCTFail("Should have thrown missingToken error")
        } catch FitnessDataError.missingToken {
            // Success
        } catch {
            XCTFail("Threw unexpected error: \(error)")
        }
    }

    func testFetchLatestActivity_WithExpiredToken_ShouldRefreshAndFetch() async throws {
        // Arrange
        let mockTokenStore = MockTokenStore()
        try mockTokenStore.saveToken("expired_token", forService: "StravaToken")
        try mockTokenStore.saveToken("old_refresh", forService: "StravaRefreshToken")
        // Set an expiration date in the past
        let pastDate = Date().addingTimeInterval(-3600).timeIntervalSince1970
        try mockTokenStore.saveToken(String(pastDate), forService: "StravaTokenExpiresAt")

        let mockSession = MockNetworkSession()

        // Setup sequence responses: 1st for refresh token, 2nd for activity fetch
        let newExpiresAt = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let refreshJson = """
        {
            "access_token": "new_access_token",
            "refresh_token": "new_refresh_token",
            "expires_at": \(newExpiresAt)
        }
        """
        let refreshResponse = HTTPURLResponse(url: URL(string: "https://strava.com/oauth/token")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        let activityJson = """
        [
            {
                "id": 54321,
                "name": "Morning Run",
                "distance": 10000.0,
                "moving_time": 3000,
                "average_heartrate": 155.0,
                "type": "Run"
            }
        ]
        """
        let activityResponse = HTTPURLResponse(url: URL(string: "https://strava.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        mockSession.sequenceResponses = [
            (refreshJson.data(using: .utf8)!, refreshResponse),
            (activityJson.data(using: .utf8)!, activityResponse)
        ]

        let service = FitnessDataService(tokenStore: mockTokenStore, session: mockSession)

        // Act
        let result = try await service.fetchLatestActivity()

        // Assert
        XCTAssertEqual(mockSession.callCount, 2, "Should have made 2 network calls (refresh + fetch)")

        // Check if keychain was updated
        let savedAccessToken = try mockTokenStore.getToken(forService: "StravaToken")
        let savedRefreshToken = try mockTokenStore.getToken(forService: "StravaRefreshToken")
        let savedExpiresAtStr = try mockTokenStore.getToken(forService: "StravaTokenExpiresAt")

        XCTAssertEqual(savedAccessToken, "new_access_token")
        XCTAssertEqual(savedRefreshToken, "new_refresh_token")
        XCTAssertEqual(savedExpiresAtStr, String(newExpiresAt))

        // Check if activity was fetched correctly
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "Morning Run")
    }

    func testFetchLatestActivity_Unauthorized() async throws {
        // Arrange
        let mockTokenStore = MockTokenStore()
        try mockTokenStore.saveToken("expired_token", forService: "StravaToken")
        // Setup mock so it doesn't refresh automatically and falls through to the unauthorized block
        let futureDate = Date().addingTimeInterval(3600).timeIntervalSince1970
        try mockTokenStore.saveToken(String(futureDate), forService: "StravaTokenExpiresAt")
        try mockTokenStore.saveToken("refresh_token", forService: "StravaRefreshToken")

        let mockSession = MockNetworkSession()
        mockSession.dataToReturn = Data()
        mockSession.responseToReturn = HTTPURLResponse(url: URL(string: "https://strava.com")!, statusCode: 401, httpVersion: nil, headerFields: nil)

        let service = FitnessDataService(tokenStore: mockTokenStore, session: mockSession)

        // Act & Assert
        do {
            _ = try await service.fetchLatestActivity()
            XCTFail("Should have thrown unauthorized error")
        } catch FitnessDataError.unauthorized {
            // Success
        } catch {
            XCTFail("Threw unexpected error: \(error)")
        }
    }

    func testFetchLatestActivity_DecodingError() async throws {
        // Arrange
        let mockTokenStore = MockTokenStore()
        try mockTokenStore.saveToken("valid_token", forService: "StravaToken")
        // Setup mock so it doesn't refresh
        let futureDate = Date().addingTimeInterval(3600).timeIntervalSince1970
        try mockTokenStore.saveToken(String(futureDate), forService: "StravaTokenExpiresAt")
        try mockTokenStore.saveToken("refresh_token", forService: "StravaRefreshToken")

        let mockSession = MockNetworkSession()
        // Provide invalid JSON for an array of StravaActivity
        let invalidJson = """
        { "not_an_array": true }
        """
        mockSession.dataToReturn = invalidJson.data(using: .utf8)
        mockSession.responseToReturn = HTTPURLResponse(url: URL(string: "https://strava.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let service = FitnessDataService(tokenStore: mockTokenStore, session: mockSession)

        // Act & Assert
        do {
            _ = try await service.fetchLatestActivity()
            XCTFail("Should have thrown decoding error")
        } catch FitnessDataError.decodingError(_) {
            // Success
        } catch {
            XCTFail("Threw unexpected error: \(error)")
        }
    }

    func testFetchActivityById_Success() async throws {
        // Arrange
        let mockTokenStore = MockTokenStore()
        try mockTokenStore.saveToken("valid_token", forService: "StravaToken")
        let futureDate = Date().addingTimeInterval(3600).timeIntervalSince1970
        try mockTokenStore.saveToken(String(futureDate), forService: "StravaTokenExpiresAt")
        try mockTokenStore.saveToken("refresh_token", forService: "StravaRefreshToken")

        let mockSession = MockNetworkSession()
        let jsonResponse = """
        {
            "id": 99999,
            "name": "Lunch Run",
            "distance": 5000.0,
            "moving_time": 1800,
            "average_heartrate": 160.0,
            "type": "Run"
        }
        """
        mockSession.dataToReturn = jsonResponse.data(using: .utf8)
        mockSession.responseToReturn = HTTPURLResponse(url: URL(string: "https://strava.com/api/v3/activities/99999")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let service = FitnessDataService(tokenStore: mockTokenStore, session: mockSession)

        // Act
        let result = try await service.fetchActivity(byId: 99999)

        // Assert
        XCTAssertNotNil(result)
        XCTAssertEqual(result.id, 99999)
        XCTAssertEqual(result.name, "Lunch Run")
        XCTAssertEqual(result.distance, 5000.0)
    }

    func testFetchActivityById_NotFound() async throws {
        // Arrange
        let mockTokenStore = MockTokenStore()
        try mockTokenStore.saveToken("valid_token", forService: "StravaToken")
        let futureDate = Date().addingTimeInterval(3600).timeIntervalSince1970
        try mockTokenStore.saveToken(String(futureDate), forService: "StravaTokenExpiresAt")
        try mockTokenStore.saveToken("refresh_token", forService: "StravaRefreshToken")

        let mockSession = MockNetworkSession()
        mockSession.dataToReturn = Data()
        mockSession.responseToReturn = HTTPURLResponse(url: URL(string: "https://strava.com")!, statusCode: 404, httpVersion: nil, headerFields: nil)

        let service = FitnessDataService(tokenStore: mockTokenStore, session: mockSession)

        // Act & Assert
        do {
            _ = try await service.fetchActivity(byId: 99999)
            XCTFail("Should have thrown network error for 404")
        } catch FitnessDataError.networkError(let message) {
            XCTAssertTrue(message.contains("niet gevonden"))
        } catch {
            XCTFail("Threw unexpected error: \(error)")
        }
    }
}
