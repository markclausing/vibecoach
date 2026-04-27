import XCTest
@testable import AIFitnessCoach

/// Epic 44 Story 44.1 — `HeartRateZoneCalculator`.
/// Borgt:
///  • Karvonen-formule levert vijf opeenvolgende zones met juiste percentages
///  • Friel-LTHR-formule produceert dezelfde 5-zone-naming
///  • Gebruiker met hogere zones (Z2 = 139-157) krijgt z'n zones correct terug
///  • `zoneIndex` mapt BPM correct naar 1-5 + 0/6-grenzen
final class HeartRateZoneCalculatorTests: XCTestCase {

    // MARK: Karvonen

    func testKarvonen_TypicalAdult_ReturnsFiveContiguousZones() {
        // maxHR 190, restHR 60 → HRR 130. Zones gebaseerd op 50–60–70–80–90–100% HRR.
        let zones = HeartRateZoneCalculator.karvonen(maxHR: 190, restingHR: 60)
        XCTAssertEqual(zones.count, 5)
        XCTAssertEqual(zones.map(\.index), [1, 2, 3, 4, 5])
        XCTAssertEqual(zones[0].lowerBPM, 125) // 60 + 130 × 0.50
        XCTAssertEqual(zones[0].upperBPM, 138) // 60 + 130 × 0.60
        XCTAssertEqual(zones[1].upperBPM, 151)
        XCTAssertEqual(zones[4].upperBPM, 190)
        // Zones moeten op elkaar aansluiten — bovengrens van Z(n) = ondergrens Z(n+1).
        for i in 0..<(zones.count - 1) {
            XCTAssertEqual(zones[i].upperBPM, zones[i + 1].lowerBPM,
                           "Z\(i+1) bovengrens moet matchen met Z\(i+2) ondergrens")
        }
    }

    func testKarvonen_HighZoneAthlete_MatchesUserExpectation() {
        // Profiel van de gebruiker (zelf vermeld): Z2 = 139-157 BPM.
        // Pas maxHR + rest aan totdat Karvonen die zone produceert.
        // Met maxHR 200 + rest 65 → HRR 135. Z2 = 60-70% van 135 + 65 = 146-160. Te hoog.
        // Met maxHR 195 + rest 65 → HRR 130. Z2 = 60-70% = 143-156. Dichterbij.
        // Friel met LTHR 175 zit zelfs nog dichter (zie testFriel_HighZoneAthlete).
        // Hier alleen sanity-check dat de formule zinnige nummers geeft voor athletic profile.
        let zones = HeartRateZoneCalculator.karvonen(maxHR: 195, restingHR: 65)
        let z2 = zones[1]
        XCTAssertGreaterThan(z2.lowerBPM, 130)
        XCTAssertLessThan(z2.upperBPM, 165)
    }

    func testKarvonen_RestEqualsMax_ReturnsEmpty() {
        XCTAssertTrue(HeartRateZoneCalculator.karvonen(maxHR: 180, restingHR: 180).isEmpty)
    }

    func testKarvonen_RestAboveMax_ReturnsEmpty() {
        XCTAssertTrue(HeartRateZoneCalculator.karvonen(maxHR: 150, restingHR: 180).isEmpty)
    }

    func testKarvonen_NegativeRest_ReturnsEmpty() {
        XCTAssertTrue(HeartRateZoneCalculator.karvonen(maxHR: 180, restingHR: -10).isEmpty)
    }

    // MARK: Friel-LTHR

    func testFriel_TypicalLTHR_ReturnsFiveZones() {
        // LTHR 170. Z2 = 81-89% = 138-151 BPM.
        let zones = HeartRateZoneCalculator.friel(lactateThresholdHR: 170)
        XCTAssertEqual(zones.count, 5)
        XCTAssertEqual(zones[1].lowerBPM, 138)
        XCTAssertEqual(zones[1].upperBPM, 153) // round(170 × 0.90) = 153
    }

    func testFriel_HighZoneAthlete_MatchesUserExpectation() {
        // Friel met LTHR 175: Z2 = 81-90% = 142-158 BPM. Dat klopt zeer dicht
        // met wat de gebruiker zelf zegt (Z2 = 139-157 BPM) — Friel is voor
        // deze atleet de juiste formule.
        let zones = HeartRateZoneCalculator.friel(lactateThresholdHR: 175)
        let z2 = zones[1]
        XCTAssertEqual(z2.lowerBPM, 142)
        XCTAssertEqual(z2.upperBPM, 158)
    }

    func testFriel_ZeroLTHR_ReturnsEmpty() {
        XCTAssertTrue(HeartRateZoneCalculator.friel(lactateThresholdHR: 0).isEmpty)
    }

    func testFriel_NegativeLTHR_ReturnsEmpty() {
        XCTAssertTrue(HeartRateZoneCalculator.friel(lactateThresholdHR: -100).isEmpty)
    }

    // MARK: zoneIndex

    func testZoneIndex_BPMInZone2_ReturnsTwo() {
        let zones = HeartRateZoneCalculator.karvonen(maxHR: 190, restingHR: 60)
        XCTAssertEqual(HeartRateZoneCalculator.zoneIndex(for: 145, in: zones), 2)
    }

    func testZoneIndex_BPMBelowZone1_ReturnsZero() {
        let zones = HeartRateZoneCalculator.karvonen(maxHR: 190, restingHR: 60)
        XCTAssertEqual(HeartRateZoneCalculator.zoneIndex(for: 80, in: zones), 0,
                       "BPM onder zone 1 (recovery) telt als 'pre-zone'")
    }

    func testZoneIndex_BPMAboveZone5_ReturnsSix() {
        let zones = HeartRateZoneCalculator.karvonen(maxHR: 190, restingHR: 60)
        XCTAssertEqual(HeartRateZoneCalculator.zoneIndex(for: 200, in: zones), 6,
                       "BPM boven zone 5 telt als 'over-VO2max'")
    }

    func testZoneIndex_EmptyZones_ReturnsZero() {
        XCTAssertEqual(HeartRateZoneCalculator.zoneIndex(for: 150, in: []), 0)
    }
}
