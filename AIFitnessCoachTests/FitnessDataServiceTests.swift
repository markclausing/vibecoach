import XCTest
import SwiftData
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
                "type": "Ride",
                "start_date": "2023-10-12T10:00:00Z"
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
                "type": "Run",
                "start_date": "2023-10-12T10:00:00Z"
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
            "type": "Run",
            "start_date": "2023-10-12T10:00:00Z"
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

@MainActor
final class AthleticProfileManagerTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var manager: AthleticProfileManager!

    override func setUp() {
        super.setUp()
        // Creëer een in-memory configuratie voor SwiftData zodat tests lokaal en snel blijven
        let schema = Schema([ActivityRecord.self, FitnessGoal.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            context = container.mainContext
        } catch {
            XCTFail("Kon in-memory ModelContainer niet aanmaken: \(error)")
        }

        manager = AthleticProfileManager()
    }

    override func tearDown() {
        container = nil
        context = nil
        manager = nil
        super.tearDown()
    }

    func testCalculateProfile_WithNoData_ReturnsNil() throws {
        // Act
        let profile = try manager.calculateProfile(context: context)

        // Assert
        XCTAssertNil(profile, "Profiel zou nil moeten zijn als er geen data is")
    }

    func testCalculateProfile_WithData_CalculatesCorrectly() throws {
        // Arrange
        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let threeWeeksAgo = Calendar.current.date(byAdding: .day, value: -21, to: now)!
        let fiveWeeksAgo = Calendar.current.date(byAdding: .day, value: -35, to: now)!

        // Activiteiten toevoegen
        // 1. Recente activiteit: 5 km in 1800 sec
        let act1 = ActivityRecord(id: "1", name: "Run 1", distance: 5000, movingTime: 1800, averageHeartrate: 150, type: "Run", startDate: twoDaysAgo)
        // 2. Activiteit 3 weken geleden: 10 km in 3600 sec (Piek afstand en tijd!)
        let act2 = ActivityRecord(id: "2", name: "Run 2", distance: 10000, movingTime: 3600, averageHeartrate: 155, type: "Run", startDate: threeWeeksAgo)
        // 3. Oude activiteit buiten de 4-weken window: 3 km in 1200 sec
        let act3 = ActivityRecord(id: "3", name: "Run 3", distance: 3000, movingTime: 1200, averageHeartrate: 145, type: "Run", startDate: fiveWeeksAgo)

        context.insert(act1)
        context.insert(act2)
        context.insert(act3)
        try context.save()

        // Act
        let profile = try manager.calculateProfile(context: context)

        // Assert
        XCTAssertNotNil(profile)

        // Piekprestatie moet gebaseerd zijn op alle activiteiten
        XCTAssertEqual(profile?.peakDistanceInMeters, 10000)
        XCTAssertEqual(profile?.peakDurationInSeconds, 3600)

        // Wekelijks volume van afgelopen 4 weken:
        // Totaal in sec: act1 (1800) + act2 (3600) = 5400 seconden
        // Gemiddeld per week: 5400 / 4 = 1350 seconden
        XCTAssertEqual(profile?.averageWeeklyVolumeInSeconds, 1350)

        // Overtraining vlag zou false moeten zijn in deze milde case
        XCTAssertFalse(profile?.isRecoveryNeeded ?? true)
    }

    func testCalculateProfile_TriggersRecoveryWarning_WhenTrainingTooManyConsecutiveDays() throws {
        // Arrange
        let now = Date()
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: now)!

        // 4 trainingen op rij
        context.insert(ActivityRecord(id: "1", name: "Run", distance: 5000, movingTime: 1800, averageHeartrate: nil, type: "Run", startDate: now))
        context.insert(ActivityRecord(id: "2", name: "Run", distance: 5000, movingTime: 1800, averageHeartrate: nil, type: "Run", startDate: oneDayAgo))
        context.insert(ActivityRecord(id: "3", name: "Run", distance: 5000, movingTime: 1800, averageHeartrate: nil, type: "Run", startDate: twoDaysAgo))
        context.insert(ActivityRecord(id: "4", name: "Run", distance: 5000, movingTime: 1800, averageHeartrate: nil, type: "Run", startDate: threeDaysAgo))
        try context.save()

        // Act
        let profile = try manager.calculateProfile(context: context)

        // Assert
        XCTAssertNotNil(profile)
        XCTAssertTrue(profile?.isRecoveryNeeded ?? false, "Should trigger recovery warning for 4 consecutive days of training")
    }
}

final class PhysiologicalCalculatorTests: XCTestCase {
    var calculator: PhysiologicalCalculator!

    override func setUp() {
        super.setUp()
        calculator = PhysiologicalCalculator()
    }

    override func tearDown() {
        calculator = nil
        super.tearDown()
    }

    func testCalculateTSS_LightRide() {
        // Arrange
        let durationInSeconds: Double = 3600 // 1 hour
        let averageHeartRate: Double = 130
        let maxHeartRate: Double = 190
        let restingHeartRate: Double = 60

        // Act
        let tss = calculator.calculateTSS(durationInSeconds: durationInSeconds, averageHeartRate: averageHeartRate, maxHeartRate: maxHeartRate, restingHeartRate: restingHeartRate)

        // Assert
        // Delta HR = (130 - 60) / (190 - 60) = 70 / 130 = 0.538461538
        // TRIMP = 60 * 0.538461538 * 0.64 * e^(1.92 * 0.538461538)
        // TRIMP = ~58.14
        XCTAssertEqual(tss, 58.14, accuracy: 0.1, "TSS calculation for light ride is incorrect")
    }

    func testCalculateTSS_HeavyRide() {
        // Arrange
        let durationInSeconds: Double = 3600 // 1 hour
        let averageHeartRate: Double = 170
        let maxHeartRate: Double = 190
        let restingHeartRate: Double = 60

        // Act
        let tss = calculator.calculateTSS(durationInSeconds: durationInSeconds, averageHeartRate: averageHeartRate, maxHeartRate: maxHeartRate, restingHeartRate: restingHeartRate)

        // Assert
        // Delta HR = (170 - 60) / (190 - 60) = 110 / 130 = 0.846153846
        // TRIMP = 60 * 0.846153846 * 0.64 * e^(1.92 * 0.846153846)
        // TRIMP = ~164.94
        XCTAssertEqual(tss, 164.94, accuracy: 0.1, "TSS calculation for heavy ride is incorrect")
    }

    func testCalculateTSS_ZeroDuration() {
        let tss = calculator.calculateTSS(durationInSeconds: 0, averageHeartRate: 150, maxHeartRate: 190, restingHeartRate: 60)
        XCTAssertEqual(tss, 0.0, "TSS should be 0 for zero duration")
    }

    func testCalculateTSS_NegativeDuration() {
        let tss = calculator.calculateTSS(durationInSeconds: -3600, averageHeartRate: 150, maxHeartRate: 190, restingHeartRate: 60)
        XCTAssertEqual(tss, 0.0, "TSS should be 0 for negative duration")
    }

    func testCalculateTSS_SameRestingAndMaxHeartRate() {
        let tss = calculator.calculateTSS(durationInSeconds: 3600, averageHeartRate: 150, maxHeartRate: 60, restingHeartRate: 60)
        XCTAssertEqual(tss, 0.0, "TSS should handle identical rest and max HR gracefully")
    }

    func testCalculateTSS_AverageHrGreaterThanMaxHr() {
        // Average HR 200, Max HR 190.
        // Should calculate normally but yield a high positive number without crashing.
        let tss = calculator.calculateTSS(durationInSeconds: 3600, averageHeartRate: 200, maxHeartRate: 190, restingHeartRate: 60)
        XCTAssertTrue(tss > 0, "TSS should be a valid positive number even if average HR slightly exceeds Max HR")

        // Let's verify the math is consistent: Delta HR = 140 / 130 = 1.076923077
        // TRIMP = 60 * 1.076923077 * 0.64 * e^(1.92 * 1.076923077) = ~326.97
        XCTAssertEqual(tss, 326.97, accuracy: 0.1, "TSS calculation for average HR > max HR is incorrect")
    }

    func testCalculateTSS_AverageHrEqualsRestingHr() {
        // Average HR equals resting HR (Delta = 0)
        // TRIMP = duration * 0 * 0.64 * e^(0) = 0
        let tss = calculator.calculateTSS(durationInSeconds: 3600, averageHeartRate: 60, maxHeartRate: 190, restingHeartRate: 60)
        XCTAssertEqual(tss, 0.0, "TSS should be exactly 0 if average heart rate equals resting heart rate")
    }

    func testCalculateTSS_MissingHealthKitData() {
        // Test with max HR 0 and resting HR 0
        let tss1 = calculator.calculateTSS(durationInSeconds: 3600, averageHeartRate: 150, maxHeartRate: 0, restingHeartRate: 0)
        XCTAssertEqual(tss1, 0.0, "TSS should be 0 when max HR and resting HR are missing/0 to avoid division by zero")

        // Test with resting HR missing (0) but max HR present
        let tss2 = calculator.calculateTSS(durationInSeconds: 3600, averageHeartRate: 150, maxHeartRate: 190, restingHeartRate: 0)
        XCTAssertTrue(tss2 > 0, "TSS should still calculate if only resting HR is missing (defaults to 0)")

        // Test with max HR missing (0) but resting HR present (would result in negative HRR)
        let tss3 = calculator.calculateTSS(durationInSeconds: 3600, averageHeartRate: 150, maxHeartRate: 0, restingHeartRate: 60)
        XCTAssertEqual(tss3, 0.0, "TSS should be 0 if HRR is negative due to missing max HR")
    }
}
