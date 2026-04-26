import XCTest
@testable import AIFitnessCoach

/// Unit tests voor `IntentExecutionContextFormatter`. Borgt dat elke verdict-case
/// een coach-bruikbare prompt-tekst produceert met de juiste signaalwoorden
/// (MATCH / TYPE-MISMATCH / OVERLOAD / UNDERLOAD) — anders kan de AI er niet op
/// reageren.
final class IntentExecutionContextFormatterTests: XCTestCase {

    func testInsufficientDataProducesEmptyString() {
        let result = IntentExecutionContextFormatter.format(
            verdict: .insufficientData,
            plannedActivity: "Tempo",
            actualActivityName: "Hardloopsessie",
            plannedTRIMP: 80, actualTRIMP: 75
        )
        XCTAssertEqual(result, "",
                       "Insufficient data hoort geen blok in de prompt te plaatsen — coach zou met loze placeholder zitten")
    }

    func testMatchProducesComplimentTrigger() {
        let result = IntentExecutionContextFormatter.format(
            verdict: .match,
            plannedActivity: "Duurloop",
            actualActivityName: "Hardloopsessie",
            plannedTRIMP: 100, actualTRIMP: 105
        )
        XCTAssertTrue(result.contains("MATCH"))
        XCTAssertTrue(result.contains("compliment"),
                      "Bij match hoort een expliciete compliment-trigger — anders gaat de coach die kans missen")
        XCTAssertTrue(result.contains("Duurloop"))
    }

    func testTypeMismatchIncludesBothTypeNamesAndStructuralCaveat() {
        let result = IntentExecutionContextFormatter.format(
            verdict: .typeMismatch(planned: .tempo, actual: .endurance),
            plannedActivity: "Tempo run",
            actualActivityName: "Easy run",
            plannedTRIMP: 80, actualTRIMP: 60
        )
        XCTAssertTrue(result.contains("TYPE-MISMATCH"))
        XCTAssertTrue(result.contains("Tempo"))
        XCTAssertTrue(result.contains("Duurtraining"),
                      "Display-naam van .endurance is 'Duurtraining' — coach moet die termen kennen")
        XCTAssertTrue(result.contains("structureel"),
                      "Caveat tegen overreageren bij eenmalige afwijking moet erin — anders zeurt de coach over één tempo-rit")
    }

    func testTypeMismatchHandlesUnknownActualType() {
        // Edge case: planned is bekend, actual.sessionType is nil (oude record).
        let result = IntentExecutionContextFormatter.format(
            verdict: .typeMismatch(planned: .vo2Max, actual: nil),
            plannedActivity: "VO2max intervallen",
            actualActivityName: "Hardloopsessie",
            plannedTRIMP: 90, actualTRIMP: 60
        )
        XCTAssertTrue(result.contains("VO₂max"))
        XCTAssertTrue(result.contains("onbepaald type"),
                      "Bij onbekend actual-type moet dat expliciet — anders verzint de coach iets")
    }

    func testOverloadIncludesPositiveDeltaAndRecoveryHint() {
        let result = IntentExecutionContextFormatter.format(
            verdict: .overload(trimpDeltaPercent: 22.5),
            plannedActivity: "Duurloop",
            actualActivityName: "Hardloopsessie",
            plannedTRIMP: 100, actualTRIMP: 122
        )
        XCTAssertTrue(result.contains("OVERLOAD"))
        XCTAssertTrue(result.contains("+23%") || result.contains("+22%"),
                      "Delta-percent moet zichtbaar — coach moet kunnen zeggen 'je trainde 23% zwaarder'")
        XCTAssertTrue(result.contains("hersteldag") || result.contains("herstel"),
                      "Bij overload hoort een herstel-suggestie als kompas voor de coach")
    }

    func testUnderloadIncludesNegativeDeltaAndCompensationHint() {
        let result = IntentExecutionContextFormatter.format(
            verdict: .underload(trimpDeltaPercent: -22.0),
            plannedActivity: "Tempo",
            actualActivityName: "Hardloopsessie",
            plannedTRIMP: 100, actualTRIMP: 78
        )
        XCTAssertTrue(result.contains("UNDERLOAD"))
        XCTAssertTrue(result.contains("-22%"))
        XCTAssertTrue(result.contains("compensatie") || result.contains("aangepast"),
                      "Bij underload moet de coach iets concreets kunnen aanbieden — niet alleen vaststellen")
    }

    func testTrimpSuffixIsOmittedWhenZeroOrNil() {
        let result = IntentExecutionContextFormatter.format(
            verdict: .match,
            plannedActivity: "Workout",
            actualActivityName: "Workout",
            plannedTRIMP: nil, actualTRIMP: nil
        )
        XCTAssertFalse(result.contains("TRIMP"),
                       "Geen TRIMP-suffix als beide ontbreken — anders krijg je 'TRIMP nil' in de prompt")
    }
}
