import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Unit tests voor `ActivityDeduplicator`. Borgt:
///  • Groepering op startDate ±5s + sportCategory
///  • Score-prioriteit (samples > deviceWatts > trimp > avgHR)
///  • Stable tiebreaker bij gelijke score
///  • Decide-output bevat exact één winnaar per groep
@MainActor
final class ActivityDeduplicatorTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private let baseDate = Date(timeIntervalSince1970: 1_745_625_600) // 2025-04-26

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ActivityRecord.self, configurations: config)
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: Helpers

    @discardableResult
    private func makeRecord(id: String,
                            startOffset: TimeInterval = 0,
                            sportCategory: SportCategory = .cycling,
                            trimp: Double? = nil,
                            avgHR: Double? = nil,
                            deviceWatts: Bool? = nil) -> ActivityRecord {
        let record = ActivityRecord(
            id: id,
            name: "Test \(id)",
            distance: 10_000,
            movingTime: 3600,
            averageHeartrate: avgHR,
            sportCategory: sportCategory,
            startDate: baseDate.addingTimeInterval(startOffset),
            trimp: trimp,
            deviceWatts: deviceWatts
        )
        context.insert(record)
        return record
    }

    // MARK: Group

    func testGroupsRecordsWithinFiveSecondWindowAndSameSport() {
        let a = makeRecord(id: "A", startOffset: 0, sportCategory: .cycling)
        let b = makeRecord(id: "B", startOffset: 3, sportCategory: .cycling) // ±5s window
        let c = makeRecord(id: "C", startOffset: 100, sportCategory: .cycling) // outside

        let groups = ActivityDeduplicator.findDuplicateGroups([a, b, c])

        XCTAssertEqual(groups.count, 2, "A+B vormen één groep, C is alleen")
        XCTAssertEqual(Set(groups[0].map(\.id)), Set(["A", "B"]))
        XCTAssertEqual(groups[1].map(\.id), ["C"])
    }

    func testDoesNotGroupAcrossSports() {
        let cycling = makeRecord(id: "cycle", startOffset: 0, sportCategory: .cycling)
        let running = makeRecord(id: "run", startOffset: 0, sportCategory: .running)

        let groups = ActivityDeduplicator.findDuplicateGroups([cycling, running])
        XCTAssertEqual(groups.count, 2, "Verschillende sport = aparte rit, ook bij gelijke startDate")
    }

    func testFiveSecondBoundaryIsInclusive() {
        let a = makeRecord(id: "A", startOffset: 0)
        let b = makeRecord(id: "B", startOffset: 5)
        let groups = ActivityDeduplicator.findDuplicateGroups([a, b])
        XCTAssertEqual(groups.count, 1, "Exact 5s zou nog binnen tolerantie moeten vallen")
    }

    // MARK: Score

    func testStravaWithSamplesBeatsHKWithoutSamples() {
        // Klassiek scenario: HK heeft alleen avg HR; Strava heeft samples + deviceWatts.
        let hk     = makeRecord(id: UUID().uuidString,    startOffset: 0, trimp: 80, avgHR: 145)
        let strava = makeRecord(id: "12345678901",        startOffset: 1, trimp: 80, avgHR: 145, deviceWatts: true)

        let counts: [String: Int] = [hk.id: 0, strava.id: 720]
        let decision = ActivityDeduplicator.decide(records: [hk, strava]) { counts[$0.id] ?? 0 }

        XCTAssertEqual(decision.winners.count, 1)
        XCTAssertEqual(decision.winners.first?.id, strava.id,
                       "Strava-record met samples + deviceWatts moet winnen — anders verlies je power")
        XCTAssertEqual(decision.losers.count, 1)
        XCTAssertEqual(decision.losers.first?.id, hk.id)
    }

    func testDeviceWattsAlsoWinsWithoutSamples() {
        // Edge: Strava-record nog niet door backfill. deviceWatts is dan het sterkste signal.
        let hk     = makeRecord(id: UUID().uuidString, startOffset: 0, trimp: 80, avgHR: 145)
        let strava = makeRecord(id: "12345678901",     startOffset: 0, trimp: 80, avgHR: 145, deviceWatts: true)

        let decision = ActivityDeduplicator.decide(records: [hk, strava]) { _ in 0 }
        XCTAssertEqual(decision.winners.first?.id, strava.id,
                       "deviceWatts is een belofte van rijke data, ook vóór backfill — Strava moet winnen")
    }

    func testHKWithSamplesBeatsStravaWithoutDeviceWatts() {
        // Edge: HK heeft samples (via story 32.1 deep-sync), Strava is een running record
        // zonder powermeter. HK is rijker.
        let strava = makeRecord(id: "12345678901",     startOffset: 0, sportCategory: .running, trimp: 80, avgHR: 145)
        let hk     = makeRecord(id: UUID().uuidString, startOffset: 0, sportCategory: .running, trimp: 80, avgHR: 145)

        let counts = [strava.id: 0, hk.id: 720]
        let decision = ActivityDeduplicator.decide(records: [strava, hk]) { counts[$0.id] ?? 0 }
        XCTAssertEqual(decision.winners.first?.id, hk.id,
                       "HK met samples wint van Strava zonder samples + zonder power")
    }

    // MARK: Tiebreaker

    func testStableTiebreakerOnEqualScore() {
        let a = makeRecord(id: "AAA", startOffset: 0, trimp: 80, avgHR: 145)
        let b = makeRecord(id: "ZZZ", startOffset: 0, trimp: 80, avgHR: 145)

        let decision = ActivityDeduplicator.decide(records: [a, b]) { _ in 0 }
        XCTAssertEqual(decision.winners.first?.id, "ZZZ",
                       "Bij gelijke score wint de hoogste id (stabiel + deterministisch)")
    }

    // MARK: Singletons

    func testSingleRecordGroupHasNoLosers() {
        let solo = makeRecord(id: "solo", startOffset: 0, trimp: 80)
        let decision = ActivityDeduplicator.decide(records: [solo]) { _ in 0 }
        XCTAssertEqual(decision.winners.count, 1)
        XCTAssertEqual(decision.losers.count, 0)
    }

    func testEmptyInput() {
        let decision = ActivityDeduplicator.decide(records: []) { _ in 0 }
        XCTAssertTrue(decision.winners.isEmpty)
        XCTAssertTrue(decision.losers.isEmpty)
    }

    // MARK: Multi-group

    func testMultipleGroupsHandledIndependently() {
        // Twee paren duplicaten op verschillende dagen.
        let dayOneHK     = makeRecord(id: UUID().uuidString, startOffset: 0)
        let dayOneStrava = makeRecord(id: "111111", startOffset: 1, deviceWatts: true)

        let dayTwoOffset: TimeInterval = 86_400
        let dayTwoHK     = makeRecord(id: UUID().uuidString, startOffset: dayTwoOffset)
        let dayTwoStrava = makeRecord(id: "222222", startOffset: dayTwoOffset + 2, deviceWatts: true)

        let decision = ActivityDeduplicator.decide(records: [dayOneHK, dayOneStrava, dayTwoHK, dayTwoStrava]) { _ in 0 }

        XCTAssertEqual(decision.winners.count, 2)
        XCTAssertEqual(decision.losers.count, 2)
        // Beide Strava-records (deviceWatts) moeten winnen
        XCTAssertEqual(Set(decision.winners.map(\.id)), Set(["111111", "222222"]))
    }
}
