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

    func testDoesNotGroupAcrossSportsWhenTimeOffsetExists() {
        // 3s drift + verschillende sport: loose check vereist sport-match → geen groepering.
        let cycling = makeRecord(id: "cycle", startOffset: 0, sportCategory: .cycling)
        let running = makeRecord(id: "run", startOffset: 3, sportCategory: .running)

        let groups = ActivityDeduplicator.findDuplicateGroups([cycling, running])
        XCTAssertEqual(groups.count, 2, "Bij timestamp-drift moet sport-categorie wel matchen — anders false positive")
    }

    func testGroupsAcrossSportsAtIdenticalTimestamp() {
        // Strict-time bypass: bij identieke tijd wint de aanname dat het mapping-
        // verschil is, niet twee parallel uitgevoerde workouts. Dit is exact het
        // scenario uit de bug-melding: HK 'Training' (.other) + Strava 'Evening
        // Weight Training' (.strength) op exact dezelfde seconde.
        let hk     = makeRecord(id: UUID().uuidString, startOffset: 0, sportCategory: .other)
        let strava = makeRecord(id: "12345678901",     startOffset: 0, sportCategory: .strength)

        let groups = ActivityDeduplicator.findDuplicateGroups([hk, strava])
        XCTAssertEqual(groups.count, 1,
                       "Identieke timestamp + verschillende sport = mapping-issue, dedupe-kandidaten")
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

    // MARK: Cross-source weather-merge (Epic #49)

    func testEnrichEmptyFields_copiesWeatherFromLoserToWinner() {
        let strava = ActivityRecord(
            id: "strava-1",
            name: "Ride",
            distance: 50_000, movingTime: 3600, averageHeartrate: 145,
            sportCategory: .cycling, startDate: baseDate
        )
        let hk = ActivityRecord(
            id: "hk-1",
            name: "Ride",
            distance: 50_000, movingTime: 3600, averageHeartrate: 145,
            sportCategory: .cycling, startDate: baseDate,
            temperatureCelsius: 27.5, humidityPercent: 68.0
        )

        ActivityDeduplicator.enrichEmptyFields(into: strava, from: hk)

        XCTAssertEqual(strava.temperatureCelsius, 27.5,
                       "Strava-winner moet HK-temperatuur overnemen")
        XCTAssertEqual(strava.humidityPercent, 68.0)
    }

    func testEnrichEmptyFields_doesNotOverwriteExistingValues() {
        let winner = ActivityRecord(
            id: "w",
            name: "Ride",
            distance: 10_000, movingTime: 1800, averageHeartrate: 140,
            sportCategory: .cycling, startDate: baseDate,
            temperatureCelsius: 22.0, humidityPercent: 50.0
        )
        let loser = ActivityRecord(
            id: "l",
            name: "Ride",
            distance: 10_000, movingTime: 1800, averageHeartrate: 140,
            sportCategory: .cycling, startDate: baseDate,
            temperatureCelsius: 99.0, humidityPercent: 99.0
        )

        ActivityDeduplicator.enrichEmptyFields(into: winner, from: loser)

        XCTAssertEqual(winner.temperatureCelsius, 22.0,
                       "Bestaande winner-waarde mag niet overschreven worden")
        XCTAssertEqual(winner.humidityPercent, 50.0)
    }

    func testSmartInsert_skippedExistingRicher_enrichesExistingWithCandidateWeather() throws {
        // Bestaand Strava-record (rijker via deviceWatts) zonder weer.
        let strava = makeRecord(id: "strava-1", startOffset: 0, deviceWatts: true)
        try context.save()

        // HK-record komt binnen met weer-metadata. Strava is rijker → HK wordt
        // geweigerd, maar de weer-velden moeten doorgesluisd worden naar Strava.
        let hk = ActivityRecord(
            id: UUID().uuidString,
            name: "HK ride",
            distance: 10_000, movingTime: 3600, averageHeartrate: 145,
            sportCategory: .cycling,
            startDate: baseDate.addingTimeInterval(2),
            temperatureCelsius: 28.0, humidityPercent: 71.0
        )

        let result = try ActivityDeduplicator.smartInsert(hk, into: context)

        XCTAssertEqual(result, .skippedExistingRicher)
        XCTAssertEqual(strava.temperatureCelsius, 28.0,
                       "Strava-record moet HK-weather overnemen ondanks dat HK geweigerd wordt")
        XCTAssertEqual(strava.humidityPercent, 71.0)
    }

    func testSmartInsert_skippedSameSource_enrichesExistingWithCandidateWeather() throws {
        // Bestaande Strava-record uit eerdere sync zonder weer.
        let strava = makeRecord(id: "strava-1", startOffset: 0, deviceWatts: true)
        try context.save()
        XCTAssertNil(strava.temperatureCelsius)

        // Re-sync: zelfde Strava-id, maar nu mét Open-Meteo-data uit Epic #50.
        // Laag 1 (id-match) skipt de insert, maar de weer-velden moeten doorvloeien
        // naar het bestaande record — anders gaat de fetch verloren bij elke re-sync.
        let resync = ActivityRecord(
            id: "strava-1",
            name: "Re-synced ride",
            distance: 10_000, movingTime: 3600, averageHeartrate: 145,
            sportCategory: .cycling, startDate: baseDate,
            deviceWatts: true,
            temperatureCelsius: 26.5, humidityPercent: 64.0
        )

        let result = try ActivityDeduplicator.smartInsert(resync, into: context)

        XCTAssertEqual(result, .skippedSameSource)
        XCTAssertEqual(strava.temperatureCelsius, 26.5,
                       "Bestaande record moet weer-data van re-sync candidate erven")
        XCTAssertEqual(strava.humidityPercent, 64.0)
    }

    func testSmartInsert_skippedSameSource_doesNotOverwriteExistingWeather() throws {
        // Bestaande record had al weer-data (bv. uit eerdere Open-Meteo-fetch).
        // Re-sync mag die niet overschrijven, ook niet als nieuwe waarde verschilt.
        let strava = ActivityRecord(
            id: "strava-2",
            name: "Ride",
            distance: 10_000, movingTime: 3600, averageHeartrate: 145,
            sportCategory: .cycling, startDate: baseDate,
            deviceWatts: true,
            temperatureCelsius: 22.0, humidityPercent: 50.0
        )
        context.insert(strava)
        try context.save()

        let resync = ActivityRecord(
            id: "strava-2",
            name: "Re-synced",
            distance: 10_000, movingTime: 3600, averageHeartrate: 145,
            sportCategory: .cycling, startDate: baseDate,
            deviceWatts: true,
            temperatureCelsius: 99.0, humidityPercent: 99.0
        )

        let result = try ActivityDeduplicator.smartInsert(resync, into: context)

        XCTAssertEqual(result, .skippedSameSource)
        XCTAssertEqual(strava.temperatureCelsius, 22.0,
                       "Bestaande weer-waarde mag niet overschreven worden bij re-sync")
        XCTAssertEqual(strava.humidityPercent, 50.0)
    }

    func testSmartInsert_replaced_carriesOverWeatherFromOldRecord() throws {
        // Bestaand HK-record met weer (armer want geen power).
        let hk = ActivityRecord(
            id: UUID().uuidString,
            name: "HK ride",
            distance: 10_000, movingTime: 3600, averageHeartrate: 145,
            sportCategory: .cycling, startDate: baseDate,
            temperatureCelsius: 26.0, humidityPercent: 60.0
        )
        context.insert(hk)
        try context.save()

        // Strava-record komt binnen, rijker → vervangt HK. Weer mag niet verloren gaan.
        let strava = ActivityRecord(
            id: "strava-1",
            name: "Strava ride",
            distance: 10_000, movingTime: 3600, averageHeartrate: 145,
            sportCategory: .cycling,
            startDate: baseDate.addingTimeInterval(1),
            deviceWatts: true
        )

        let result = try ActivityDeduplicator.smartInsert(strava, into: context)

        XCTAssertEqual(result, .replaced)
        XCTAssertEqual(strava.temperatureCelsius, 26.0,
                       "Vervangende Strava-record moet HK-weather erfen")
        XCTAssertEqual(strava.humidityPercent, 60.0)
    }
}
