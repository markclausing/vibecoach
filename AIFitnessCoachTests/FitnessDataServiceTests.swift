import XCTest
@testable import AIFitnessCoach

final class FitnessDataServiceTests: XCTestCase {

    var mockTokenStore: MockTokenStore!
    var service: FitnessDataService!

    override func setUp() {
        super.setUp()
        mockTokenStore = MockTokenStore()
        service = FitnessDataService(tokenStore: mockTokenStore)
    }

    override func tearDown() {
        mockTokenStore = nil
        service = nil
        super.tearDown()
    }

    func testFetchLatestActivityReturnsMockData() async throws {
        // Arrange
        // (Optioneel: stel een mock token in, al gebruikt de mock functie die momenteel nog niet)
        try mockTokenStore.saveToken("test-token", forService: "StravaToken")

        // Act
        let result = try await service.fetchLatestActivity()

        // Assert
        XCTAssertTrue(result.contains("50km"))
        XCTAssertTrue(result.contains("140"))
    }
}
