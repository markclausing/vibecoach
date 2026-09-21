import XCTest
@testable import AIFitnessCoach

/// Unit tests voor `SessionLoadCalculator` (Epic #74). De kern van de epic: een lange
/// duurtraining op praattempo moet een hoge sessie-load opleveren, ondanks een lage RPE.
/// Die ene eigenschap is wat de coach eerder verkeerd las, dus die is hier het zwaarst getest.
final class SessionLoadCalculatorTests: XCTestCase {

    // MARK: - Kernberekening

    func testLoadIsRpeTimesMinutes() {
        let result = SessionLoadCalculator.calculate(rpe: 5, durationSeconds: 60 * 60)
        XCTAssertEqual(result?.load, 300, "60 min op RPE 5 = 300 AU (Foster sRPE)")
        XCTAssertEqual(result?.durationMinutes, 60)
        XCTAssertEqual(result?.rpe, 5)
    }

    func testDurationRoundsToNearestMinute() {
        // 90 seconden → 2 minuten (afronden, niet afkappen): anders zou een korte
        // inspanning naar 1 minuut collapsen.
        XCTAssertEqual(SessionLoadCalculator.calculate(rpe: 4, durationSeconds: 90)?.durationMinutes, 2)
        // 89 seconden → 1 minuut.
        XCTAssertEqual(SessionLoadCalculator.calculate(rpe: 4, durationSeconds: 89)?.durationMinutes, 1)
    }

    // MARK: - Het scenario dat de epic veroorzaakte

    func testLongEasyRunIsVeryDemandingDespiteLowRpe() {
        // 30 km duurloop, ~3u02, gerapporteerd als "Makkelijk" (RPE 2 in de check-in).
        let result = SessionLoadCalculator.calculate(rpe: 2, durationSeconds: 182 * 60)
        XCTAssertEqual(result?.load, 364)
        XCTAssertEqual(result?.band, .substantial,
                       "Zelfs op RPE 2 tilt 3 uur de sessie ruim boven een 'lichte' dag")
        // En op de realistischere 'Prima te doen' (RPE 5) is het onmiskenbaar zwaar.
        let moderateEffort = SessionLoadCalculator.calculate(rpe: 5, durationSeconds: 182 * 60)
        XCTAssertEqual(moderateEffort?.load, 910)
        XCTAssertEqual(moderateEffort?.band, .veryDemanding)
        XCTAssertTrue(moderateEffort?.band.requiresRecovery == true,
                      "Dit is precies de sessie die herstel vraagt ondanks een niet-maximale RPE")
    }

    func testShortHardSessionStaysBelowLongEasySession() {
        // 30 min all-out (RPE 9) = 270 AU; 2 uur rustig (RPE 3) = 360 AU.
        // De lange rustige sessie hoort de zwaardere van de twee te zijn — dat is het
        // hele punt van duur-weging.
        let shortHard = SessionLoadCalculator.calculate(rpe: 9, durationSeconds: 30 * 60)
        let longEasy = SessionLoadCalculator.calculate(rpe: 3, durationSeconds: 120 * 60)
        XCTAssertEqual(shortHard?.load, 270)
        XCTAssertEqual(longEasy?.load, 360)
        XCTAssertGreaterThan(longEasy!.load, shortHard!.load)
    }

    // MARK: - Banden

    func testBandBoundaries() {
        XCTAssertEqual(SessionLoadCalculator.band(for: 0), .light)
        XCTAssertEqual(SessionLoadCalculator.band(for: 149), .light)
        XCTAssertEqual(SessionLoadCalculator.band(for: 150), .moderate)
        XCTAssertEqual(SessionLoadCalculator.band(for: 299), .moderate)
        XCTAssertEqual(SessionLoadCalculator.band(for: 300), .substantial)
        XCTAssertEqual(SessionLoadCalculator.band(for: 499), .substantial)
        XCTAssertEqual(SessionLoadCalculator.band(for: 500), .demanding)
        XCTAssertEqual(SessionLoadCalculator.band(for: 699), .demanding)
        XCTAssertEqual(SessionLoadCalculator.band(for: 700), .veryDemanding)
        XCTAssertEqual(SessionLoadCalculator.band(for: 5_000), .veryDemanding)
    }

    func testOnlyDemandingBandsRequireRecovery() {
        XCTAssertFalse(SessionLoadCalculator.Band.light.requiresRecovery)
        XCTAssertFalse(SessionLoadCalculator.Band.moderate.requiresRecovery)
        XCTAssertFalse(SessionLoadCalculator.Band.substantial.requiresRecovery)
        XCTAssertTrue(SessionLoadCalculator.Band.demanding.requiresRecovery)
        XCTAssertTrue(SessionLoadCalculator.Band.veryDemanding.requiresRecovery)
    }

    func testEveryBandHasAPromptLabel() {
        for band in SessionLoadCalculator.Band.allCases {
            XCTAssertFalse(band.promptLabel.isEmpty, "Band \(band) mist een prompt-label")
        }
    }

    // MARK: - Ongeldige invoer

    func testNilWhenRpeMissing() {
        XCTAssertNil(SessionLoadCalculator.calculate(rpe: nil, durationSeconds: 3_600))
    }

    func testNilForIgnoredSentinel() {
        // WorkoutCheckinConfig.ignoredRPESentinel (0) betekent 'geen training' —
        // dat mag nooit als een sessie-load van 0 AU doorgaan.
        XCTAssertNil(SessionLoadCalculator.calculate(rpe: WorkoutCheckinConfig.ignoredRPESentinel,
                                                     durationSeconds: 3_600))
    }

    func testNilForOutOfScaleRpe() {
        XCTAssertNil(SessionLoadCalculator.calculate(rpe: 11, durationSeconds: 3_600))
        XCTAssertNil(SessionLoadCalculator.calculate(rpe: -1, durationSeconds: 3_600))
    }

    func testNilWhenDurationMissingOrNonPositive() {
        XCTAssertNil(SessionLoadCalculator.calculate(rpe: 5, durationSeconds: nil))
        XCTAssertNil(SessionLoadCalculator.calculate(rpe: 5, durationSeconds: 0))
        XCTAssertNil(SessionLoadCalculator.calculate(rpe: 5, durationSeconds: -60))
        // Onder de halve minuut rondt de duur naar 0 → geen betekenisvolle load.
        XCTAssertNil(SessionLoadCalculator.calculate(rpe: 5, durationSeconds: 20))
    }
}
