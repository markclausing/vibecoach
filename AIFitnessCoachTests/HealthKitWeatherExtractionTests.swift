import XCTest
import HealthKit
@testable import AIFitnessCoach

/// Epic #49 — `HealthKitSyncService.extractWeather`. Borgt:
///  • HKMetadataKeyWeatherTemperature in degF wordt naar Celsius geconverteerd
///  • HKMetadataKeyWeatherTemperature in degC blijft direct op Celsius staan
///  • HKMetadataKeyWeatherHumidity wordt genormaliseerd op 0-100 (Apple kan 0-1 of 0-100 leveren)
///  • Ontbrekende of onbekende keys → nil zonder crash
final class HealthKitWeatherExtractionTests: XCTestCase {

    // MARK: Temperature conversion

    func testFahrenheitTemperature_ConvertedToCelsius() {
        let metadata: [String: Any] = [
            HKMetadataKeyWeatherTemperature: HKQuantity(unit: .degreeFahrenheit(), doubleValue: 86)
        ]
        let result = HealthKitSyncService.extractWeather(from: metadata)
        XCTAssertEqual(result.temperatureCelsius ?? 0, 30, accuracy: 0.5,
                       "86°F = 30°C")
        XCTAssertNil(result.humidityPercent)
    }

    func testCelsiusTemperature_StoredAsCelsius() {
        let metadata: [String: Any] = [
            HKMetadataKeyWeatherTemperature: HKQuantity(unit: .degreeCelsius(), doubleValue: 22)
        ]
        let result = HealthKitSyncService.extractWeather(from: metadata)
        XCTAssertEqual(result.temperatureCelsius ?? 0, 22, accuracy: 0.01)
    }

    // MARK: Humidity normalization

    func testHumidityAsPercent_ZeroToOne_NormalizedTo100() {
        // Apple kan luchtvochtigheid leveren als HKQuantity in fractie (0.65 = 65%).
        let metadata: [String: Any] = [
            HKMetadataKeyWeatherHumidity: HKQuantity(unit: .percent(), doubleValue: 0.65)
        ]
        let result = HealthKitSyncService.extractWeather(from: metadata)
        XCTAssertEqual(result.humidityPercent ?? 0, 65, accuracy: 0.5)
    }

    func testHumidityAsPercent_ZeroToHundred_StaysSame() {
        // Andere bronnen leveren al 0-100. Mag niet ten onrechte ×100 worden.
        let metadata: [String: Any] = [
            HKMetadataKeyWeatherHumidity: HKQuantity(unit: .percent(), doubleValue: 65)
        ]
        let result = HealthKitSyncService.extractWeather(from: metadata)
        XCTAssertEqual(result.humidityPercent ?? 0, 65, accuracy: 0.5)
    }

    // MARK: Combined

    func testBothPresent_ReturnsBoth() {
        let metadata: [String: Any] = [
            HKMetadataKeyWeatherTemperature: HKQuantity(unit: .degreeCelsius(), doubleValue: 28),
            HKMetadataKeyWeatherHumidity: HKQuantity(unit: .percent(), doubleValue: 0.72)
        ]
        let result = HealthKitSyncService.extractWeather(from: metadata)
        XCTAssertEqual(result.temperatureCelsius ?? 0, 28, accuracy: 0.01)
        XCTAssertEqual(result.humidityPercent ?? 0, 72, accuracy: 0.5)
    }

    // MARK: Missing/edge cases

    func testNilMetadata_ReturnsNilNil() {
        let result = HealthKitSyncService.extractWeather(from: nil)
        XCTAssertNil(result.temperatureCelsius)
        XCTAssertNil(result.humidityPercent)
    }

    func testEmptyMetadata_ReturnsNilNil() {
        let result = HealthKitSyncService.extractWeather(from: [:])
        XCTAssertNil(result.temperatureCelsius)
        XCTAssertNil(result.humidityPercent)
    }

    func testIrrelevantKeys_Ignored() {
        let metadata: [String: Any] = [
            "OtherKey": "noise",
            HKMetadataKeyIndoorWorkout: NSNumber(value: false)
        ]
        let result = HealthKitSyncService.extractWeather(from: metadata)
        XCTAssertNil(result.temperatureCelsius)
        XCTAssertNil(result.humidityPercent)
    }

    func testWrongValueType_HandledGracefully() {
        // String i.p.v. HKQuantity onder de weer-key — moet gewoon nil teruggeven,
        // niet crashen. Defensief tegen mocked of corrupte metadata-dictionaries.
        let metadata: [String: Any] = [
            HKMetadataKeyWeatherTemperature: "not a quantity",
            HKMetadataKeyWeatherHumidity: 42
        ]
        let result = HealthKitSyncService.extractWeather(from: metadata)
        XCTAssertNil(result.temperatureCelsius)
        XCTAssertNil(result.humidityPercent)
    }
}
