import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Unit tests voor `SessionReclassifier` (Epic 40 Story 40.4). Borgt:
///  • Manual override (gebruiker-keuze) wordt nooit overschreven
///  • Records zonder samples worden overgeslagen (geen upgrade-potentieel)
///  • Records met samples krijgen het zone-distributie-voorstel als dat verandert
///  • Idempotentie — een tweede run op een schone DB doet niets
@MainActor
final class SessionReclassifierTests: XCTestCase {

    private let baseDate = Date(timeIntervalSince1970: 1_745_625_600) // 2025-04-26
    private let maxHR: Double = 190 // Default voor zone-percentage

    // MARK: Helpers

    private func makeRecord(id: String,
                            sessionType: SessionType? = nil,
                            avgHR: Double? = nil,
                            manualOverride: Bool? = nil) -> ActivityRecord {
        ActivityRecord(
            id: id,
            name: "Test \(id)",
            distance: 10_000,
            movingTime: 3600,
            averageHeartrate: avgHR,
            sportCategory: .cycling,
            startDate: baseDate,
            trimp: 80,
            sessionType: sessionType,
            manualSessionTypeOverride: manualOverride
        )
    }

    /// Bouwt een sample-reeks waarvan de zone-distributie eenduidig één type uitlokt.
    /// vo2Max-profiel = ≥25% HR ≥0.90 × maxHR.
    private func vo2MaxSamples(count: Int = 60) -> [WorkoutSample] {
        var samples: [WorkoutSample] = []
        for i in 0..<count {
            let pct: Double = (i % 4 == 0) ? 0.95 : 0.85 // 25% in Z5, 75% in Z4
            samples.append(WorkoutSample(
                workoutUUID: UUID(),
                timestamp: baseDate.addingTimeInterval(Double(i) * 5),
                heartRate: pct * maxHR
            ))
        }
        return samples
    }

    /// Recovery-profiel = >60% HR onder 0.60 × maxHR.
    private func recoverySamples(count: Int = 60) -> [WorkoutSample] {
        (0..<count).map { i in
            WorkoutSample(
                workoutUUID: UUID(),
                timestamp: baseDate.addingTimeInterval(Double(i) * 5),
                heartRate: 0.50 * maxHR
            )
        }
    }

    // MARK: Manual override

    func testManualOverrideIsNeverChanged() {
        let record = makeRecord(id: "A", sessionType: .recovery, manualOverride: true)
        let changes = SessionReclassifier.decide(records: [record], maxHeartRate: maxHR) { _ in
            self.vo2MaxSamples() // Zou normaal vo2Max voorstellen
        }
        XCTAssertTrue(changes.isEmpty, "Manual override moet de classifier blokkeren — anders verlies je een gebruiker-keuze")
    }

    // MARK: Geen samples → skip

    func testRecordWithoutSamplesIsSkipped() {
        let record = makeRecord(id: "A", sessionType: nil, avgHR: 145)
        let changes = SessionReclassifier.decide(records: [record], maxHeartRate: maxHR) { _ in [] }
        XCTAssertTrue(changes.isEmpty, "Zonder samples geen rerun — avg-HR draaide al bij ingest")
    }

    // MARK: Upgrade van avg-HR-classificatie naar zone-based

    func testHKRecordWithAvgHRGetsUpgradedToZoneBasedAfterSamples() {
        // Bij ingest gaf avg-HR-fallback `tempo` (0.76 × maxHR over 60 min). Nu komen er
        // samples binnen die 25% Z5 laten zien — vo2Max is dan correcter.
        let record = makeRecord(id: "A", sessionType: .tempo, avgHR: 0.76 * maxHR)
        let changes = SessionReclassifier.decide(records: [record], maxHeartRate: maxHR) { _ in
            self.vo2MaxSamples()
        }
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.newType, .vo2Max,
                       "Zone-distributie moet de eerdere avg-HR-fallback overrulen")
    }

    // MARK: Strava-record (sessionType=nil) krijgt classificatie

    func testStravaRecordWithoutSessionTypeGetsClassifiedAfterBackfill() {
        let record = makeRecord(id: "12345678901", sessionType: nil)
        let changes = SessionReclassifier.decide(records: [record], maxHeartRate: maxHR) { _ in
            self.recoverySamples()
        }
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.newType, .recovery,
                       "Strava-record had nog geen type — moet er nu een krijgen")
    }

    // MARK: Idempotentie

    func testNoChangeIfClassificationMatchesExistingType() {
        // Record heeft al `.recovery`, samples bevestigen dat — geen wijziging.
        let record = makeRecord(id: "A", sessionType: .recovery)
        let changes = SessionReclassifier.decide(records: [record], maxHeartRate: maxHR) { _ in
            self.recoverySamples()
        }
        XCTAssertTrue(changes.isEmpty, "Geen save als de classifier hetzelfde type teruggeeft — idempotent")
    }

    // MARK: Multi-record flow

    func testMixedBatchOnlyChangesEligibleRecords() {
        let manual    = makeRecord(id: "manual",    sessionType: .recovery, manualOverride: true)  // skip
        let stravaNew = makeRecord(id: "stravaNew", sessionType: nil)                              // classify
        let hkOld     = makeRecord(id: "hkOld",     sessionType: .tempo, avgHR: 0.76 * maxHR)      // upgrade
        let noSamples = makeRecord(id: "noSamples", sessionType: nil)                              // skip
        let unchanged = makeRecord(id: "unchanged", sessionType: .recovery)                        // idempotent

        let samplesByID: [String: [WorkoutSample]] = [
            "manual":    vo2MaxSamples(),
            "stravaNew": recoverySamples(),
            "hkOld":     vo2MaxSamples(),
            "unchanged": recoverySamples(),
            // noSamples → leeg
        ]

        let changes = SessionReclassifier.decide(
            records: [manual, stravaNew, hkOld, noSamples, unchanged],
            maxHeartRate: maxHR
        ) { samplesByID[$0.id] ?? [] }

        XCTAssertEqual(changes.count, 2)
        let byID = Dictionary(uniqueKeysWithValues: changes.map { ($0.record.id, $0.newType) })
        XCTAssertEqual(byID["stravaNew"], .recovery)
        XCTAssertEqual(byID["hkOld"], .vo2Max)
    }
}
