import XCTest
@testable import AIFitnessCoach

/// Unit tests voor `LastWorkoutContextFormatter`. Borgt dat sessie-type + intent
/// in het laatste-workout-blok belanden zonder dat we de hele ChatViewModel hoeven
/// te draaien.
final class LastWorkoutContextFormatterTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testEmptyWhenRpeMissing() {
        let result = LastWorkoutContextFormatter.format(
            rpe: nil, mood: "🟢", workoutName: "Training", trimp: 100,
            startDate: date, sessionType: nil
        )
        XCTAssertEqual(result, "", "Zonder RPE is er geen feedback om te injecteren")
    }

    func testEmptyWhenMoodMissing() {
        let result = LastWorkoutContextFormatter.format(
            rpe: 7, mood: nil, workoutName: "Training", trimp: 100,
            startDate: date, sessionType: nil
        )
        XCTAssertEqual(result, "", "Zonder mood ontbreekt subjectieve helft van de feedback")
    }

    func testIncludesNameTrimpRpeMoodWhenComplete() {
        let result = LastWorkoutContextFormatter.format(
            rpe: 7, mood: "🟢", workoutName: "Hardloopsessie", trimp: 142,
            startDate: date, sessionType: nil
        )
        XCTAssertTrue(result.contains("Hardloopsessie"))
        XCTAssertTrue(result.contains("TRIMP: 142"))
        XCTAssertTrue(result.contains("RPE: 7/10"))
        XCTAssertTrue(result.contains("Stemming: 🟢"))
        // Geen sessionType doorgegeven → blok mag GEEN sessie-type-suffix bevatten.
        XCTAssertFalse(result.contains("Sessie-type:"))
    }

    func testTrimpUnknownWhenNil() {
        let result = LastWorkoutContextFormatter.format(
            rpe: 5, mood: "😌", workoutName: "Wandeling", trimp: nil,
            startDate: date, sessionType: nil
        )
        XCTAssertTrue(result.contains("TRIMP: onbekend"))
    }

    func testRpeLabelClassification() {
        let licht = LastWorkoutContextFormatter.format(rpe: 2, mood: "😌", workoutName: "x", trimp: 50, startDate: date, sessionType: nil)
        let matig = LastWorkoutContextFormatter.format(rpe: 5, mood: "😌", workoutName: "x", trimp: 50, startDate: date, sessionType: nil)
        let zwaar = LastWorkoutContextFormatter.format(rpe: 8, mood: "😌", workoutName: "x", trimp: 50, startDate: date, sessionType: nil)
        let max = LastWorkoutContextFormatter.format(rpe: 10, mood: "😌", workoutName: "x", trimp: 50, startDate: date, sessionType: nil)

        XCTAssertTrue(licht.contains("(licht (1-3))"))
        XCTAssertTrue(matig.contains("(matig (4-6))"))
        XCTAssertTrue(zwaar.contains("(zwaar (7-8))"))
        XCTAssertTrue(max.contains("(maximaal (9-10))"))
    }

    // MARK: - Story 33.1b: SessionType injectie

    func testIncludesSessionTypeAndIntentWhenProvided() {
        let result = LastWorkoutContextFormatter.format(
            rpe: 3, mood: "😌", workoutName: "Easy run", trimp: 60,
            startDate: date, sessionType: .recovery
        )
        XCTAssertTrue(result.contains("Sessie-type: Herstel"),
                      "Display-naam moet zichtbaar zijn — dat is waar de coach naar refereert")
        XCTAssertTrue(result.contains("Actief herstel"),
                      "Coaching-summary van het intent moet meekomen — architect-notitie: AI begrijpt tekstuele context beter dan label")
    }

    func testCoachingSummaryDifferentPerSessionType() {
        // Verschillende sessie-types horen verschillende intent-strings te produceren —
        // anders is de injectie nutteloos voor coach-differentiatie.
        let recoverySummary = LastWorkoutContextFormatter.format(
            rpe: 3, mood: "😌", workoutName: "x", trimp: 50,
            startDate: date, sessionType: .recovery
        )
        let vo2Summary = LastWorkoutContextFormatter.format(
            rpe: 9, mood: "🥵", workoutName: "x", trimp: 80,
            startDate: date, sessionType: .vo2Max
        )

        XCTAssertNotEqual(recoverySummary, vo2Summary)
        XCTAssertTrue(recoverySummary.contains("Actief herstel"))
        XCTAssertTrue(vo2Summary.contains("Maximale aerobe stimulus"))
    }

    func testNoSessionTypeOmitsBlockEntirely() {
        let result = LastWorkoutContextFormatter.format(
            rpe: 5, mood: "😌", workoutName: "x", trimp: 50,
            startDate: date, sessionType: nil
        )
        XCTAssertFalse(result.contains("Sessie-type:"),
                       "Als de gebruiker geen type heeft (en classifier ook geen voorstel had), mag de prompt geen 'leeg' veld tonen — dat zou de AI zelf laten gokken")
    }
}
