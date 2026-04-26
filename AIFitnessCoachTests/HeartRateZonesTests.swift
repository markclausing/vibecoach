import XCTest
@testable import AIFitnessCoach

/// Unit tests voor `HeartRateZones`. Verifieert Tanaka-formule + fallback-gedrag.
final class HeartRateZonesTests: XCTestCase {

    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14

    private func birthDate(yearsAgo: Int) -> Date {
        Calendar.current.date(byAdding: .year, value: -yearsAgo, to: referenceDate)!
    }

    func testTanakaFormulaForTypicalAdult() {
        // 40-jarige: 208 - 0.7×40 = 180
        let result = HeartRateZones.estimatedMaxHeartRate(
            birthDate: birthDate(yearsAgo: 40),
            now: referenceDate
        )
        XCTAssertEqual(result, 180, accuracy: 0.5)
    }

    func testTanakaFormulaForYoungAdult() {
        // 25-jarige: 208 - 0.7×25 = 190.5
        let result = HeartRateZones.estimatedMaxHeartRate(
            birthDate: birthDate(yearsAgo: 25),
            now: referenceDate
        )
        XCTAssertEqual(result, 190.5, accuracy: 0.5)
    }

    func testTanakaFormulaForSenior() {
        // 65-jarige: 208 - 0.7×65 = 162.5
        let result = HeartRateZones.estimatedMaxHeartRate(
            birthDate: birthDate(yearsAgo: 65),
            now: referenceDate
        )
        XCTAssertEqual(result, 162.5, accuracy: 0.5)
    }

    func testNilBirthDateFallsBackToDefault() {
        let result = HeartRateZones.estimatedMaxHeartRate(birthDate: nil, now: referenceDate)
        XCTAssertEqual(result, HeartRateZones.defaultMaxHeartRate)
    }

    func testFutureBirthDateFallsBackToDefault() {
        // Geboortedatum in de toekomst → ongeldig → fallback.
        let future = referenceDate.addingTimeInterval(86_400 * 30)
        let result = HeartRateZones.estimatedMaxHeartRate(birthDate: future, now: referenceDate)
        XCTAssertEqual(result, HeartRateZones.defaultMaxHeartRate)
    }

    func testRidiculouslyOldBirthDateFallsBackToDefault() {
        // 150 jaar geleden — onmogelijk levend → fallback.
        let result = HeartRateZones.estimatedMaxHeartRate(
            birthDate: birthDate(yearsAgo: 150),
            now: referenceDate
        )
        XCTAssertEqual(result, HeartRateZones.defaultMaxHeartRate)
    }

    func testDefaultMaxHeartRateIsRealistic() {
        // Sanity-check: 190 ligt binnen normale range voor jonge volwassenen.
        XCTAssertGreaterThanOrEqual(HeartRateZones.defaultMaxHeartRate, 170)
        XCTAssertLessThanOrEqual(HeartRateZones.defaultMaxHeartRate, 210)
    }
}
