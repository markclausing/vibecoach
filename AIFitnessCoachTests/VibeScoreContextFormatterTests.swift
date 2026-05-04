import XCTest
@testable import AIFitnessCoach

final class VibeScoreContextFormatterTests: XCTestCase {

    // MARK: - Nil readiness

    func test_format_nilReadiness_keepsExistingSentinel() {
        let result = VibeScoreContextFormatter.format(
            readiness: nil,
            previousValue: VibeScoreContextFormatter.noVibeDataSentinel
        )
        XCTAssertEqual(result, VibeScoreContextFormatter.noVibeDataSentinel,
                       "Bestaande sentinel mag niet weggegooid worden bij nil-readiness.")
    }

    func test_format_nilReadiness_clearsNonSentinel() {
        let result = VibeScoreContextFormatter.format(
            readiness: nil,
            previousValue: "Vibe Score vandaag: 75/100..."
        )
        XCTAssertEqual(result, "")
    }

    // MARK: - Score-band labels

    func test_format_highScore_labelsOptimaalHersteld() {
        let r = DailyReadiness(date: .init(), sleepHours: 8.0, hrv: 60.0, readinessScore: 85)
        let result = VibeScoreContextFormatter.format(readiness: r, previousValue: "")
        XCTAssertTrue(result.contains("Optimaal Hersteld"), "Score ≥ 80 hoort 'Optimaal Hersteld' te zijn.")
        XCTAssertTrue(result.contains("85/100"))
    }

    func test_format_midScore_labelsMatigHersteld() {
        let r = DailyReadiness(date: .init(), sleepHours: 7.0, hrv: 50.0, readinessScore: 65)
        let result = VibeScoreContextFormatter.format(readiness: r, previousValue: "")
        XCTAssertTrue(result.contains("Matig Hersteld"))
    }

    func test_format_lowScore_labelsSlechtHersteld() {
        let r = DailyReadiness(date: .init(), sleepHours: 5.0, hrv: 30.0, readinessScore: 40)
        let result = VibeScoreContextFormatter.format(readiness: r, previousValue: "")
        XCTAssertTrue(result.contains("Slecht Hersteld"))
        XCTAssertTrue(result.contains("Rust prioriteit"))
    }

    // MARK: - Sleep formatting

    func test_format_sleepHoursAndMinutes() {
        let r = DailyReadiness(date: .init(), sleepHours: 7.5, hrv: 55.0, readinessScore: 75)
        let result = VibeScoreContextFormatter.format(readiness: r, previousValue: "")
        XCTAssertTrue(result.contains("7u 30m"), "7.5 uur slaap → 7u 30m. Kreeg: \(result)")
    }

    // MARK: - Sleep stages

    func test_format_withGoodDeepSleep_includesQualityLabel() {
        let r = DailyReadiness(date: .init(), sleepHours: 8.0, hrv: 60.0, readinessScore: 85,
                               deepSleepMinutes: 90, remSleepMinutes: 110, coreSleepMinutes: 200)
        let result = VibeScoreContextFormatter.format(readiness: r, previousValue: "")
        // 90 / 400 = 22.5% → "Uitstekend"
        XCTAssertTrue(result.contains("Uitstekend"))
        XCTAssertFalse(result.contains("INSTRUCTIE:"), "Bij goede slaap geen extra instructie.")
    }

    func test_format_withPoorDeepSleep_addsCoachInstruction() {
        let r = DailyReadiness(date: .init(), sleepHours: 7.0, hrv: 55.0, readinessScore: 70,
                               deepSleepMinutes: 30, remSleepMinutes: 100, coreSleepMinutes: 270)
        // 30 / 400 = 7.5% → "Onvoldoende" + INSTRUCTIE
        let result = VibeScoreContextFormatter.format(readiness: r, previousValue: "")
        XCTAssertTrue(result.contains("Onvoldoende"))
        XCTAssertTrue(result.contains("INSTRUCTIE:"))
    }

    func test_format_withoutStageData_omitsQualityNote() {
        let r = DailyReadiness(date: .init(), sleepHours: 7.0, hrv: 50.0, readinessScore: 70)
        let result = VibeScoreContextFormatter.format(readiness: r, previousValue: "")
        XCTAssertFalse(result.contains("Slaapfases:"), "Zonder stage-data geen slaapfase-blok.")
    }
}
