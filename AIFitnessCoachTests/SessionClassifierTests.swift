import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Unit tests voor `SessionClassifier`. Pure-Swift — geen ModelContainer nodig voor de
/// classifier zelf, maar `WorkoutSample` is `@Model` dus we maken een in-memory container
/// voor de test-fixtures.
@MainActor
final class SessionClassifierTests: XCTestCase {

    private var container: ModelContainer!
    private let classifier = SessionClassifier(maxHeartRate: 190)
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: WorkoutSample.self, configurations: config)
    }

    override func tearDownWithError() throws {
        container = nil
    }

    // MARK: Helpers

    private func sample(at offset: TimeInterval, hr: Double) -> WorkoutSample {
        WorkoutSample(workoutUUID: UUID(),
                      timestamp: baseDate.addingTimeInterval(offset),
                      heartRate: hr)
    }

    /// Bouwt N samples met een vaste HR-percentage van HRmax (190 bpm).
    private func samples(count: Int, hrPercent: Double) -> [WorkoutSample] {
        (0..<count).map { sample(at: TimeInterval($0 * 5), hr: 190 * hrPercent) }
    }

    // MARK: Keyword-classification

    func testKeywordsRecognizeVo2MaxIntervalSessions() {
        XCTAssertEqual(classifier.classifyByKeywords(title: "VO2 intervallen 5x4 min"), .vo2Max)
        XCTAssertEqual(classifier.classifyByKeywords(title: "8x800m intervals"), .vo2Max)
        XCTAssertEqual(classifier.classifyByKeywords(title: "VMAX work"), .vo2Max)
    }

    func testKeywordsRecognizeThresholdSessions() {
        XCTAssertEqual(classifier.classifyByKeywords(title: "FTP test"), .threshold)
        XCTAssertEqual(classifier.classifyByKeywords(title: "Drempel-rit 2x20"), .threshold)
        XCTAssertEqual(classifier.classifyByKeywords(title: "Sweet spot werkje"), .threshold)
    }

    func testKeywordsRecognizeRecovery() {
        XCTAssertEqual(classifier.classifyByKeywords(title: "Recovery run"), .recovery)
        XCTAssertEqual(classifier.classifyByKeywords(title: "Easy spin"), .recovery)
        XCTAssertEqual(classifier.classifyByKeywords(title: "Actief herstel ochtend"), .recovery)
    }

    func testKeywordsRecognizeSocialOverridesIntensity() {
        // 'Social' moet altijd winnen, ook als andere keywords erbij staan.
        XCTAssertEqual(classifier.classifyByKeywords(title: "Sociale rit met de club"), .social)
        XCTAssertEqual(classifier.classifyByKeywords(title: "Group ride zondag"), .social)
    }

    func testKeywordsRecognizeRace() {
        // Bewust expliciete race-keywords — 'Marathon Rotterdam' alleen is ambigu
        // (kan training-sessie zijn met marathon-context). Strava-naming voor races
        // bevat doorgaans 'race', 'wedstrijd' of 'criterium'.
        XCTAssertEqual(classifier.classifyByKeywords(title: "Race rotterdam halve"), .race)
        XCTAssertEqual(classifier.classifyByKeywords(title: "Wedstrijd ochtend"), .race)
        XCTAssertEqual(classifier.classifyByKeywords(title: "Criterium Arnhem"), .race)
    }

    func testKeywordsReturnNilOnNeutralTitle() {
        XCTAssertNil(classifier.classifyByKeywords(title: "Cycling"))
        XCTAssertNil(classifier.classifyByKeywords(title: "Workout"))
    }

    // MARK: Zone-distribution

    func testZoneDistributionDetectsVo2MaxWhenZ5Dominant() {
        // 30% in Z5 (95% HRmax) + 70% in Z2 (recovery tussen intervallen)
        var samples = self.samples(count: 30, hrPercent: 0.95)
        samples.append(contentsOf: self.samples(count: 70, hrPercent: 0.65))
        let result = classifier.classifyByZoneDistribution(samples: samples)
        XCTAssertEqual(result, .vo2Max,
                       "30% Z5 met de rest in Z2 hoort vo2Max te zijn — Z5-stimulus domineert het effect")
    }

    func testZoneDistributionDetectsThresholdWhenZ4Dominant() {
        // 50% in Z4 (85% HRmax)
        var samples = self.samples(count: 50, hrPercent: 0.85)
        samples.append(contentsOf: self.samples(count: 50, hrPercent: 0.70))
        let result = classifier.classifyByZoneDistribution(samples: samples)
        XCTAssertEqual(result, .threshold)
    }

    func testZoneDistributionDetectsEnduranceWhenLowZones() {
        // 80% in Z2 (65% HRmax) — typische lange duurrit
        let samples = self.samples(count: 100, hrPercent: 0.65)
        let result = classifier.classifyByZoneDistribution(samples: samples)
        XCTAssertEqual(result, .endurance)
    }

    func testZoneDistributionDetectsRecoveryWhenAllZ1() {
        // 100% in Z1 (55% HRmax)
        let samples = self.samples(count: 50, hrPercent: 0.55)
        let result = classifier.classifyByZoneDistribution(samples: samples)
        XCTAssertEqual(result, .recovery)
    }

    func testZoneDistributionEmptySamplesReturnsNil() {
        let result = classifier.classifyByZoneDistribution(samples: [])
        XCTAssertNil(result)
    }

    // MARK: Average-HR fallback

    func testAverageHRFallbackRecoveryAtLowHR() {
        // 55% HRmax = 104 bpm
        let result = classifier.classifyByAverageHR(averageHeartRate: 104, durationSeconds: 30 * 60)
        XCTAssertEqual(result, .recovery)
    }

    func testAverageHRFallbackEnduranceAtLowMidHRLongDuration() {
        // 70% HRmax = 133 bpm, 2 uur — moet endurance zijn
        let result = classifier.classifyByAverageHR(averageHeartRate: 133, durationSeconds: 120 * 60)
        XCTAssertEqual(result, .endurance)
    }

    func testAverageHRFallbackTempoAtMidRangeShortDuration() {
        // 75% HRmax = 142 bpm, 45 min
        let result = classifier.classifyByAverageHR(averageHeartRate: 142, durationSeconds: 45 * 60)
        XCTAssertEqual(result, .tempo)
    }

    func testAverageHRFallbackThresholdAtHighHR() {
        // 89% HRmax = 169 bpm
        let result = classifier.classifyByAverageHR(averageHeartRate: 169, durationSeconds: 60 * 60)
        XCTAssertEqual(result, .threshold)
    }

    // MARK: Full classify (keyword > zones > average)

    func testFullClassifyKeywordOverridesPhysiology() {
        // Hoge HR, maar titel zegt 'sociale rit' → social moet winnen
        let highHRSamples = self.samples(count: 100, hrPercent: 0.85)
        let result = classifier.classify(samples: highHRSamples,
                                         averageHeartRate: 162,
                                         durationSeconds: 90 * 60,
                                         title: "Sociale rit met de club")
        XCTAssertEqual(result, .social,
                       "Sociale-keyword moet fysiologische zone-data overrulen — een groep dwingt soms hogere HR af zonder dat het 'tempo' is")
    }

    func testFullClassifyFallsBackToZonesWhenNoKeyword() {
        let z2Samples = self.samples(count: 100, hrPercent: 0.65)
        let result = classifier.classify(samples: z2Samples,
                                         averageHeartRate: 124,
                                         durationSeconds: 120 * 60,
                                         title: "Zaterdag fietstocht")
        XCTAssertEqual(result, .endurance)
    }

    func testFullClassifyFallsBackToAverageHRWithoutSamples() {
        // Geen samples (Strava-import scenario), titel niet matchend
        let result = classifier.classify(samples: nil,
                                         averageHeartRate: 145,
                                         durationSeconds: 50 * 60,
                                         title: "Zondagochtend rit")
        XCTAssertEqual(result, .tempo)
    }

    func testFullClassifyReturnsNilWithoutAnySignal() {
        // Geen samples, geen avg HR, neutrale titel → kan niets concluderen
        let result = classifier.classify(samples: nil,
                                         averageHeartRate: nil,
                                         durationSeconds: 60 * 60,
                                         title: "Workout")
        XCTAssertNil(result)
    }

    // MARK: SessionIntent integratie-check

    func testEverySessionTypeHasIntent() {
        // Borgt dat iedere case een SessionIntent heeft — als er een nieuwe enum-case
        // wordt toegevoegd zonder intent-mapping, vangt deze test dat op via een crash.
        for type in SessionType.allCases {
            let intent = type.intent
            XCTAssertFalse(intent.coachingSummary.isEmpty,
                           "SessionType.\(type.rawValue) ontbreekt een coachingSummary")
            XCTAssertGreaterThanOrEqual(intent.expectedRPERange.lowerBound, 1)
            XCTAssertLessThanOrEqual(intent.expectedRPERange.upperBound, 10)
            XCTAssertGreaterThanOrEqual(intent.targetZoneRange.lowerBound, 1)
            XCTAssertLessThanOrEqual(intent.targetZoneRange.upperBound, 5)
        }
    }
}
