import XCTest
@testable import AIFitnessCoach

/// Epic #50 — `HistoricalWeatherService`. Borgt:
///  • URL-bouw: archive vs forecast endpoint kiezen op basis van leeftijd
///  • Privacy-rounding op 0.1° (~11km) vóór coords naar Open-Meteo gaan
///  • Hour-bucket-extractie: workout om 14:25 → uur 14
///  • Graceful handling van missing data (Open-Meteo `null` voor uren)
///  • Fout-paden (invalid coords, out-of-range date, niet-2xx response)
final class HistoricalWeatherServiceTests: XCTestCase {

    // MARK: - Privacy rounding

    func testRoundForPrivacy_roundsToOneDecimal() {
        XCTAssertEqual(HistoricalWeatherService.roundForPrivacy(52.3712), 52.4, accuracy: 0.001)
        XCTAssertEqual(HistoricalWeatherService.roundForPrivacy(4.8945), 4.9, accuracy: 0.001)
        XCTAssertEqual(HistoricalWeatherService.roundForPrivacy(-33.8688), -33.9, accuracy: 0.001)
    }

    // MARK: - URL-builder

    func testMakeURL_olderThanArchiveLag_usesArchiveEndpoint() throws {
        let date = Date().addingTimeInterval(-30 * 86_400)
        let url = try HistoricalWeatherService.makeURL(
            latitude: 52.4, longitude: 4.9, date: date, useArchive: true
        )
        XCTAssertTrue(url.absoluteString.contains("archive-api.open-meteo.com"))
        XCTAssertTrue(url.absoluteString.contains("start_date="))
        XCTAssertTrue(url.absoluteString.contains("end_date="))
    }

    func testMakeURL_recentDate_usesForecastEndpoint() throws {
        let date = Date().addingTimeInterval(-2 * 86_400)
        let url = try HistoricalWeatherService.makeURL(
            latitude: 52.4, longitude: 4.9, date: date, useArchive: false
        )
        XCTAssertTrue(url.absoluteString.contains("api.open-meteo.com/v1/forecast"))
        XCTAssertTrue(url.absoluteString.contains("past_days="))
    }

    func testMakeURL_includesHourlyParameters() throws {
        let url = try HistoricalWeatherService.makeURL(
            latitude: 52.4, longitude: 4.9, date: Date(), useArchive: true
        )
        XCTAssertTrue(url.absoluteString.contains("hourly=temperature_2m,relative_humidity_2m")
                      || url.absoluteString.contains("temperature_2m%2Crelative_humidity_2m"))
    }

    // MARK: - Hour-bucket extractie

    func testExtractHourValues_picksClosestHourBucket() {
        // Workout-startdate: 2026-05-09 14:25 UTC
        let startDate = ISO8601DateFormatter().date(from: "2026-05-09T14:25:00Z")!

        // 24 uren met oplopende temperatuur 0..23, humidity 50..73
        let times = (0..<24).map { String(format: "2026-05-09T%02d:00", $0) }
        let temps: [Double?] = (0..<24).map { Double($0) }
        let hums: [Double?] = (0..<24).map { Double(50 + $0) }
        let response = OpenMeteoHourlyResponse(
            hourly: .init(time: times, temperature_2m: temps, relative_humidity_2m: hums)
        )

        let result = HistoricalWeatherService.extractHourValues(from: response, at: startDate)
        // 14:25 is dichtst bij 14:00 (delta 25 min) versus 15:00 (delta 35 min).
        XCTAssertEqual(result.temperatureCelsius ?? -1, 14, accuracy: 0.01)
        XCTAssertEqual(result.humidityPercent ?? -1, 64, accuracy: 0.01)
    }

    func testExtractHourValues_missingDataReturnsNil() {
        // Open-Meteo levert soms `null` voor specifieke uren — dat moet als nil
        // doorvloeien in plaats van te crashen of een verkeerde waarde te pakken.
        let startDate = ISO8601DateFormatter().date(from: "2026-05-09T10:00:00Z")!
        let response = OpenMeteoHourlyResponse(
            hourly: .init(
                time: ["2026-05-09T10:00"],
                temperature_2m: [nil],
                relative_humidity_2m: [nil]
            )
        )
        let result = HistoricalWeatherService.extractHourValues(from: response, at: startDate)
        XCTAssertNil(result.temperatureCelsius)
        XCTAssertNil(result.humidityPercent)
    }

    func testExtractHourValues_emptyResponseReturnsNil() {
        let response = OpenMeteoHourlyResponse(
            hourly: .init(time: [], temperature_2m: [], relative_humidity_2m: [])
        )
        let result = HistoricalWeatherService.extractHourValues(from: response, at: Date())
        XCTAssertNil(result.temperatureCelsius)
        XCTAssertNil(result.humidityPercent)
    }

    // MARK: - Validatie

    func testFetchWeather_invalidLatitude_throws() async {
        let service = HistoricalWeatherService()
        do {
            _ = try await service.fetchWeather(latitude: 999, longitude: 5, startDate: Date())
            XCTFail("Verwacht WeatherFetchError.invalidCoordinates")
        } catch HistoricalWeatherService.WeatherFetchError.invalidCoordinates {
            // ok
        } catch {
            XCTFail("Verwacht invalidCoordinates, kreeg: \(error)")
        }
    }

    func testFetchWeather_dateTooFarInPast_throws() async {
        let service = HistoricalWeatherService()
        let veryOld = Date(timeIntervalSinceReferenceDate: 0).addingTimeInterval(-100 * 365 * 86_400)
        do {
            _ = try await service.fetchWeather(latitude: 52.4, longitude: 4.9, startDate: veryOld)
            XCTFail("Verwacht WeatherFetchError.dateOutOfRange")
        } catch HistoricalWeatherService.WeatherFetchError.dateOutOfRange {
            // ok
        } catch {
            XCTFail("Verwacht dateOutOfRange, kreeg: \(error)")
        }
    }

    // MARK: - Mock fetcher (end-to-end zonder netwerk)

    func testFetchWeather_withMockFetcher_returnsValuesFromResponse() async throws {
        // Bouw een mini Open-Meteo response voor 12:00 → 25.5°C, 60%
        let mockJSON = """
        {
          "hourly": {
            "time": ["2026-05-09T11:00", "2026-05-09T12:00", "2026-05-09T13:00"],
            "temperature_2m": [24.5, 25.5, 26.0],
            "relative_humidity_2m": [62, 60, 58]
          }
        }
        """.data(using: .utf8)!

        let mock = MockFetcher(data: mockJSON, statusCode: 200)
        let service = HistoricalWeatherService(fetcher: mock)
        let date = ISO8601DateFormatter().date(from: "2026-05-09T12:05:00Z")!

        let (temp, humidity) = try await service.fetchWeather(
            latitude: 52.4, longitude: 4.9, startDate: date
        )
        XCTAssertEqual(temp ?? -1, 25.5, accuracy: 0.01)
        XCTAssertEqual(humidity ?? -1, 60, accuracy: 0.01)
    }

    func testFetchWeather_non2xxResponse_throwsRequestFailed() async {
        let mock = MockFetcher(data: Data(), statusCode: 503)
        let service = HistoricalWeatherService(fetcher: mock)
        do {
            _ = try await service.fetchWeather(
                latitude: 52.4, longitude: 4.9,
                startDate: Date().addingTimeInterval(-30 * 86_400)
            )
            XCTFail("Verwacht WeatherFetchError.requestFailed")
        } catch HistoricalWeatherService.WeatherFetchError.requestFailed(let statusCode) {
            XCTAssertEqual(statusCode, 503)
        } catch {
            XCTFail("Verwacht requestFailed, kreeg: \(error)")
        }
    }
}

// MARK: - Test helpers

private struct MockFetcher: WeatherURLFetcher {
    let data: Data
    let statusCode: Int

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                       httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}
