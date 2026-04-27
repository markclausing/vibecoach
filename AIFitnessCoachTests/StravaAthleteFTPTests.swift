import XCTest
@testable import AIFitnessCoach

/// Epic 44 Story 44.3 — Strava FTP-import via `FitnessDataService.fetchAthleteFTP`.
/// Borgt:
///  • Geldig athlete-JSON met FTP → Int teruggegeven
///  • Athlete-JSON zonder FTP-veld → nil (geen onnodige fout)
///  • 401 → unauthorized error
///  • Token-refresh-pad blijft werken (bestaat al via ensureValidToken)
final class StravaAthleteFTPTests: XCTestCase {

    private func makeService() throws -> (FitnessDataService, MockTokenStore, MockNetworkSession) {
        let store = MockTokenStore()
        try store.saveToken("valid_token", forService: "StravaToken")
        try store.saveToken("refresh_token", forService: "StravaRefreshToken")
        let future = Date().addingTimeInterval(3_600).timeIntervalSince1970
        try store.saveToken(String(future), forService: "StravaTokenExpiresAt")
        let session = MockNetworkSession()
        return (FitnessDataService(tokenStore: store, session: session), store, session)
    }

    private func httpResponse(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://www.strava.com/api/v3/athlete")!,
                        statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    // MARK: Decode

    func testFetchAthleteFTP_WithFTP_ReturnsValue() async throws {
        let (service, _, session) = try makeService()
        session.dataToReturn = """
        { "id": 12345, "username": "test", "ftp": 287 }
        """.data(using: .utf8)
        session.responseToReturn = httpResponse(status: 200)

        let ftp = try await service.fetchAthleteFTP()
        XCTAssertEqual(ftp, 287)
    }

    func testFetchAthleteFTP_NoFTPField_ReturnsNil() async throws {
        let (service, _, session) = try makeService()
        session.dataToReturn = """
        { "id": 12345, "username": "no_ftp_set" }
        """.data(using: .utf8)
        session.responseToReturn = httpResponse(status: 200)

        let ftp = try await service.fetchAthleteFTP()
        XCTAssertNil(ftp,
                     "Atleet zonder FTP in profiel moet nil teruggeven, niet een fout")
    }

    func testFetchAthleteFTP_NullFTP_ReturnsNil() async throws {
        let (service, _, session) = try makeService()
        session.dataToReturn = """
        { "id": 12345, "ftp": null }
        """.data(using: .utf8)
        session.responseToReturn = httpResponse(status: 200)

        let ftp = try await service.fetchAthleteFTP()
        XCTAssertNil(ftp)
    }

    // MARK: Errors

    func testFetchAthleteFTP_Unauthorized_Throws() async throws {
        let (service, _, session) = try makeService()
        session.dataToReturn = Data()
        session.responseToReturn = httpResponse(status: 401)

        do {
            _ = try await service.fetchAthleteFTP()
            XCTFail("Verwacht .unauthorized")
        } catch FitnessDataError.unauthorized {
            // ok
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }
    }

    func testFetchAthleteFTP_ServerError_ThrowsNetworkError() async throws {
        let (service, _, session) = try makeService()
        session.dataToReturn = Data()
        session.responseToReturn = httpResponse(status: 503)

        do {
            _ = try await service.fetchAthleteFTP()
            XCTFail("Verwacht .networkError voor 5xx")
        } catch FitnessDataError.networkError {
            // ok
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }
    }

    func testFetchAthleteFTP_MissingToken_ThrowsMissingToken() async throws {
        let store = MockTokenStore() // geen token
        let session = MockNetworkSession()
        let service = FitnessDataService(tokenStore: store, session: session)

        do {
            _ = try await service.fetchAthleteFTP()
            XCTFail("Verwacht .missingToken")
        } catch FitnessDataError.missingToken {
            // ok
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }
    }
}
