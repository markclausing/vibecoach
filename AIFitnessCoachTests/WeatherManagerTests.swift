import XCTest
@testable import AIFitnessCoach

/// Unit tests voor WeatherSafetyEvaluator (Epic 27).
///
/// Test de pure beslissingslogica — geen netwerk, locatie of UI vereist.
///
/// Drempelwaarden (referentie):
///   precipitationProbability > 0.60  → risico
///   windSpeedKmh             > 50.0  → risico
///   highCelsius              < -5.0  → risico (vrieskou)
///   highCelsius              > 38.0  → risico (hittestress)
final class WeatherManagerTests: XCTestCase {

    // MARK: - Helpers

    /// Roept WeatherSafetyEvaluator.isRisky aan met benoemde parameters.
    private func isRisky(
        rain: Double = 0.0,
        wind: Double = 0.0,
        high: Double = 20.0
    ) -> Bool {
        WeatherSafetyEvaluator.isRisky(
            precipitationProbability: rain,
            windSpeedKmh: wind,
            highCelsius: high
        )
    }

    // MARK: - 1. Ideaal weer (geen risico)

    func testIdealWeather_NoRisk() {
        // Given: mooie zomerdag — geen enkel drempelwaarde overschreden
        // When / Then
        XCTAssertFalse(isRisky(rain: 0.10, wind: 15.0, high: 22.0),
                       "Lekker weer mag geen risico opleveren.")
    }

    func testPrecipitationAtThreshold_NoRisk() {
        // Given: exact 60% neerslagkans (niet strikt groter dan drempel)
        XCTAssertFalse(isRisky(rain: 0.60, wind: 20.0, high: 18.0),
                       "Exact 60% neerslagkans is NIET boven de drempel — geen risico.")
    }

    func testWindAtThreshold_NoRisk() {
        // Given: exact 50 km/h wind (niet strikt groter dan drempel)
        XCTAssertFalse(isRisky(rain: 0.20, wind: 50.0, high: 18.0),
                       "Exact 50 km/h is NIET boven de drempel — geen risico.")
    }

    func testHighTempAtColdThreshold_NoRisk() {
        // Given: exact -5°C hoog (niet strikt lager dan koude drempel)
        XCTAssertFalse(isRisky(rain: 0.10, wind: 10.0, high: -5.0),
                       "Exact -5°C is NIET onder de koude drempel — geen risico.")
    }

    func testHighTempAtHeatThreshold_NoRisk() {
        // Given: exact 38°C hoog (niet strikt hoger dan hittedrempel)
        XCTAssertFalse(isRisky(rain: 0.10, wind: 10.0, high: 38.0),
                       "Exact 38°C is NIET boven de hittedrempel — geen risico.")
    }

    // MARK: - 2. Hoge neerslagkans → risico

    func testHighPrecipitation_IsRisky() {
        // Given: 80% neerslagkans (> 60%)
        XCTAssertTrue(isRisky(rain: 0.80, wind: 10.0, high: 15.0),
                      "80% neerslagkans moet een risico zijn.")
    }

    func testPrecipitationJustAboveThreshold_IsRisky() {
        // Given: 61% — net boven de drempel
        XCTAssertTrue(isRisky(rain: 0.61, wind: 5.0, high: 20.0),
                      "61% neerslagkans (> 60%) moet een risico zijn.")
    }

    func testFullRainChance_IsRisky() {
        // Given: 100% neerslagkans
        XCTAssertTrue(isRisky(rain: 1.0, wind: 0.0, high: 15.0),
                      "100% neerslagkans moet een risico zijn.")
    }

    // MARK: - 3. Harde wind → risico

    func testHighWind_IsRisky() {
        // Given: 75 km/h wind (> 50 km/h)
        XCTAssertTrue(isRisky(rain: 0.10, wind: 75.0, high: 18.0),
                      "75 km/h wind moet een risico zijn.")
    }

    func testWindJustAboveThreshold_IsRisky() {
        // Given: 51 km/h — net boven de drempel
        XCTAssertTrue(isRisky(rain: 0.05, wind: 51.0, high: 20.0),
                      "51 km/h wind (> 50) moet een risico zijn.")
    }

    func testStormForce_IsRisky() {
        // Given: 120 km/h storm
        XCTAssertTrue(isRisky(rain: 0.90, wind: 120.0, high: 10.0),
                      "Stormkracht wind en zware regen moeten een risico zijn.")
    }

    // MARK: - 4. Extreme temperaturen → risico

    func testBelowFreezingTemperature_IsRisky() {
        // Given: maximumtemperatuur -10°C (< -5°C)
        XCTAssertTrue(isRisky(rain: 0.10, wind: 5.0, high: -10.0),
                      "-10°C maximumtemperatuur moet een risico zijn (vrieskou).")
    }

    func testJustBelowColdThreshold_IsRisky() {
        // Given: -5.1°C — net onder de koude drempel
        XCTAssertTrue(isRisky(rain: 0.10, wind: 5.0, high: -5.1),
                      "-5.1°C moet net een risico zijn (onder drempel).")
    }

    func testHeatwave_IsRisky() {
        // Given: maximumtemperatuur 40°C (> 38°C)
        XCTAssertTrue(isRisky(rain: 0.0, wind: 5.0, high: 40.0),
                      "40°C hittegolf moet een risico zijn (hittestress).")
    }

    func testJustAboveHeatThreshold_IsRisky() {
        // Given: 38.1°C — net boven de hittedrempel
        XCTAssertTrue(isRisky(rain: 0.0, wind: 5.0, high: 38.1),
                      "38.1°C moet net een risico zijn (boven drempel).")
    }

    // MARK: - 5. Gecombineerde condities

    func testMultipleRiskFactors_IsRisky() {
        // Given: regen én wind én hitte tegelijk
        XCTAssertTrue(isRisky(rain: 0.75, wind: 60.0, high: 39.0),
                      "Meerdere risicofactoren tegelijk moet een risico zijn.")
    }

    func testWindAndRainBothAboveThreshold_IsRisky() {
        // Given: wind 55 km/h én 70% regen
        XCTAssertTrue(isRisky(rain: 0.70, wind: 55.0, high: 15.0),
                      "Zowel wind als regen boven drempel moet een risico zijn.")
    }

    // MARK: - 6. Constanten verificatie

    func testThresholdConstants_HaveExpectedValues() {
        // Verifieer dat de drempelwaarden niet per ongeluk worden gewijzigd.
        XCTAssertEqual(WeatherSafetyEvaluator.precipitationRiskThreshold, 0.60, accuracy: 0.001)
        XCTAssertEqual(WeatherSafetyEvaluator.windRiskThresholdKmh,       50.0, accuracy: 0.001)
        XCTAssertEqual(WeatherSafetyEvaluator.coldRiskCelsius,            -5.0, accuracy: 0.001)
        XCTAssertEqual(WeatherSafetyEvaluator.heatRiskCelsius,            38.0, accuracy: 0.001)
    }

    // MARK: - 7. DayForecast delegeert correct

    func testDayForecast_IsRiskyForOutdoorTraining_DelegatesToEvaluator() {
        // Given: een DayForecast met harde wind
        let riskyDay = DayForecast(
            date: Date(),
            highCelsius: 20.0,
            lowCelsius: 10.0,
            precipitationProbability: 0.10,
            windSpeedKmh: 60.0,
            conditionDescription: "Bewolkt"
        )

        // Then: DayForecast.isRiskyForOutdoorTraining moet true zijn
        XCTAssertTrue(riskyDay.isRiskyForOutdoorTraining,
                      "DayForecast met 60 km/h wind moet isRiskyForOutdoorTraining = true retourneren.")
    }

    func testDayForecast_GoodWeather_IsNotRisky() {
        // Given: een mooie trainingsdag
        let goodDay = DayForecast(
            date: Date(),
            highCelsius: 18.0,
            lowCelsius: 10.0,
            precipitationProbability: 0.15,
            windSpeedKmh: 20.0,
            conditionDescription: "Overwegend helder"
        )

        // Then
        XCTAssertFalse(goodDay.isRiskyForOutdoorTraining,
                       "Goed weer moet isRiskyForOutdoorTraining = false retourneren.")
    }
}
