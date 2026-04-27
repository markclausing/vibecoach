import XCTest
@testable import AIFitnessCoach

/// Epic 44 Story 44.1 — `PowerZoneCalculator`.
/// Borgt:
///  • Coggan 7-zone-model levert correcte percentages
///  • Top-zone (Z7) heeft geen bovengrens
///  • `zoneIndex` mapt watt → 1-7 met correcte 0-grens en open Z7
final class PowerZoneCalculatorTests: XCTestCase {

    func testCoggan_TypicalFTP_ReturnsSevenZones() {
        // FTP 250 W: standaard recreatieve cyclist.
        let zones = PowerZoneCalculator.coggan(ftp: 250)
        XCTAssertEqual(zones.count, 7)
        XCTAssertEqual(zones.map(\.index), [1, 2, 3, 4, 5, 6, 7])
        // Z2 Endurance = 56-75% van 250 = 140-188 W.
        XCTAssertEqual(zones[1].lowerWatts, 140)
        XCTAssertEqual(zones[1].upperWatts, 188)
        // Z4 Lactate Threshold = 91-105% van 250 = 228-263 W.
        XCTAssertEqual(zones[3].lowerWatts, 228)
        XCTAssertEqual(zones[3].upperWatts, 263)
    }

    func testCoggan_TopZoneHasNoUpperBound() {
        let zones = PowerZoneCalculator.coggan(ftp: 250)
        XCTAssertNil(zones[6].upperWatts,
                     "Z7 (Neuromuscular Power) is open-ended — sprintvermogen heeft geen plafond")
    }

    func testCoggan_ZeroFTP_ReturnsEmpty() {
        XCTAssertTrue(PowerZoneCalculator.coggan(ftp: 0).isEmpty)
    }

    func testCoggan_NegativeFTP_ReturnsEmpty() {
        XCTAssertTrue(PowerZoneCalculator.coggan(ftp: -50).isEmpty)
    }

    func testZoneIndex_PowerInZone2_ReturnsTwo() {
        let zones = PowerZoneCalculator.coggan(ftp: 250)
        XCTAssertEqual(PowerZoneCalculator.zoneIndex(for: 165, in: zones), 2)
    }

    func testZoneIndex_PowerInZone4_ReturnsFour() {
        let zones = PowerZoneCalculator.coggan(ftp: 250)
        XCTAssertEqual(PowerZoneCalculator.zoneIndex(for: 245, in: zones), 4)
    }

    func testZoneIndex_PowerWayAboveFTP_ReturnsZ7() {
        // Sprint van 800 W bij FTP 250 — valt in open Z7.
        let zones = PowerZoneCalculator.coggan(ftp: 250)
        XCTAssertEqual(PowerZoneCalculator.zoneIndex(for: 800, in: zones), 7)
    }

    func testZoneIndex_NegativePower_ReturnsZero() {
        // Theoretisch onmogelijk maar tests defensief.
        let zones = PowerZoneCalculator.coggan(ftp: 250)
        XCTAssertEqual(PowerZoneCalculator.zoneIndex(for: -10, in: zones), 0)
    }

    func testZoneIndex_EmptyZones_ReturnsZero() {
        XCTAssertEqual(PowerZoneCalculator.zoneIndex(for: 200, in: []), 0)
    }

    func testCoggan_LowFTP_ZonesScaleProportionally() {
        // FTP 150 W (beginner): Z2 = 56-75% = 84-113 W.
        let zones = PowerZoneCalculator.coggan(ftp: 150)
        XCTAssertEqual(zones[1].lowerWatts, 84)
        XCTAssertEqual(zones[1].upperWatts, 113)
    }
}
