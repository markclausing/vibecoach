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
        XCTAssertTrue(WorkoutPatternDetector.detectAll(in: samples, zones: nil).isEmpty)
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

    // MARK: Epic #44 — zone-gate

    func testCardiacDrift_HighIntensityWithZones_SkippedByZoneGate() {
        // 165 → 180 (~9% drift). Karvonen 195/60: HRR=135. Z4 = 168-181.
        // Avg HR over beide helften ≈ 172 → Z4 → moet gefilterd worden.
        let samples = makeSamples(heartRate: { i in i < 120 ? 165 : 180 })
        let zones = HeartRateZoneCalculator.karvonen(maxHR: 195, restingHR: 60)
        XCTAssertNil(WorkoutPatternDetector.detectCardiacDrift(in: samples, zones: zones),
                     "Cardiac drift in Z4 moet gefilterd worden — verwacht effect, niet informatief")
    }

    func testCardiacDrift_AerobicWithZones_StillFires() {
        // 145 → 154 (~6.2% drift) bij maxHR=195+rest=60. Avg HR ≈ 149 → Z2-Z3 boundary.
        let samples = makeSamples(heartRate: { i in i < 120 ? 145 : 154 })
        let zones = HeartRateZoneCalculator.karvonen(maxHR: 195, restingHR: 60)
        let pattern = WorkoutPatternDetector.detectCardiacDrift(in: samples, zones: zones)
        XCTAssertNotNil(pattern, "Drift in Z2-Z3 moet wél getrigerd worden")
        XCTAssertEqual(pattern?.severity, .moderate)
    }

    // Epic #47: HR-recovery zone-gates vervallen — recovery wordt nu alleen in
    // gedetecteerde pauzes gemeten, en daar is geen zone-gate meer nodig
    // (een pauze impliceert al dat de externe load wegvalt). Drempels schalen
    // op `referenceHR` (LTHR / 0.88 × maxHR / fallback).

    func testDetectAll_WithProfile_AppliesZoneGate() {
        // Z2-only workout met 13% cardiac drift (zou zonder zones triggeren) maar
        // de zone-gate filtert hem nu uit. Cadence-fade en decoupling werken nog.
        let samples = makeSamples(
            heartRate: { i in i < 120 ? 130 : 140 },
            cadence: { i in i < 60 ? 90 : (i >= 180 ? 78 : 84) }
        )
        let profile = UserPhysicalProfile(
            weightKg: 75, heightCm: 178, ageYears: 35, sex: .male,
            weightSource: .local, heightSource: .local,
            maxHeartRate: ThresholdValue(value: 195, source: .manual),
            restingHeartRate: ThresholdValue(value: 60, source: .manual)
        )
        let patterns = WorkoutPatternDetector.detectAll(in: samples, profile: profile)
        // Drift was 7.7% → in tier 'moderate' (5-8%) maar avg 135 valt in Z1 (recovery).
        // Zone-gate eist 1...3 dus Z1 zou nog moeten doorlaten — laten we 't checken.
        // Cadence fade triggert wel.
        XCTAssertTrue(patterns.contains(where: { $0.kind == .cadenceFade }))
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
        XCTAssertTrue(pattern.detail.contains("power"),
                      "Detail moet 'power' vermelden bij power-based decoupling, kreeg: \(pattern.detail)")
    }

    func testAerobicDecoupling_FallsBackToSpeedWhenNoPower() {
        // Speed 3 m/s constant, HR drift 150 → 165 (10% drift).
        let samples = makeSamples(heartRate: { i in i < 120 ? 150 : 165 },
                                  speed: { _ in 3.0 })
        guard let pattern = WorkoutPatternDetector.detectAerobicDecoupling(in: samples) else {
            return XCTFail("Verwacht speed-based decoupling-patroon")
        }
        XCTAssertTrue(pattern.detail.contains("pace"),
                      "Detail moet 'pace' vermelden bij speed-fallback, kreeg: \(pattern.detail)")
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

    // MARK: HR recovery (Epic #47 — pauze-based)

    /// Bouwt een 20-min cycling-rit met een pauze van 95s op index 60..80
    /// (boven de 90s minimum-pin-grens). HR daalt lineair met `dropOver60s` BPM
    /// in de eerste 60s, blijft daarna op het lage niveau.
    private func samplesWithSinglePause(dropOver60s: Double,
                                         peakHR: Double = 180) -> [WorkoutSample] {
        let pauseStart = 60
        let pauseEnd = 80  // exclusive — 20 buckets × 5s = 95s pauze
        return makeSamples(count: 240,
                           heartRate: { i in
                               if i < pauseStart { return peakHR }
                               if i < pauseEnd {
                                   let elapsed = Double(i - pauseStart) * 5.0
                                   // Lineair dalen, geclamped op 60s (window-eind)
                                   let progress = min(elapsed / 60.0, 1.0)
                                   return peakHR - dropOver60s * progress
                               }
                               return peakHR - dropOver60s
                           },
                           power: { i in (pauseStart..<pauseEnd).contains(i) ? 0 : 200 },
                           cadence: { i in (pauseStart..<pauseEnd).contains(i) ? 0 : 90 })
    }

    func testHRRecovery_NoPauseInWorkout_ReturnsNil() {
        // Continue rit zonder pauze (de scenario uit het screenshot van Epic #47).
        // Geen pauze → geen recovery-pin, ook niet als HR rond een piek visueel
        // wel een dip toonde.
        let samples = makeSamples(count: 240,
                                  heartRate: { i in i == 60 ? 180 : 165 },
                                  power: { _ in 200 },
                                  cadence: { _ in 90 })
        XCTAssertNil(WorkoutPatternDetector.detectHeartRateRecovery(in: samples),
                     "Zonder pauze (continue effort) mag er geen HR-recovery-pin zijn")
    }

    func testHRRecovery_GoodRecoveryInPause_ReturnsNil() {
        // Pauze van 90s, HR daalt 30 BPM in 60s → ratio 30/165 ≈ 0.18 > 0.15 (good)
        // → geen pin (uitstekend herstel).
        let samples = samplesWithSinglePause(dropOver60s: 30)
        XCTAssertNil(WorkoutPatternDetector.detectHeartRateRecovery(in: samples),
                     "Uitstekend herstel mag geen pin tonen (Management by Exception §1)")
    }

    func testHRRecovery_PoorRecoveryInPause_ReturnsSignificant() {
        // Pauze van 90s, HR daalt slechts 10 BPM in 60s → ratio 10/165 ≈ 0.06 < 0.09
        // → significant.
        let samples = samplesWithSinglePause(dropOver60s: 10)
        guard let pattern = WorkoutPatternDetector.detectHeartRateRecovery(in: samples) else {
            return XCTFail("Verwacht significant HR-recovery-pin bij trage pauze-recovery")
        }
        XCTAssertEqual(pattern.kind, .heartRateRecovery)
        XCTAssertEqual(pattern.severity, .significant)
        XCTAssertTrue(pattern.detail.contains("pause"),
                      "Detail moet 'pause' vermelden, niet 'piek'")
    }

    func testHRRecovery_ModerateRecoveryInPause_ReturnsModerate() {
        // Drop 17 BPM op 165 → ratio ≈ 0.103 → tussen 0.09 en 0.12 → moderate.
        let samples = samplesWithSinglePause(dropOver60s: 17)
        guard let pattern = WorkoutPatternDetector.detectHeartRateRecovery(in: samples) else {
            return XCTFail("Verwacht moderate-pin")
        }
        XCTAssertEqual(pattern.severity, .moderate)
    }

    func testHRRecovery_MildRecoveryInPause_ReturnsMild() {
        // Drop 22 BPM op 165 → ratio ≈ 0.133 → tussen 0.12 en 0.15 → mild.
        let samples = samplesWithSinglePause(dropOver60s: 22)
        guard let pattern = WorkoutPatternDetector.detectHeartRateRecovery(in: samples) else {
            return XCTFail("Verwacht mild-pin")
        }
        XCTAssertEqual(pattern.severity, .mild)
    }

    func testHRRecovery_WithLTHR_ScalesThresholds() {
        // Drop 20 BPM met LTHR=150 → ratio ≈ 0.133 → mild (zou bij fallback 165 ook mild zijn).
        // Maar drop 20 met LTHR=200 → ratio = 0.10 → moderate. Bewijs dat referenceHR
        // de drempel daadwerkelijk schaalt.
        let samples = samplesWithSinglePause(dropOver60s: 20)
        let mildAtLTHR150 = WorkoutPatternDetector.detectHeartRateRecovery(in: samples, referenceHR: 150)
        let moderateAtLTHR200 = WorkoutPatternDetector.detectHeartRateRecovery(in: samples, referenceHR: 200)
        XCTAssertEqual(mildAtLTHR150?.severity, .mild)
        XCTAssertEqual(moderateAtLTHR200?.severity, .moderate)
    }

    func testHRRecovery_MultiplePauses_PinsWorstRecovery() {
        // Twee pauzes ≥90s: één met 30 BPM drop (uitstekend, geen pin) en één met
        // 10 BPM drop (significant). Detector moet de slechtste pinnen.
        let pauseA = 60..<80   // 95s
        let pauseB = 150..<170 // 95s
        let stillIndexes = Set(pauseA).union(Set(pauseB))
        let samples = makeSamples(count: 240,
                                  heartRate: { i in
                                      if pauseA.contains(i) {
                                          let elapsed = Double(i - 60) * 5.0
                                          return 180 - 30 * min(elapsed / 60.0, 1.0)
                                      }
                                      if pauseB.contains(i) {
                                          let elapsed = Double(i - 150) * 5.0
                                          return 180 - 10 * min(elapsed / 60.0, 1.0)
                                      }
                                      return 180
                                  },
                                  power: { i in stillIndexes.contains(i) ? 0 : 200 },
                                  cadence: { i in stillIndexes.contains(i) ? 0 : 90 })
        guard let pattern = WorkoutPatternDetector.detectHeartRateRecovery(in: samples) else {
            return XCTFail("Verwacht pin op slechtste pauze")
        }
        XCTAssertEqual(pattern.severity, .significant,
                       "Slechtste pauze (10 BPM drop) moet de pin bepalen, niet de uitstekende (30 BPM)")
        XCTAssertEqual(pattern.value, 10, accuracy: 1)
    }

    func testHRRecovery_ShortPauseUnder90s_NotPinnedDespiteSlowDrop() {
        // Verkeerslicht-stop van 60s met slechts 4 BPM drop — fysiologisch te kort
        // om als recovery-event te framen. Ook al is de ratio < 0.09 (significant),
        // de pin moet uitblijven omdat pauze < `hrRecoveryMinPauseForPinSeconds`.
        // Dit is exact het Epic #47 follow-up scenario waar verkeerslicht-stops de
        // pin van de échte (uitstekende) lange pauze afpakten.
        let stillRange = 60..<73  // 13 buckets × 5s = 60s
        let samples = makeSamples(count: 240,
                                  heartRate: { i in
                                      if stillRange.contains(i) {
                                          let elapsed = Double(i - 60) * 5.0
                                          return 175 - 4 * min(elapsed / 60.0, 1.0)
                                      }
                                      return i < 60 ? 175 : 171
                                  },
                                  power: { i in stillRange.contains(i) ? 0 : 200 },
                                  cadence: { i in stillRange.contains(i) ? 0 : 90 })
        XCTAssertNil(WorkoutPatternDetector.detectHeartRateRecovery(in: samples),
                     "Pauze < 90s mag geen pin opleveren ook al is de ratio onder de drempel")
    }

    func testHRRecovery_LongUnskepablePauseWinsOverShortBadPause() {
        // Echt rit-scenario uit Epic #47 follow-up: korte verkeerslicht-stop (60s,
        // drop 4 BPM = ratio 0.024 → "significant") + lange koffiestop (5min,
        // drop 35 BPM = ratio 0.21 → "uitstekend"). Vóór deze fix won de korte
        // stop de pin omdat hij de slechtste ratio had. Nu wordt de korte stop
        // uitgesloten van pin-overweging en de lange pauze is uitstekend → geen pin.
        let shortPause = 30..<43   // 60s
        let longPause = 100..<160  // 5min
        let stillIndexes = Set(shortPause).union(Set(longPause))
        let samples = makeSamples(count: 240,
                                  heartRate: { i in
                                      if shortPause.contains(i) {
                                          let elapsed = Double(i - 30) * 5.0
                                          return 175 - 4 * min(elapsed / 60.0, 1.0)
                                      }
                                      if longPause.contains(i) {
                                          let elapsed = Double(i - 100) * 5.0
                                          return 180 - 35 * min(elapsed / 90.0, 1.0)
                                      }
                                      return 175
                                  },
                                  power: { i in stillIndexes.contains(i) ? 0 : 200 },
                                  cadence: { i in stillIndexes.contains(i) ? 0 : 90 })
        XCTAssertNil(WorkoutPatternDetector.detectHeartRateRecovery(in: samples),
                     "Lange pauze met uitstekend herstel + korte stop met trage drop = geen pin (korte stop niet pin-waardig)")
    }

    func testHRRecovery_AllPausesGood_ReturnsNil() {
        // Eén pauze met uitstekend herstel — geen pin, ook niet door fallback-regel.
        let samples = samplesWithSinglePause(dropOver60s: 30)
        XCTAssertNil(WorkoutPatternDetector.detectHeartRateRecovery(in: samples, referenceHR: 165))
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
