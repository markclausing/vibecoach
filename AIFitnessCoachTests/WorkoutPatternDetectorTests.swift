import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Epic 32 Story 32.3a — `WorkoutPatternDetector`.
/// Borgt:
///  • Drempel-grenzen (juist boven mild = mild; juist boven significant = significant)
///  • Skip-paden (te kort, geen data, ontbrekende metrics)
///  • Stabiele workouts triggeren niets
///  • `detectAll` aggregeert correct
@MainActor
final class WorkoutPatternDetectorTests: XCTestCase {

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

    /// Bouwt N samples op `interval`-spacing met optionele waardes. Default duur:
    /// 1200s (20 min) zodat detectoren niet op de short-circuit struikelen.
    private func makeSamples(count: Int = 240,
                             interval: TimeInterval = 5,
                             heartRate: (Int) -> Double? = { _ in nil },
                             power: (Int) -> Double? = { _ in nil },
                             speed: (Int) -> Double? = { _ in nil },
                             cadence: (Int) -> Double? = { _ in nil }) -> [WorkoutSample] {
        (0..<count).map { i in
            WorkoutSample(
                workoutUUID: workoutUUID,
                timestamp: baseDate.addingTimeInterval(Double(i) * interval),
                heartRate: heartRate(i),
                speed: speed(i),
                power: power(i),
                cadence: cadence(i)
            )
        }
    }

    // MARK: Skip-paden

    func testEmptyInput_AllDetectorsReturnNil() {
        let samples: [WorkoutSample] = []
        XCTAssertNil(WorkoutPatternDetector.detectAerobicDecoupling(in: samples))
        XCTAssertNil(WorkoutPatternDetector.detectCardiacDrift(in: samples))
        XCTAssertNil(WorkoutPatternDetector.detectCadenceFade(in: samples))
        XCTAssertNil(WorkoutPatternDetector.detectHeartRateRecovery(in: samples))
        XCTAssertTrue(WorkoutPatternDetector.detectAll(in: samples).isEmpty)
    }

    func testTooShortWorkout_HalvesAndCadenceSkipped() {
        // 5 minuten = 300s, onder de 600s minimum-grens.
        let samples = makeSamples(count: 60, heartRate: { _ in 150 }, cadence: { _ in 90 })
        XCTAssertNil(WorkoutPatternDetector.detectAerobicDecoupling(in: samples))
        XCTAssertNil(WorkoutPatternDetector.detectCardiacDrift(in: samples))
        XCTAssertNil(WorkoutPatternDetector.detectCadenceFade(in: samples))
    }

    // MARK: Cardiac drift

    func testCardiacDrift_StableHR_ReturnsNil() {
        // Constante 150 BPM: 0% drift, geen patroon.
        let samples = makeSamples(heartRate: { _ in 150 })
        XCTAssertNil(WorkoutPatternDetector.detectCardiacDrift(in: samples))
    }

    func testCardiacDrift_BelowMildThreshold_ReturnsNil() {
        // ~2% drift: 145 → 148. Onder mild-grens (3%).
        let samples = makeSamples(heartRate: { i in i < 120 ? 145 : 148 })
        XCTAssertNil(WorkoutPatternDetector.detectCardiacDrift(in: samples))
    }

    func testCardiacDrift_AboveMildThreshold_ReturnsMild() {
        // ~3.4% drift: 145 → 150. Boven mild (3%), onder moderate (5%).
        let samples = makeSamples(heartRate: { i in i < 120 ? 145 : 150 })
        guard let pattern = WorkoutPatternDetector.detectCardiacDrift(in: samples) else {
            return XCTFail("Verwacht mild drift-patroon")
        }
        XCTAssertEqual(pattern.kind, .cardiacDrift)
        XCTAssertEqual(pattern.severity, .mild)
        XCTAssertEqual(pattern.value, (150.0 / 145.0 - 1) * 100, accuracy: 0.1)
    }

    func testCardiacDrift_ModerateRange_ReturnsModerate() {
        // ~6.2% drift: 145 → 154. Boven moderate (5%), onder significant (8%).
        let samples = makeSamples(heartRate: { i in i < 120 ? 145 : 154 })
        guard let pattern = WorkoutPatternDetector.detectCardiacDrift(in: samples) else {
            return XCTFail("Verwacht moderate drift-patroon")
        }
        XCTAssertEqual(pattern.severity, .moderate)
    }

    func testCardiacDrift_AboveSignificantThreshold_ReturnsSignificant() {
        // ~10.3% drift: 145 → 160. Boven significant (8%).
        let samples = makeSamples(heartRate: { i in i < 120 ? 145 : 160 })
        guard let pattern = WorkoutPatternDetector.detectCardiacDrift(in: samples) else {
            return XCTFail("Verwacht significant drift-patroon")
        }
        XCTAssertEqual(pattern.severity, .significant)
        XCTAssertTrue(pattern.detail.contains("Cardiac drift"))
    }

    func testCardiacDrift_NegativeDrift_ReturnsNil() {
        // HR daalt — sterker geworden tijdens de workout, niet zorgwekkend.
        let samples = makeSamples(heartRate: { i in i < 120 ? 160 : 150 })
        XCTAssertNil(WorkoutPatternDetector.detectCardiacDrift(in: samples))
    }

    func testCardiacDrift_NoHeartRateData_ReturnsNil() {
        let samples = makeSamples(power: { _ in 200 })
        XCTAssertNil(WorkoutPatternDetector.detectCardiacDrift(in: samples))
    }

    // MARK: Aerobic decoupling

    func testAerobicDecoupling_StablePowerAndHR_ReturnsNil() {
        // Power 200W constant, HR 150 constant: HR/W = 0.75 in beide helften.
        let samples = makeSamples(heartRate: { _ in 150 }, power: { _ in 200 })
        XCTAssertNil(WorkoutPatternDetector.detectAerobicDecoupling(in: samples))
    }

    func testAerobicDecoupling_PowerBased_HRDriftsAtSamePower_ReturnsPattern() {
        // Power blijft 200W, HR drift 150 → 165 (10% HR-stijging bij gelijk vermogen).
        // Pa:HR-ratio drift = ((165/200) / (150/200) - 1) * 100 = 10% → significant.
        let samples = makeSamples(heartRate: { i in i < 120 ? 150 : 165 },
                                  power: { _ in 200 })
        guard let pattern = WorkoutPatternDetector.detectAerobicDecoupling(in: samples) else {
            return XCTFail("Verwacht decoupling-patroon")
        }
        XCTAssertEqual(pattern.kind, .aerobicDecoupling)
        XCTAssertEqual(pattern.severity, .significant)
        XCTAssertTrue(pattern.detail.contains("vermogen"),
                      "Detail moet 'vermogen' vermelden bij power-based decoupling, kreeg: \(pattern.detail)")
    }

    func testAerobicDecoupling_FallsBackToSpeedWhenNoPower() {
        // Speed 3 m/s constant, HR drift 150 → 165 (10% drift).
        let samples = makeSamples(heartRate: { i in i < 120 ? 150 : 165 },
                                  speed: { _ in 3.0 })
        guard let pattern = WorkoutPatternDetector.detectAerobicDecoupling(in: samples) else {
            return XCTFail("Verwacht speed-based decoupling-patroon")
        }
        XCTAssertTrue(pattern.detail.contains("tempo"),
                      "Detail moet 'tempo' vermelden bij speed-fallback, kreeg: \(pattern.detail)")
    }

    func testAerobicDecoupling_NoIntensityData_ReturnsNil() {
        // Alleen HR — decoupling vereist power óf speed.
        let samples = makeSamples(heartRate: { i in i < 120 ? 150 : 165 })
        XCTAssertNil(WorkoutPatternDetector.detectAerobicDecoupling(in: samples))
    }

    func testAerobicDecoupling_HighPowerVariance_ReturnsNil() {
        // Stop-and-go-rit: power oscilleert tussen 100W en 300W (CV ≈ 0.50).
        // HR drift 150 → 165 ziet eruit als decoupling, maar door de variabele
        // inspanning is de Pa:HR-ratio onbetrouwbaar — detector moet zwijgen.
        let samples = makeSamples(heartRate: { i in i < 120 ? 150 : 165 },
                                  power: { i in i.isMultiple(of: 2) ? 100 : 300 })
        XCTAssertNil(WorkoutPatternDetector.detectAerobicDecoupling(in: samples),
                     "Bij chaotische power moet decoupling-meting overgeslagen worden")
    }

    func testAerobicDecoupling_HighSpeedVariance_ReturnsNil() {
        // Idem voor pace-fallback: variabele snelheid is geen steady-state.
        let samples = makeSamples(heartRate: { i in i < 120 ? 150 : 165 },
                                  speed: { i in i.isMultiple(of: 2) ? 1.5 : 4.5 })
        XCTAssertNil(WorkoutPatternDetector.detectAerobicDecoupling(in: samples))
    }

    // MARK: Cadence fade

    func testCadenceFade_StableCadence_ReturnsNil() {
        let samples = makeSamples(cadence: { _ in 90 })
        XCTAssertNil(WorkoutPatternDetector.detectCadenceFade(in: samples))
    }

    func testCadenceFade_AboveMildThreshold_ReturnsMild() {
        // 90 → 86 RPM, drop 4. Boven mild (3), onder moderate (5).
        let samples = makeSamples(cadence: { i in i < 60 ? 90 : (i >= 180 ? 86 : 88) })
        guard let pattern = WorkoutPatternDetector.detectCadenceFade(in: samples) else {
            return XCTFail("Verwacht mild cadence-fade")
        }
        XCTAssertEqual(pattern.kind, .cadenceFade)
        XCTAssertEqual(pattern.severity, .mild)
    }

    func testCadenceFade_AboveSignificantThreshold_ReturnsSignificant() {
        // 90 → 78 RPM, drop 12. Boven significant (10).
        let samples = makeSamples(cadence: { i in i < 60 ? 90 : (i >= 180 ? 78 : 84) })
        guard let pattern = WorkoutPatternDetector.detectCadenceFade(in: samples) else {
            return XCTFail("Verwacht significant cadence-fade")
        }
        XCTAssertEqual(pattern.severity, .significant)
    }

    func testCadenceFade_FiltersZeroCadence() {
        // Laatste kwart: helft van de samples op 0 (gestopt voor stoplicht), helft op 88.
        // Filter moet de zeros negeren — gemiddelde over de niet-zero samples is 88,
        // drop = 90-88 = 2 → onder mild-drempel → nil.
        let samples = makeSamples(cadence: { i in
            if i < 60 { return 90 }
            if i >= 180 { return i.isMultiple(of: 2) ? 0 : 88 }
            return 89
        })
        XCTAssertNil(WorkoutPatternDetector.detectCadenceFade(in: samples),
                     "Zero-cadence samples (stops) mogen het kwartiel-gemiddelde niet omlaag trekken")
    }

    // MARK: HR recovery

    func testHRRecovery_GoodRecovery_ReturnsNil() {
        // Piek 180 BPM, daalt naar 150 in 60s = 30 BPM drop. Boven `hrRecoveryGood` (25),
        // dus niet gerapporteerd.
        let samples = makeSamples(count: 240, heartRate: { i in
            if i == 60 { return 180 }
            if i > 60 && i <= 72 {
                let elapsed = Double(i - 60) * 5.0 // seconden
                return 180 - (30 * elapsed / 60.0) // lineair naar 150
            }
            if i > 72 { return 150 }
            return 140
        })
        XCTAssertNil(WorkoutPatternDetector.detectHeartRateRecovery(in: samples))
    }

    func testHRRecovery_PoorRecovery_ReturnsSignificant() {
        // Piek 180 BPM, daalt slechts 10 BPM in 60s. Onder moderate-drempel (15) → significant.
        let samples = makeSamples(count: 240, heartRate: { i in
            if i == 60 { return 180 }
            if i > 60 && i <= 72 {
                let elapsed = Double(i - 60) * 5.0
                return 180 - (10 * elapsed / 60.0)
            }
            if i > 72 { return 170 }
            return 140
        })
        guard let pattern = WorkoutPatternDetector.detectHeartRateRecovery(in: samples) else {
            return XCTFail("Verwacht poor-recovery patroon")
        }
        XCTAssertEqual(pattern.kind, .heartRateRecovery)
        XCTAssertEqual(pattern.severity, .significant)
    }

    func testHRRecovery_PeakAtEnd_ReturnsNil() {
        // Piek bij laatste sample — geen 60s recovery-window.
        let samples = makeSamples(count: 240, heartRate: { i in i == 239 ? 180 : 140 })
        XCTAssertNil(WorkoutPatternDetector.detectHeartRateRecovery(in: samples))
    }

    // MARK: detectAll aggregation

    func testDetectAll_StableWorkout_ReturnsEmpty() {
        let samples = makeSamples(heartRate: { _ in 150 },
                                  power: { _ in 200 },
                                  cadence: { _ in 90 })
        XCTAssertTrue(WorkoutPatternDetector.detectAll(in: samples).isEmpty)
    }

    func testDetectAll_MultiplePatterns_ReturnsAllInExpectedOrder() {
        // Workout met cardiac drift + cadence fade tegelijk.
        // HR 145 → 158 (~9% drift = significant cardiac drift)
        // Cadence 90 → 78 (drop 12 = significant cadence fade)
        let samples = makeSamples(
            heartRate: { i in i < 120 ? 145 : 158 },
            cadence: { i in i < 60 ? 90 : (i >= 180 ? 78 : 84) }
        )
        let patterns = WorkoutPatternDetector.detectAll(in: samples)
        XCTAssertEqual(patterns.count, 2,
                       "Verwacht cardiac drift + cadence fade — kreeg \(patterns.map(\.kind))")
        // Volgorde matcht de implementatie: decoupling → drift → cadence → recovery
        XCTAssertEqual(patterns[0].kind, .cardiacDrift)
        XCTAssertEqual(patterns[1].kind, .cadenceFade)
    }
}
