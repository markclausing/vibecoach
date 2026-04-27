import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Epic 41.4 — Integratietests die de "race" tussen een HealthKit-import en
/// een Strava-import simuleren. Doel: bewijzen dat `ActivityDeduplicator.smartInsert`
/// voorkomt dat een armer record een rijker record overschrijft, ongeacht de
/// volgorde waarin de bronnen binnenkomen.
@MainActor
final class SmartIngestRaceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private let baseDate = Date(timeIntervalSince1970: 1_745_625_600) // 2025-04-26 12:00:00 UTC

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ActivityRecord.self, configurations: config)
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: Builders

    /// Bouwt een HealthKit-stijl record: id is een echte UUID-string, geen deviceWatts.
    private func makeHKRecord(startOffset: TimeInterval = 0,
                              sport: SportCategory = .cycling,
                              avgHR: Double? = 145,
                              trimp: Double? = 80) -> ActivityRecord {
        ActivityRecord(
            id: UUID().uuidString,
            name: "HK Workout",
            distance: 25_000,
            movingTime: 3_600,
            averageHeartrate: avgHR,
            sportCategory: sport,
            startDate: baseDate.addingTimeInterval(startOffset),
            trimp: trimp,
            deviceWatts: nil
        )
    }

    /// Bouwt een Strava-stijl record: id is de numerieke Strava-id, deviceWatts=true.
    private func makeStravaRecord(stravaID: String = "12345678901",
                                  startOffset: TimeInterval = 0,
                                  sport: SportCategory = .cycling,
                                  avgHR: Double? = 145,
                                  trimp: Double? = 80,
                                  deviceWatts: Bool? = true) -> ActivityRecord {
        ActivityRecord(
            id: stravaID,
            name: "Strava Ride",
            distance: 25_000,
            movingTime: 3_600,
            averageHeartrate: avgHR,
            sportCategory: sport,
            startDate: baseDate.addingTimeInterval(startOffset),
            trimp: trimp,
            deviceWatts: deviceWatts
        )
    }

    private func allRecords() throws -> [ActivityRecord] {
        try context.fetch(FetchDescriptor<ActivityRecord>())
    }

    // MARK: Race A — HK eerst, Strava daarna

    func testRace_HKFirstThenStrava_StravaWinsAndReplacesHK() throws {
        // Arrange: HK-record komt als eerste binnen.
        let hk = makeHKRecord(startOffset: 0)
        let hkResult = try ActivityDeduplicator.smartInsert(hk, into: context)
        try context.save()
        XCTAssertEqual(hkResult, .inserted)

        // Act: Strava-record met deviceWatts komt 1 seconde later binnen.
        let strava = makeStravaRecord(startOffset: 1)
        let stravaResult = try ActivityDeduplicator.smartInsert(strava, into: context)
        try context.save()

        // Assert: Strava heeft HK vervangen — slechts één record over en deviceWatts=true.
        XCTAssertEqual(stravaResult, .replaced,
                       "Strava-record met deviceWatts moet HK-record overschrijven")
        let records = try allRecords()
        XCTAssertEqual(records.count, 1, "Na replace mag er maar één record over zijn")
        XCTAssertEqual(records.first?.id, strava.id)
        XCTAssertEqual(records.first?.deviceWatts, true)
    }

    // MARK: Race B — Strava eerst, HK daarna

    func testRace_StravaFirstThenHK_HKIsSkippedExistingRicher() throws {
        // Arrange: rijker Strava-record landt eerst.
        let strava = makeStravaRecord(startOffset: 0)
        let stravaResult = try ActivityDeduplicator.smartInsert(strava, into: context)
        try context.save()
        XCTAssertEqual(stravaResult, .inserted)

        // Act: armer HK-record komt 2 seconden later — moet niet over Strava heen schrijven.
        let hk = makeHKRecord(startOffset: 2)
        let hkResult = try ActivityDeduplicator.smartInsert(hk, into: context)
        try context.save()

        // Assert: Strava blijft staan, HK is afgewezen.
        XCTAssertEqual(hkResult, .skippedExistingRicher,
                       "Armer HK-record moet wijken voor reeds aanwezig Strava-record met power")
        let records = try allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, strava.id)
    }

    // MARK: Race C — Idempotente re-import van zelfde bron

    func testRace_StravaReImport_IsSkippedSameSource() throws {
        // Arrange: Strava-record landt, daarna komt exact dezelfde Strava-id nog eens binnen.
        let strava1 = makeStravaRecord(stravaID: "9999", startOffset: 0)
        try ActivityDeduplicator.smartInsert(strava1, into: context)
        try context.save()

        let strava2 = makeStravaRecord(stravaID: "9999", startOffset: 0)
        let result = try ActivityDeduplicator.smartInsert(strava2, into: context)
        try context.save()

        // Assert: niets gebeurt — re-imports zijn idempotent op basis van source-id.
        XCTAssertEqual(result, .skippedSameSource)
        XCTAssertEqual(try allRecords().count, 1)
    }

    // MARK: Race D — Cross-sport bug op identieke timestamp

    func testRace_CrossSportSameTimestamp_StravaStrengthReplacesHKOther() throws {
        // Reproduceert de bug uit Epic 41-context: HK mapt strength als `.other`
        // omdat de hkType-id niet gekend is, terwijl Strava 'm correct als
        // `.strength` aanlevert. Identieke seconde → strikt-tijd bypass triggert.
        let hk = makeHKRecord(startOffset: 0, sport: .other, avgHR: 130, trimp: 50)
        try ActivityDeduplicator.smartInsert(hk, into: context)
        try context.save()

        let strava = makeStravaRecord(stravaID: "55555", startOffset: 0,
                                      sport: .strength, avgHR: 130, trimp: 50,
                                      deviceWatts: true)
        let result = try ActivityDeduplicator.smartInsert(strava, into: context)
        try context.save()

        XCTAssertEqual(result, .replaced)
        let records = try allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.sportCategory, .strength,
                       "Strava's correcte sport-mapping moet de HK `.other`-fallback verdringen")
    }

    // MARK: Race E — Onafhankelijke workouts blijven naast elkaar bestaan

    func testRace_TwoUnrelatedWorkouts_BothInserted() throws {
        let morning  = makeStravaRecord(stravaID: "morning", startOffset: 0)
        let evening  = makeStravaRecord(stravaID: "evening", startOffset: 36_000) // +10 uur
        try ActivityDeduplicator.smartInsert(morning, into: context)
        try ActivityDeduplicator.smartInsert(evening, into: context)
        try context.save()

        let records = try allRecords()
        XCTAssertEqual(records.count, 2,
                       "Twee verschillende workouts op dezelfde dag mogen beide blijven bestaan")
        XCTAssertEqual(Set(records.map(\.id)), Set(["morning", "evening"]))
    }

    // MARK: Race F — Beide bronnen zonder rijke signalen → existing wint (tiebreaker)

    func testRace_EqualPoorRecords_FirstStays() throws {
        // Beide records: alleen avg-HR. shouldReplace eist strikt > , dus existing blijft.
        let hk = makeHKRecord(startOffset: 0, avgHR: 140, trimp: nil)
        try ActivityDeduplicator.smartInsert(hk, into: context)
        try context.save()

        let strava = makeStravaRecord(startOffset: 1, avgHR: 140, trimp: nil, deviceWatts: nil)
        let result = try ActivityDeduplicator.smartInsert(strava, into: context)
        try context.save()

        XCTAssertEqual(result, .skippedExistingRicher,
                       "Bij gelijke score moet de eerst-binnengekomen record blijven staan")
        XCTAssertEqual(try allRecords().count, 1)
        XCTAssertEqual(try allRecords().first?.id, hk.id)
    }

    // MARK: shouldReplace — directe unit-test voor de helper

    func testShouldReplace_NewWithDeviceWatts_BeatsExistingWithoutPower() {
        let existing = makeHKRecord()
        let new = makeStravaRecord(deviceWatts: true)
        XCTAssertTrue(ActivityDeduplicator.shouldReplace(existing: existing, new: new))
    }

    func testShouldReplace_EqualScore_ReturnsFalse() {
        // Strict-greater: gelijke score telt niet als "vervangen".
        let a = makeHKRecord()
        let b = makeStravaRecord(deviceWatts: nil)
        XCTAssertFalse(ActivityDeduplicator.shouldReplace(existing: a, new: b))
    }
}

// MARK: - Epic 41.3 — ensureValidToken()

/// Borgt het OAuth-hardening contract: vóór elke API-call wordt het token
/// gevalideerd én indien nodig ververst, en een ontbrekend token throwt
/// `.missingToken` in plaats van een silent 401.
final class EnsureValidTokenTests: XCTestCase {

    func testEnsureValidToken_WithFreshToken_ReturnsTokenWithoutNetworkCall() async throws {
        let store = MockTokenStore()
        try store.saveToken("fresh_access", forService: "StravaToken")
        try store.saveToken("refresh", forService: "StravaRefreshToken")
        let future = Date().addingTimeInterval(3_600).timeIntervalSince1970
        try store.saveToken(String(future), forService: "StravaTokenExpiresAt")

        let session = MockNetworkSession()
        let service = FitnessDataService(tokenStore: store, session: session)

        let token = try await service.ensureValidToken()

        XCTAssertEqual(token, "fresh_access")
        XCTAssertEqual(session.callCount, 0,
                       "Een geldig token mag geen refresh-call triggeren — anders heeft de hardening averechts effect")
    }

    func testEnsureValidToken_WithExpiringToken_RefreshesAndReturnsNewToken() async throws {
        let store = MockTokenStore()
        try store.saveToken("expired_access", forService: "StravaToken")
        try store.saveToken("old_refresh", forService: "StravaRefreshToken")
        // Token verloopt over 60 seconden — binnen de 5-minuten guard.
        let nearExpiry = Date().addingTimeInterval(60).timeIntervalSince1970
        try store.saveToken(String(nearExpiry), forService: "StravaTokenExpiresAt")

        let session = MockNetworkSession()
        let newExpiresAt = Int(Date().addingTimeInterval(7_200).timeIntervalSince1970)
        let refreshJSON = """
        {
          "access_token": "new_access",
          "refresh_token": "new_refresh",
          "expires_at": \(newExpiresAt)
        }
        """
        session.dataToReturn = refreshJSON.data(using: .utf8)
        session.responseToReturn = HTTPURLResponse(
            url: URL(string: "https://proxy/oauth/strava/refresh")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )

        let service = FitnessDataService(tokenStore: store, session: session)

        let token = try await service.ensureValidToken()

        XCTAssertEqual(token, "new_access",
                       "Na refresh moet ensureValidToken het nét opgeslagen access-token teruggeven")
        XCTAssertEqual(session.callCount, 1, "Precies één refresh-call verwacht")
        XCTAssertEqual(try store.getToken(forService: "StravaToken"), "new_access")
        XCTAssertEqual(try store.getToken(forService: "StravaRefreshToken"), "new_refresh")
    }

    func testEnsureValidToken_WithoutAnyToken_ThrowsMissingToken() async {
        let store = MockTokenStore()
        let session = MockNetworkSession()
        let service = FitnessDataService(tokenStore: store, session: session)

        do {
            _ = try await service.ensureValidToken()
            XCTFail("Verwacht missingToken-fout bij lege token-store")
        } catch FitnessDataError.missingToken {
            // Verwacht: geen silent 401 meer mogelijk.
        } catch {
            XCTFail("Verwacht .missingToken, kreeg: \(error)")
        }
    }

    func testEnsureValidToken_WithEmptyAccessToken_ThrowsMissingToken() async throws {
        let store = MockTokenStore()
        try store.saveToken("", forService: "StravaToken")
        let future = Date().addingTimeInterval(3_600).timeIntervalSince1970
        try store.saveToken(String(future), forService: "StravaTokenExpiresAt")
        try store.saveToken("refresh", forService: "StravaRefreshToken")

        let service = FitnessDataService(tokenStore: store, session: MockNetworkSession())

        do {
            _ = try await service.ensureValidToken()
            XCTFail("Een lege token-string moet als ontbrekend tellen")
        } catch FitnessDataError.missingToken {
            // ok
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }
    }
}
