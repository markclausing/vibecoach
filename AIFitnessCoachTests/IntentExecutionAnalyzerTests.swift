import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Unit tests voor `IntentExecutionAnalyzer`. Borgt de cascade-volgorde
/// (typeMismatch > overload > underload > match > insufficientData) en de
/// 15%-marge bij TRIMP-vergelijking.
@MainActor
final class IntentExecutionAnalyzerTests: XCTestCase {

    private let maxHR: Double = 190
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ActivityRecord.self, configurations: config)
    }

    override func tearDownWithError() throws {
        container = nil
    }

    // MARK: Helpers

    private func planned(activityType: String,
                         description: String,
                         heartRateZone: String? = nil,
                         targetTRIMP: Int? = 80) -> SuggestedWorkout {
        SuggestedWorkout(
            dateOrDay: "Maandag",
            activityType: activityType,
            suggestedDurationMinutes: 60,
            targetTRIMP: targetTRIMP,
            description: description,
            heartRateZone: heartRateZone
        )
    }

    private func actual(trimp: Double?, sessionType: SessionType?) -> ActivityRecord {
        ActivityRecord(
            id: UUID().uuidString,
            name: "Test",
            distance: 10_000,
            movingTime: 3600,
            averageHeartrate: 145,
            sportCategory: .running,
            startDate: Date(),
            trimp: trimp,
            sessionType: sessionType
        )
    }

    // MARK: typeMismatch — hoogste prioriteit

    func testTypeMismatchOverridesEvenWhenTrimpIsCloseToPlan() {
        // Gepland tempo, gedaan endurance. TRIMP zelfs binnen marge — type wint nog steeds.
        // 'Sub-threshold tempo' zou 'threshold' triggeren (keyword komt eerst); we kiezen
        // bewust een description zonder concurrerende keywords.
        let plan = planned(activityType: "Tempo run",
                           description: "Comfortabel hard tempo, niet te zwaar",
                           targetTRIMP: 80)
        let act = actual(trimp: 82, sessionType: .endurance)

        let result = IntentExecutionAnalyzer.analyze(planned: plan, actual: act, maxHeartRate: maxHR)
        XCTAssertEqual(result, .typeMismatch(planned: .tempo, actual: .endurance),
                       "Type-mismatch hoort fundamenteler te zijn dan TRIMP-binnen-marge — ander type = ander stimulus")
    }

    func testTypeMismatchAlsoFiresWithoutTrimpData() {
        let plan = planned(activityType: "Intervaltraining 5x4 min",
                           description: "VO2max werk",
                           targetTRIMP: nil)
        let act = actual(trimp: nil, sessionType: .endurance)

        let result = IntentExecutionAnalyzer.analyze(planned: plan, actual: act, maxHeartRate: maxHR)
        XCTAssertEqual(result, .typeMismatch(planned: .vo2Max, actual: .endurance))
    }

    // MARK: overload / underload — TRIMP-cascade

    func testOverloadDetectedAtPlus20Percent() {
        let plan = planned(activityType: "Duurloop",
                           description: "Lange Z2",
                           targetTRIMP: 100)
        let act = actual(trimp: 120, sessionType: .endurance)

        let result = IntentExecutionAnalyzer.analyze(planned: plan, actual: act, maxHeartRate: maxHR)
        if case let .overload(delta) = result {
            XCTAssertEqual(delta, 20, accuracy: 0.1)
        } else {
            XCTFail("Verwacht .overload, kreeg \(result)")
        }
    }

    func testUnderloadDetectedAtMinus20Percent() {
        let plan = planned(activityType: "Duurloop",
                           description: "Lange Z2",
                           targetTRIMP: 100)
        let act = actual(trimp: 80, sessionType: .endurance)

        let result = IntentExecutionAnalyzer.analyze(planned: plan, actual: act, maxHeartRate: maxHR)
        if case let .underload(delta) = result {
            XCTAssertEqual(delta, -20, accuracy: 0.1)
        } else {
            XCTFail("Verwacht .underload, kreeg \(result)")
        }
    }

    // MARK: 15%-grens — randgevallen

    func testTrimpAtPlus15PercentExactlyIsStillMatch() {
        // 15% afwijking is precies de grens (NIET strikt groter).
        let plan = planned(activityType: "Duurloop",
                           description: "Z2",
                           targetTRIMP: 100)
        let act = actual(trimp: 115, sessionType: .endurance)
        let result = IntentExecutionAnalyzer.analyze(planned: plan, actual: act, maxHeartRate: maxHR)
        XCTAssertEqual(result, .match, "15% exact moet binnen marge vallen — pas vanaf >15% kantelt het naar overload")
    }

    func testTrimpAtPlus15Point01PercentTipsToOverload() {
        let plan = planned(activityType: "Duurloop",
                           description: "Z2",
                           targetTRIMP: 100)
        let act = actual(trimp: 115.5, sessionType: .endurance)
        let result = IntentExecutionAnalyzer.analyze(planned: plan, actual: act, maxHeartRate: maxHR)
        if case .overload = result {
            // OK
        } else {
            XCTFail("Net boven 15% hoort overload op te leveren")
        }
    }

    // MARK: match

    func testMatchWhenTypeAndTrimpAlign() {
        let plan = planned(activityType: "Duurloop",
                           description: "Lange Z2",
                           targetTRIMP: 100)
        let act = actual(trimp: 105, sessionType: .endurance)
        let result = IntentExecutionAnalyzer.analyze(planned: plan, actual: act, maxHeartRate: maxHR)
        XCTAssertEqual(result, .match)
    }

    func testMatchWhenTypeUnknownButTrimpInRange() {
        // Plan-keywords matchen niet (vaag) → plannedType nil. Toch is TRIMP binnen
        // marge, dus we mogen dit als success rapporteren. Een onbekende type-zijde
        // verzwakt het TRIMP-signaal niet.
        let plan = planned(activityType: "Workout",
                           description: "Generic",
                           targetTRIMP: 100)
        let act = actual(trimp: 105, sessionType: nil)
        let result = IntentExecutionAnalyzer.analyze(planned: plan, actual: act, maxHeartRate: maxHR)
        XCTAssertEqual(result, .match)
    }

    // MARK: insufficientData

    func testInsufficientWhenNoTrimpAvailableAndTypesMatch() {
        // Type matches, geen TRIMP — kan geen overload/underload bepalen, geen
        // type-mismatch om over te rapporteren → insufficient.
        let plan = planned(activityType: "Hersteltraining",
                           description: "Easy",
                           targetTRIMP: nil)
        let act = actual(trimp: nil, sessionType: .recovery)
        let result = IntentExecutionAnalyzer.analyze(planned: plan, actual: act, maxHeartRate: maxHR)
        XCTAssertEqual(result, .insufficientData)
    }

    func testInsufficientWhenPlannedTrimpZero() {
        // 0 TRIMP is een rust-dag — geen analyse zinvol bij actuele beweging.
        let plan = planned(activityType: "Rust",
                           description: "Volledige rustdag",
                           targetTRIMP: 0)
        let act = actual(trimp: 50, sessionType: .recovery)
        let result = IntentExecutionAnalyzer.analyze(planned: plan, actual: act, maxHeartRate: maxHR)
        XCTAssertEqual(result, .insufficientData,
                       "Rustdagen kunnen niet vergeleken worden — geen TRIMP-marge te berekenen")
    }

    // MARK: matching helper

    func testFirstMatchingFindsSameDayWorkout() {
        let today = Calendar.current.startOfDay(for: Date())
        let plan = planned(activityType: "Tempo", description: "Tempo")
        // Force scheduledDate naar vandaag zodat displayDate matcht.
        var p = plan
        p.scheduledDate = today

        let act = actual(trimp: 80, sessionType: .tempo)
        // Force startDate naar vandaag (default `Date()` werkt ook; expliciet voor zekerheid).
        // Geen mutatie nodig — startDate is `var` op @Model class niet beschikbaar zonder context.
        // We vertrouwen op default Date() → today.

        let plans: [SuggestedWorkout] = [p]
        let match = plans.first(matching: act)
        XCTAssertNotNil(match)
    }

    func testFirstMatchingReturnsNilWhenNoSameDay() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        var p = planned(activityType: "Tempo", description: "Tempo")
        p.scheduledDate = yesterday

        let act = actual(trimp: 80, sessionType: .tempo) // startDate = vandaag
        let plans: [SuggestedWorkout] = [p]
        XCTAssertNil(plans.first(matching: act))
    }
}
