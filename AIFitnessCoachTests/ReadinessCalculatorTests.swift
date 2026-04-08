import XCTest
@testable import AIFitnessCoach

/// Unit tests voor ReadinessCalculator (Epic 14).
///
/// ReadinessCalculator is een pure struct zonder side-effects of dependencies —
/// geen mocks nodig. Elke test verifieert één grenswaarde of combinatie.
///
/// Algoritme ter referentie:
///   sleepScore = clamp((slaapUren - 5) / 3, 0...1) × 100
///   lowerBound = baseline × 0.80
///   hrvScore   = 100 als hrv ≥ baseline, 0 als hrv ≤ lowerBound, lineair daartussen
///   vibeScore  = round((sleepScore + hrvScore) / 2)
final class ReadinessCalculatorTests: XCTestCase {

    // MARK: - Optimale herstel (hoge score verwacht)

    /// 8+ uur slaap + HRV op of boven baseline → beide deelscores zijn 100 → eindscore 100.
    func testCalculate_OptimalSleepAndHRV_Returns100() {
        let score = ReadinessCalculator.calculate(sleepHours: 8.0, hrv: 60.0, hrvBaseline: 60.0)
        XCTAssertEqual(score, 100, "8u slaap + HRV op baseline moet score 100 opleveren.")
    }

    /// HRV bóven de baseline telt ook als 100 (geen bonus boven 100).
    func testCalculate_HRVAboveBaseline_CapsAt100() {
        let score = ReadinessCalculator.calculate(sleepHours: 9.0, hrv: 80.0, hrvBaseline: 60.0)
        XCTAssertEqual(score, 100, "Excessief slaap + HRV boven baseline mag nooit boven 100 komen.")
    }

    // MARK: - Slechte herstel (lage score verwacht)

    /// <5 uur slaap + HRV meer dan 20% onder baseline → beide deelscores zijn 0 → eindscore 0.
    func testCalculate_PoorSleepAndLowHRV_ReturnsNearZero() {
        // baseline = 60, lowerBound = 48. hrv = 40 (ruim onder lowerBound).
        let score = ReadinessCalculator.calculate(sleepHours: 4.0, hrv: 40.0, hrvBaseline: 60.0)
        XCTAssertEqual(score, 0, "Minder dan 5u slaap + HRV >20% onder baseline moet score 0 opleveren.")
    }

    /// HRV exact op de ondergrens (80% van baseline) → hrvScore = 0. Slaap ook slecht → 0.
    func testCalculate_HRVExactlyAtLowerBound_HRVScoreIsZero() {
        // baseline = 50, lowerBound = 40. hrv = 40.
        let score = ReadinessCalculator.calculate(sleepHours: 4.5, hrv: 40.0, hrvBaseline: 50.0)
        XCTAssertEqual(score, 0, "HRV exact op de 80%-ondergrens + te weinig slaap → score 0.")
    }

    // MARK: - Grenzen slaapscore

    /// Precies 5 uur slaap → sleepScore = 0. HRV perfect → eindscore = 50.
    func testCalculate_ExactlyFiveHoursSleep_SleepScoreIsZero() {
        let score = ReadinessCalculator.calculate(sleepHours: 5.0, hrv: 60.0, hrvBaseline: 60.0)
        XCTAssertEqual(score, 50, "5u slaap (grens) + perfecte HRV → (0 + 100) / 2 = 50.")
    }

    /// Precies 8 uur slaap → sleepScore = 100. HRV perfect → eindscore = 100.
    func testCalculate_ExactlyEightHoursSleep_SleepScoreIsFull() {
        let score = ReadinessCalculator.calculate(sleepHours: 8.0, hrv: 55.0, hrvBaseline: 55.0)
        XCTAssertEqual(score, 100, "8u slaap (bovenkant) + perfecte HRV → (100 + 100) / 2 = 100.")
    }

    /// 6,5 uur slaap = midden van 5–8 → sleepScore ≈ 50. HRV op baseline → eindscore ≈ 75.
    func testCalculate_MidpointSleep_ProducesExpectedScore() {
        // sleepScore = (6.5 - 5) / 3 * 100 = 50. hrvScore = 100. final = 75.
        let score = ReadinessCalculator.calculate(sleepHours: 6.5, hrv: 60.0, hrvBaseline: 60.0)
        XCTAssertEqual(score, 75, "6,5u slaap + HRV op baseline → verwacht 75.")
    }

    // MARK: - Grenzen HRV-score

    /// HRV precies halverwege lowerBound en baseline → hrvScore = 50.
    /// baseline = 60, lowerBound = 48, hrv = 54 (midden). sleepScore = 100. final = 75.
    func testCalculate_HRVAtMidpoint_ProducesLinearScore() {
        let score = ReadinessCalculator.calculate(sleepHours: 8.0, hrv: 54.0, hrvBaseline: 60.0)
        XCTAssertEqual(score, 75, "HRV halverwege lowerBound en baseline + perfecte slaap → 75.")
    }

    // MARK: - Score altijd binnen 0–100

    /// Extreme inputs mogen nooit buiten het 0–100 bereik vallen.
    func testCalculate_ExtremeInputs_NeverExceedsBounds() {
        let tooLow  = ReadinessCalculator.calculate(sleepHours: 0.0,  hrv: 0.0,    hrvBaseline: 100.0)
        let tooHigh = ReadinessCalculator.calculate(sleepHours: 24.0, hrv: 1000.0, hrvBaseline: 10.0)
        XCTAssertGreaterThanOrEqual(tooLow,  0,   "Score mag nooit onder 0 komen.")
        XCTAssertLessThanOrEqual(tooHigh,    100, "Score mag nooit boven 100 komen.")
    }
}
