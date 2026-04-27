import XCTest
@testable import AIFitnessCoach

/// Epic 44 Story 44.2 — `PhysiologicalThresholdEstimator`.
/// Borgt:
///  • Onvoldoende data → nil (geen wilde gokken)
///  • Plausibility-filter (HR < 80 of > 220 weggegooid)
///  • Mediaan voor rust-HR (robuust tegen outliers)
///  • 95e-percentiel voor max-HR per workout (filter spikes)
///  • Rolling 30-window voor LTHR
final class PhysiologicalThresholdEstimatorTests: XCTestCase {

    private let baseDate = Date(timeIntervalSince1970: 1_745_625_600)

    private func makeWorkout(durationMinutes: Double,
                             heartRates: [Double]) -> PhysiologicalThresholdEstimator.WorkoutHRSample {
        PhysiologicalThresholdEstimator.WorkoutHRSample(
            startDate: baseDate,
            durationSeconds: durationMinutes * 60,
            heartRates: heartRates
        )
    }

    // MARK: Max HR

    func testEstimateMaxHR_NoWorkouts_ReturnsNil() {
        XCTAssertNil(PhysiologicalThresholdEstimator.estimateMaxHeartRate(workouts: []))
    }

    func testEstimateMaxHR_TooShortWorkout_Skipped() {
        // 10 min onder de 20-min drempel → genegeerd.
        let workout = makeWorkout(durationMinutes: 10, heartRates: Array(repeating: 200, count: 100))
        XCTAssertNil(PhysiologicalThresholdEstimator.estimateMaxHeartRate(workouts: [workout]))
    }

    func testEstimateMaxHR_TooFewSamples_Skipped() {
        // 25 min duur maar slechts 10 samples — niet betrouwbaar.
        let workout = makeWorkout(durationMinutes: 25, heartRates: Array(repeating: 195, count: 10))
        XCTAssertNil(PhysiologicalThresholdEstimator.estimateMaxHeartRate(workouts: [workout]))
    }

    func testEstimateMaxHR_StableHardWorkout_ReturnsTopPercentile() {
        // 30-min workout met 200 samples op stabiel 180 BPM.
        let workout = makeWorkout(durationMinutes: 30, heartRates: Array(repeating: 180, count: 200))
        XCTAssertEqual(PhysiologicalThresholdEstimator.estimateMaxHeartRate(workouts: [workout]), 180)
    }

    func testEstimateMaxHR_FiltersImplausibleSpikes() {
        // 200 samples op 180 BPM, plus 5 sensor-spikes naar 250 BPM. Plausibility-filter
        // gooit de spikes weg, max blijft 180.
        var rates = Array(repeating: 180.0, count: 200)
        rates.append(contentsOf: [250, 250, 250, 250, 250])
        let workout = makeWorkout(durationMinutes: 30, heartRates: rates)
        XCTAssertEqual(PhysiologicalThresholdEstimator.estimateMaxHeartRate(workouts: [workout]), 180,
                       "Spikes boven 220 BPM zijn sensorfouten — niet meenemen")
    }

    func testEstimateMaxHR_TakesHighestAcrossMultipleWorkouts() {
        // Drie workouts: één met piek 175, één met piek 188, één met piek 192.
        // Hoogste over alles wint.
        let easy   = makeWorkout(durationMinutes: 30, heartRates: Array(repeating: 175.0, count: 200))
        let tempo  = makeWorkout(durationMinutes: 30, heartRates: Array(repeating: 188.0, count: 200))
        let intervalsTop = makeWorkout(durationMinutes: 30,
                                       heartRates: Array(repeating: 192.0, count: 200))
        let result = PhysiologicalThresholdEstimator.estimateMaxHeartRate(
            workouts: [easy, tempo, intervalsTop]
        )
        XCTAssertEqual(result, 192)
    }

    // MARK: Resting HR

    func testEstimateRestingHR_TooFewSamples_ReturnsNil() {
        let samples = Array(repeating: 55.0, count: 10) // onder de 14-drempel
        XCTAssertNil(PhysiologicalThresholdEstimator.estimateRestingHeartRate(samples: samples))
    }

    func testEstimateRestingHR_StableSamples_ReturnsMedian() {
        let samples: [Double] = Array(repeating: 55, count: 14)
        XCTAssertEqual(PhysiologicalThresholdEstimator.estimateRestingHeartRate(samples: samples), 55)
    }

    func testEstimateRestingHR_RobustToSingleOutlier() {
        // 14 dagen op 55 BPM (boven de drempel) + één dag met sensorfout op 120 BPM.
        // De 120 wordt door de plausibility-filter (>100) weggegooid; 14 plausibele
        // samples blijven over → mediaan = 55. Borgt zowel de filter als de mediaan-
        // robustheid in één test.
        var samples = Array(repeating: 55.0, count: 14)
        samples.append(120)
        XCTAssertEqual(PhysiologicalThresholdEstimator.estimateRestingHeartRate(samples: samples), 55,
                       "Mediaan + plausibility-filter moeten samen outliers negeren")
    }

    func testEstimateRestingHR_FiltersImplausibleValues() {
        // Mix: 14 normale samples (55) + zes implausibele (10, 200).
        var samples = Array(repeating: 55.0, count: 14)
        samples.append(contentsOf: [10, 10, 10, 200, 200, 200])
        XCTAssertEqual(PhysiologicalThresholdEstimator.estimateRestingHeartRate(samples: samples), 55)
    }

    // MARK: LTHR

    func testEstimateLTHR_NoWorkouts_ReturnsNil() {
        XCTAssertNil(PhysiologicalThresholdEstimator.estimateLactateThresholdHR(workouts: []))
    }

    func testEstimateLTHR_TooFewSamples_ReturnsNil() {
        // Maar 20 samples → onder de 30-window-drempel.
        let workout = makeWorkout(durationMinutes: 30, heartRates: Array(repeating: 170, count: 20))
        XCTAssertNil(PhysiologicalThresholdEstimator.estimateLactateThresholdHR(workouts: [workout]))
    }

    func testEstimateLTHR_StableHardWorkout_ReturnsRollingAverage() {
        // 60 samples op 170 BPM. Rolling 30-window gemiddelde = 170.
        let workout = makeWorkout(durationMinutes: 30, heartRates: Array(repeating: 170, count: 60))
        XCTAssertEqual(PhysiologicalThresholdEstimator.estimateLactateThresholdHR(workouts: [workout]), 170)
    }

    func testEstimateLTHR_PicksHighestAcrossWorkouts() {
        // Twee workouts: rustige op 140 BPM, zware op 175 BPM. Zware wint.
        let easy = makeWorkout(durationMinutes: 30, heartRates: Array(repeating: 140, count: 60))
        let hard = makeWorkout(durationMinutes: 30, heartRates: Array(repeating: 175, count: 60))
        XCTAssertEqual(
            PhysiologicalThresholdEstimator.estimateLactateThresholdHR(workouts: [easy, hard]),
            175
        )
    }

    func testEstimateLTHR_RollingWindowPicksMostIntense30Min() {
        // 60 samples: eerste 30 op 140 BPM (warm-up), laatste 30 op 175 BPM.
        // Rolling-window detecteert het 175-blok, returnt 175.
        var rates = Array(repeating: 140.0, count: 30)
        rates.append(contentsOf: Array(repeating: 175.0, count: 30))
        let workout = makeWorkout(durationMinutes: 60, heartRates: rates)
        XCTAssertEqual(PhysiologicalThresholdEstimator.estimateLactateThresholdHR(workouts: [workout]), 175)
    }

    // MARK: estimate aggregation

    func testEstimate_CombinesAllThree() {
        let workout = makeWorkout(durationMinutes: 30, heartRates: Array(repeating: 175.0, count: 100))
        let restingSamples = Array(repeating: 55.0, count: 14)
        let result = PhysiologicalThresholdEstimator.estimate(
            workouts: [workout],
            dailyRestingHR: restingSamples
        )
        XCTAssertEqual(result.maxHeartRate, 175)
        XCTAssertEqual(result.restingHeartRate, 55)
        XCTAssertEqual(result.lactateThresholdHR, 175)
    }

    func testEstimate_PartialDataStillReturnsResult() {
        // Geen workouts maar wel rust-HR — alleen rest is gevuld.
        let restingSamples = Array(repeating: 60.0, count: 14)
        let result = PhysiologicalThresholdEstimator.estimate(
            workouts: [],
            dailyRestingHR: restingSamples
        )
        XCTAssertNil(result.maxHeartRate)
        XCTAssertNil(result.lactateThresholdHR)
        XCTAssertEqual(result.restingHeartRate, 60)
    }
}
