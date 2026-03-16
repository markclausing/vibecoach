import XCTest
@testable import AIFitnessCoach

final class FitnessDataServiceTests: XCTestCase {

    func testFetchLatestActivity_Success() async throws {
        // Arrange
        let mockTokenStore = MockTokenStore()
        try mockTokenStore.saveToken("valid_token", forService: "StravaToken")

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

    func testFetchLatestActivity_Unauthorized() async throws {
        // Arrange
        let mockTokenStore = MockTokenStore()
        try mockTokenStore.saveToken("expired_token", forService: "StravaToken")

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
}
