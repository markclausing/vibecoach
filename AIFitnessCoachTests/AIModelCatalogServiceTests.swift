import XCTest
@testable import AIFitnessCoach

/// Epic #35 — unit-dekking voor de Cloudflare-proxy die de Gemini model-catalogus
/// levert. We testen alleen het gedrag van `AIModelCatalogService` en
/// `AIModelCatalog.builtInFallback`; de sorteer-/filter-logica leeft server-side
/// en heeft zijn eigen vitest-suite in de `vibecoach-proxy` repo.
final class AIModelCatalogServiceTests: XCTestCase {

    private let baseURL = "https://worker.test"
    private let clientToken = "unit-test-token"

    private func makeResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "\(baseURL)/ai/models")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // MARK: - Happy path

    func testFetchCatalog_WithValidResponse_DecodesModelsAndDefaults() async throws {
        let json = """
        {
          "models": [
            { "id": "gemini-flash-latest", "displayName": "Gemini Flash (latest)" },
            { "id": "gemini-flash-lite-latest", "displayName": "Gemini Flash Lite (latest)" },
            { "id": "gemini-1.5-pro", "displayName": "Gemini 1.5 Pro" }
          ],
          "defaultPrimary": "gemini-flash-latest",
          "defaultFallback": "gemini-flash-lite-latest"
        }
        """
        let session = MockNetworkSession()
        session.dataToReturn = json.data(using: .utf8)
        session.responseToReturn = makeResponse(statusCode: 200)

        let service = AIModelCatalogService(session: session, baseURL: baseURL, clientToken: clientToken)
        let catalog = try await service.fetchCatalog()

        XCTAssertEqual(catalog.models.count, 3)
        XCTAssertEqual(catalog.models.map(\.id), [
            "gemini-flash-latest",
            "gemini-flash-lite-latest",
            "gemini-1.5-pro",
        ])
        XCTAssertEqual(catalog.defaultPrimary, "gemini-flash-latest")
        XCTAssertEqual(catalog.defaultFallback, "gemini-flash-lite-latest")
    }

    // MARK: - Foutpaden

    func testFetchCatalog_WithHTTPErrorStatus_ThrowsHTTPStatus() async {
        let session = MockNetworkSession()
        session.dataToReturn = Data("{}".utf8)
        session.responseToReturn = makeResponse(statusCode: 502)

        let service = AIModelCatalogService(session: session, baseURL: baseURL, clientToken: clientToken)

        do {
            _ = try await service.fetchCatalog()
            XCTFail("Verwachtte dat een 502-response tot een .httpStatus-fout zou leiden")
        } catch let AIModelCatalogError.httpStatus(code) {
            XCTAssertEqual(code, 502)
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }
    }

    func testFetchCatalog_WithMalformedJSON_ThrowsDecoding() async {
        let session = MockNetworkSession()
        session.dataToReturn = Data("not json at all".utf8)
        session.responseToReturn = makeResponse(statusCode: 200)

        let service = AIModelCatalogService(session: session, baseURL: baseURL, clientToken: clientToken)

        do {
            _ = try await service.fetchCatalog()
            XCTFail("Verwachtte een .decoding-fout bij onleesbare body")
        } catch AIModelCatalogError.decoding {
            // Verwacht
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }
    }

    func testFetchCatalog_WithTransportFailure_ThrowsTransport() async {
        let session = MockNetworkSession()
        session.errorToThrow = URLError(.notConnectedToInternet)

        let service = AIModelCatalogService(session: session, baseURL: baseURL, clientToken: clientToken)

        do {
            _ = try await service.fetchCatalog()
            XCTFail("Verwachtte een .transport-fout bij netwerkuitval")
        } catch AIModelCatalogError.transport {
            // Verwacht
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }
    }

    func testFetchCatalog_WithInvalidBaseURL_ThrowsInvalidURL() async {
        let session = MockNetworkSession()
        // Een baseURL met een illegale host-karakter leidt ertoe dat `URL(string:)`
        // voor de gecombineerde string `nil` teruggeeft — de service hoort dat
        // te herkennen vóórdat er een request de deur uitgaat.
        let service = AIModelCatalogService(
            session: session,
            baseURL: "http://exa mple .com",
            clientToken: clientToken
        )

        do {
            _ = try await service.fetchCatalog()
            XCTFail("Verwachtte een .invalidURL-fout bij een onconstrueerbare URL")
        } catch AIModelCatalogError.invalidURL {
            // Verwacht
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }

        XCTAssertEqual(session.callCount, 0, "Er mag geen netwerk-call gebeuren bij een ongeldige URL")
    }

    // MARK: - Request-shape

    func testFetchCatalog_SendsGETWithAcceptAndClientTokenHeaders() async throws {
        final class HeaderCapturingSession: NetworkSession {
            var capturedRequest: URLRequest?
            func data(for request: URLRequest) async throws -> (Data, URLResponse) {
                capturedRequest = request
                let data = Data(#"{"models":[],"defaultPrimary":"gemini-flash-latest","defaultFallback":"gemini-flash-lite-latest"}"#.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, response)
            }
        }

        let session = HeaderCapturingSession()
        let service = AIModelCatalogService(session: session, baseURL: baseURL, clientToken: clientToken)
        _ = try await service.fetchCatalog()

        let request = try XCTUnwrap(session.capturedRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "\(baseURL)/ai/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client-Token"), clientToken)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    // MARK: - Built-in fallback

    func testBuiltInFallback_HasExpectedDefaults() {
        let fallback = AIModelCatalog.builtInFallback

        XCTAssertEqual(fallback.defaultPrimary, AIModelAppStorageKey.defaultPrimary)
        XCTAssertEqual(fallback.defaultFallback, AIModelAppStorageKey.defaultFallback)
        let ids = fallback.models.map(\.id)
        XCTAssertTrue(ids.contains(fallback.defaultPrimary),
                      "defaultPrimary moet ook in de modellijst staan")
        XCTAssertTrue(ids.contains(fallback.defaultFallback),
                      "defaultFallback moet ook in de modellijst staan")
    }

    // MARK: - AppStorage resolver

    /// Eigen `UserDefaults`-suite per test zodat we de echte app-instellingen
    /// niet vervuilen. Wordt in `tearDown` opgeruimd.
    private var isolatedDefaults: UserDefaults!
    private var isolatedSuiteName: String!

    override func setUp() {
        super.setUp()
        isolatedSuiteName = "vibecoach.tests.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: isolatedSuiteName)
    }

    override func tearDown() {
        isolatedDefaults.removePersistentDomain(forName: isolatedSuiteName)
        isolatedDefaults = nil
        isolatedSuiteName = nil
        super.tearDown()
    }

    func testResolvedPrimary_WhenKeyIsMissing_ReturnsDefault() {
        let resolved = AIModelAppStorageKey.resolvedPrimary(in: isolatedDefaults)
        XCTAssertEqual(resolved, AIModelAppStorageKey.defaultPrimary)
        XCTAssertEqual(resolved, "gemini-flash-latest")
    }

    func testResolvedPrimary_WhenKeyIsSet_ReturnsStoredValue() {
        isolatedDefaults.set("gemini-2.5-flash", forKey: AIModelAppStorageKey.primary)
        let resolved = AIModelAppStorageKey.resolvedPrimary(in: isolatedDefaults)
        XCTAssertEqual(resolved, "gemini-2.5-flash")
    }

    func testResolvedFallback_WhenKeyIsMissing_ReturnsDefault() {
        let resolved = AIModelAppStorageKey.resolvedFallback(in: isolatedDefaults)
        XCTAssertEqual(resolved, AIModelAppStorageKey.defaultFallback)
        XCTAssertEqual(resolved, "gemini-flash-lite-latest")
    }

    func testResolvedFallback_WhenKeyIsSet_ReturnsStoredValue() {
        isolatedDefaults.set("gemini-1.5-pro", forKey: AIModelAppStorageKey.fallback)
        let resolved = AIModelAppStorageKey.resolvedFallback(in: isolatedDefaults)
        XCTAssertEqual(resolved, "gemini-1.5-pro")
    }

    /// Regressie-guard: als iemand per ongeluk de sleutelnamen hernoemt, zien
    /// bestaande installaties hun gekozen model resetten naar de default. Dit
    /// test pint de publieke AppStorage-contract-sleutels vast.
    func testAppStorageKeys_HaveStableNamesAndDefaults() {
        XCTAssertEqual(AIModelAppStorageKey.primary, "vibecoach_primaryGeminiModel")
        XCTAssertEqual(AIModelAppStorageKey.fallback, "vibecoach_fallbackGeminiModel")
        XCTAssertEqual(AIModelAppStorageKey.defaultPrimary, "gemini-flash-latest")
        XCTAssertEqual(AIModelAppStorageKey.defaultFallback, "gemini-flash-lite-latest")
    }
}
