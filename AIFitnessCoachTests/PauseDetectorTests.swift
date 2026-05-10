import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Epic #47 — `PauseDetector`. Borgt:
///  • Pre-check (sport zonder cadence/power-stream → geen detectie)
///  • Minimum-duur-grens (verkeerslicht 30s = niet, 90s pauze = wel, 50s pauze = wel)
///  • Power+cadence beide-stil-eis (alleen power=0 of alleen cadence=0 niet genoeg)
///  • Recovery-window = min(60s, pauze-duur)
///  • Pauze tot einde workout (cool-down)
///  • HR-data-edge-cases (nil-HR aan start, geen meetbare drop)
@MainActor
final class PauseDetectorTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private let baseDate = Date(timeIntervalSince1970: 1_745_625_600) // 2025-04-26
    private let workoutUUID = UUID()

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: WorkoutSample.self, configurations: config)
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: Builders

    /// Bouwt een sample-reeks op 5s-spacing met getatte waardes per index. Default
    /// duur: 1200s (20 min, 240 samples) zodat er ruimte is voor zowel actieve
    /// segmenten als pauzes zonder de pre-check te triggeren.
    private func makeSamples(count: Int = 240,
                             interval: TimeInterval = 5,
                             heartRate: (Int) -> Double? = { _ in nil },
                             power: (Int) -> Double? = { _ in nil },
                             cadence: (Int) -> Double? = { _ in nil }) -> [WorkoutSample] {
        (0..<count).map { i in
            WorkoutSample(
                workoutUUID: workoutUUID,
                timestamp: baseDate.addingTimeInterval(Double(i) * interval),
                heartRate: heartRate(i),
                speed: nil,
                power: power(i),
                cadence: cadence(i)
            )
        }
    }

    // MARK: Pre-check

    func testEmptyInput_ReturnsNoEvents() {
        XCTAssertTrue(PauseDetector.detect(in: []).isEmpty)
    }

    func testNoActivitySamples_PreCheckSkips() {
        // Zwemmen-achtige workout: geen power, geen cadence (sensors niet aanwezig).
        // Hele rit zou anders als één lange "pauze" worden geïnterpreteerd.
        let samples = makeSamples(count: 240, heartRate: { _ in 140 })
        XCTAssertTrue(PauseDetector.detect(in: samples).isEmpty,
                      "Workout zonder power/cadence-data mag geen pauzes opleveren")
    }

    func testFewerThanMinimumActivitySamples_PreCheckSkips() {
        // Slechts 5 samples met activiteit (minimum is 10). Niet genoeg signaal.
        let samples = makeSamples(count: 240,
                                  heartRate: { _ in 140 },
                                  cadence: { i in i < 5 ? 90 : 0 })
        XCTAssertTrue(PauseDetector.detect(in: samples).isEmpty)
    }

    // MARK: Minimum-duur

    func testTrafficLightStop30s_NotDetected() {
        // Stilstand van 30s (6 samples) midden in een rit. Onder de 45s-drempel.
        let samples = makeSamples(count: 240, heartRate: { _ in 140 },
                                  power: { i in (60..<66).contains(i) ? 0 : 200 },
                                  cadence: { i in (60..<66).contains(i) ? 0 : 90 })
        XCTAssertTrue(PauseDetector.detect(in: samples).isEmpty,
                      "30s-stop is verkeerslicht-ruis, niet pinnable")
    }

    func testPause50s_DetectedWithShortenedWindow() {
        // Stilstand van 50s (10 samples 60..70). Pauze ≥ 45s, window = 50s (kort dan 60s).
        let stillRange = 60..<70
        let samples = makeSamples(count: 240,
                                  heartRate: { i in
                                      if stillRange.contains(i) {
                                          // HR daalt lineair van 170 → 145 binnen het 50s-window.
                                          let elapsed = Double(i - 60) * 5.0
                                          return 170 - (25 * elapsed / 50.0)
                                      }
                                      return i < 60 ? 170 : 165
                                  },
                                  power: { i in stillRange.contains(i) ? 0 : 200 },
                                  cadence: { i in stillRange.contains(i) ? 0 : 90 })
        let events = PauseDetector.detect(in: samples)
        XCTAssertEqual(events.count, 1)
        guard let event = events.first else { return XCTFail("Verwacht één event") }
        XCTAssertEqual(event.durationSeconds, 45, accuracy: 0.01)
        XCTAssertEqual(event.measurementWindow.upperBound.timeIntervalSince(event.measurementWindow.lowerBound),
                       45, accuracy: 0.01,
                       "Voor pauze < 60s moet het meetwindow gelijk zijn aan de pauze-duur")
        XCTAssertEqual(event.hrAtPauseStart, 170, accuracy: 0.5)
        XCTAssertGreaterThan(event.drop, 20, "HR daalde 25 BPM in 50s — drop > 20 verwacht")
    }

    func testPause90s_DetectedWithFull60sWindow() {
        // Stilstand van 90s (18 samples 60..78). Window beperkt tot 60s.
        let stillRange = 60..<78
        let samples = makeSamples(count: 240,
                                  heartRate: { i in
                                      if stillRange.contains(i) {
                                          let elapsed = Double(i - 60) * 5.0
                                          // HR daalt lineair tot 130 over 90s
                                          return 180 - (50 * elapsed / 90.0)
                                      }
                                      return i < 60 ? 180 : 130
                                  },
                                  power: { i in stillRange.contains(i) ? 0 : 200 },
                                  cadence: { i in stillRange.contains(i) ? 0 : 90 })
        let events = PauseDetector.detect(in: samples)
        XCTAssertEqual(events.count, 1)
        guard let event = events.first else { return XCTFail("Verwacht één event") }
        XCTAssertEqual(event.durationSeconds, 85, accuracy: 5,
                       "Pauze-duur ≈ aantal-stille-samples × 5s")
        XCTAssertEqual(event.measurementWindow.upperBound.timeIntervalSince(event.measurementWindow.lowerBound),
                       60, accuracy: 0.01,
                       "Window moet bij ≥60s-pauze precies 60s zijn")
        // Drop in 60s ≈ 50 × (60/90) ≈ 33 BPM
        XCTAssertEqual(event.drop, 33, accuracy: 3)
    }

    // MARK: Power+cadence beide-stil-eis

    func testOnlyPowerZero_NotDetected() {
        // Power=0 maar cadence>0 (bijv. freewheelen bergaf). Geen pauze.
        let stillRange = 60..<78
        let samples = makeSamples(count: 240, heartRate: { _ in 150 },
                                  power: { i in stillRange.contains(i) ? 0 : 200 },
                                  cadence: { _ in 80 })
        XCTAssertTrue(PauseDetector.detect(in: samples).isEmpty,
                      "Freewheelen (power=0, cadence>0) is geen pauze")
    }

    func testOnlyCadenceZero_NotDetected() {
        // Cadence=0 maar power>0 (zou theoretisch kunnen door foutieve sensor).
        let stillRange = 60..<78
        let samples = makeSamples(count: 240, heartRate: { _ in 150 },
                                  power: { _ in 200 },
                                  cadence: { i in stillRange.contains(i) ? 0 : 80 })
        XCTAssertTrue(PauseDetector.detect(in: samples).isEmpty)
    }

    // MARK: Cadence-only sport (running/walking, geen powermeter)

    func testRunningWithCadenceOnly_PauseDetected() {
        // Running zonder powermeter: power overal nil, cadence stream wel aanwezig.
        // Pauze van 90s bij index 60-78 → cadence drop naar 0.
        let stillRange = 60..<78
        let samples = makeSamples(count: 240, heartRate: { _ in 150 },
                                  power: { _ in nil },
                                  cadence: { i in stillRange.contains(i) ? 0 : 170 })
        let events = PauseDetector.detect(in: samples)
        XCTAssertEqual(events.count, 1, "Cadence=0 over 90s moet als pauze tellen ook zonder powermeter")
    }

    // MARK: Cool-down aan einde

    func testPauseUntilEnd_DetectedAsCooldown() {
        // Laatste 90s van de workout zit op power=0+cadence=0 (cool-down stap-uit).
        let stillStart = 222 // index 222..240 = 18 samples = 85s
        let samples = makeSamples(count: 240,
                                  heartRate: { i in
                                      if i >= stillStart {
                                          let elapsed = Double(i - stillStart) * 5.0
                                          return 175 - (30 * elapsed / 60.0).rounded()
                                      }
                                      return 175
                                  },
                                  power: { i in i >= stillStart ? 0 : 220 },
                                  cadence: { i in i >= stillStart ? 0 : 88 })
        let events = PauseDetector.detect(in: samples)
        XCTAssertEqual(events.count, 1, "Cool-down aan het einde moet als pauze tellen")
    }

    // MARK: Multiple pauzes

    func testMultiplePauses_AllDetected() {
        // Twee pauzes: index 60..78 (90s) en 150..170 (100s).
        let pause1 = 60..<78
        let pause2 = 150..<170
        let stillIndexes = Set(pause1).union(Set(pause2))
        let samples = makeSamples(count: 240, heartRate: { _ in 150 },
                                  power: { i in stillIndexes.contains(i) ? 0 : 200 },
                                  cadence: { i in stillIndexes.contains(i) ? 0 : 90 })
        let events = PauseDetector.detect(in: samples)
        XCTAssertEqual(events.count, 2)
        XCTAssertLessThan(events[0].pauseRange.lowerBound, events[1].pauseRange.lowerBound,
                          "Events moeten op timestamp-volgorde gesorteerd zijn")
    }

    // MARK: HR-data edge cases

    func testPause_NoHRData_ReturnsNoEvent() {
        // Pauze van 90s maar HR-stream is leeg. Zonder hrStart kunnen we geen drop berekenen.
        let stillRange = 60..<78
        let samples = makeSamples(count: 240,
                                  heartRate: { _ in nil },
                                  power: { i in stillRange.contains(i) ? 0 : 200 },
                                  cadence: { i in stillRange.contains(i) ? 0 : 90 })
        XCTAssertTrue(PauseDetector.detect(in: samples).isEmpty,
                      "Pauze zonder HR-data kan geen recovery-event opleveren")
    }

    func testPause_FlatHR_DropZero() {
        // Pauze van 90s, HR blijft op 175 BPM (geen herstel — gebrickt parasympatisch).
        let stillRange = 60..<78
        let samples = makeSamples(count: 240, heartRate: { _ in 175 },
                                  power: { i in stillRange.contains(i) ? 0 : 200 },
                                  cadence: { i in stillRange.contains(i) ? 0 : 90 })
        let events = PauseDetector.detect(in: samples)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.drop ?? -1, 0, accuracy: 0.01,
                       "Vlak HR-profiel = drop=0 (caller filtert dit alsnog uit voor pin)")
    }
}
