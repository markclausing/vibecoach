import XCTest
@testable import AIFitnessCoach

final class IntentContextFormatterTests: XCTestCase {

    private func makeResult(goal: FitnessGoal,
                            instruction: String) -> PeriodizationResult {
        let intentMod = IntentModifier(
            weeklyTrimpMultiplier: 1.0,
            allowHighIntensity: true,
            backToBackEmphasis: false,
            stretchPaceAllowed: false,
            coachingInstruction: instruction
        )
        return PeriodizationResult(
            goal: goal,
            blueprint: BlueprintChecker.marathonBlueprint,
            phase: .buildPhase,
            criteria: TrainingPhase.buildPhase.successCriteria,
            longestRecentSessionMeters: 0,
            currentWeeklyTrimp: 0,
            intentModifier: intentMod
        )
    }

    func test_format_emptyResults_returnsEmpty() {
        XCTAssertEqual(IntentContextFormatter.format(results: []), "")
    }

    func test_format_emptyInstructions_returnsEmpty() {
        let goal = FitnessGoal(title: "Marathon", targetDate: Date().addingTimeInterval(3600 * 24 * 30))
        let result = makeResult(goal: goal, instruction: "")
        XCTAssertEqual(IntentContextFormatter.format(results: [result]), "")
    }

    func test_format_singleDayRace_omitsTouristNotice() {
        let goal = FitnessGoal(title: "Berlin Marathon",
                               targetDate: Date().addingTimeInterval(3600 * 24 * 30),
                               format: .singleDayRace)
        let r = makeResult(goal: goal, instruction: "Build Phase: opbouwen.")
        let output = IntentContextFormatter.format(results: [r])
        XCTAssertTrue(output.contains("Berlin Marathon"))
        XCTAssertTrue(output.contains("Build Phase: opbouwen."))
        XCTAssertFalse(output.contains("TOERTOCHT"), "SingleDayRace mag geen toertocht-waarschuwing krijgen.")
    }

    func test_format_multiDayStage_addsTouristNotice() {
        let goal = FitnessGoal(title: "Arnhem-Karlsruhe",
                               targetDate: Date().addingTimeInterval(3600 * 24 * 30),
                               format: .multiDayStage)
        let r = makeResult(goal: goal, instruction: "Bouw aerobe basis.")
        let output = IntentContextFormatter.format(results: [r])
        XCTAssertTrue(output.contains("TOERTOCHT, geen race"))
    }

    func test_format_withStretchGoal_addsReadableTime() {
        let goal = FitnessGoal(title: "Marathon",
                               targetDate: Date().addingTimeInterval(3600 * 24 * 30),
                               format: .singleDayRace,
                               stretchGoalTime: 3 * 3600 + 30 * 60) // 3u30
        let r = makeResult(goal: goal, instruction: "Push tempo.")
        let output = IntentContextFormatter.format(results: [r])
        XCTAssertTrue(output.contains("Stretch Goal Doeltijd"))
        XCTAssertTrue(output.contains("3 uur en 30 minuten"))
    }

    func test_format_withSubHourStretchGoal_omitsHours() {
        let goal = FitnessGoal(title: "10K",
                               targetDate: Date().addingTimeInterval(3600 * 24 * 30),
                               format: .singleDayRace,
                               stretchGoalTime: 45 * 60) // 45 min
        let r = makeResult(goal: goal, instruction: "Push tempo.")
        let output = IntentContextFormatter.format(results: [r])
        XCTAssertTrue(output.contains("45 minuten"))
        XCTAssertFalse(output.contains("uur en"), "Sub-uur stretch tijd moet alleen minuten tonen.")
    }
}
