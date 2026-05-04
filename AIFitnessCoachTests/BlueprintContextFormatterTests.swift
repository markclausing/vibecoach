import XCTest
@testable import AIFitnessCoach

final class BlueprintContextFormatterTests: XCTestCase {

    func test_format_emptyResults_returnsEmptyString() {
        XCTAssertEqual(BlueprintContextFormatter.format(results: []), "")
    }

    func test_format_singleResultOnTrack_includesGoalAndStatus() {
        let goal = FitnessGoal(title: "Marathon Amsterdam",
                               targetDate: Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date())!)
        let result = BlueprintCheckResult(
            blueprint: BlueprintChecker.marathonBlueprint,
            goal: goal,
            milestones: [
                MilestoneStatus(id: "m1", description: "28 km duurloop",
                                isSatisfied: true, satisfiedByDate: Date(),
                                deadline: Date().addingTimeInterval(-86400),
                                weeksBefore: 6),
                MilestoneStatus(id: "m2", description: "32 km duurloop",
                                isSatisfied: true, satisfiedByDate: Date(),
                                deadline: Date().addingTimeInterval(-86400),
                                weeksBefore: 3)
            ]
        )

        let output = BlueprintContextFormatter.format(results: [result])
        XCTAssertTrue(output.contains("Marathon Amsterdam"))
        XCTAssertTrue(output.contains("Marathon"))           // blueprint displayName
        XCTAssertTrue(output.contains("Op schema"))
        XCTAssertTrue(output.contains("(2/2 kritieke eisen behaald)"))
        XCTAssertTrue(output.contains("28 km duurloop (behaald)"))
        XCTAssertTrue(output.contains("32 km duurloop (behaald)"))
    }

    func test_format_resultBehind_showsOpenMilestoneWithDeadline() {
        let goal = FitnessGoal(title: "Halve Marathon",
                               targetDate: Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date())!)
        // Deadline ligt al ácht dagen in het verleden zonder dat de milestone behaald is →
        // `isOnTrack` valt op `false` (filter pakt 'm op, allSatisfy faalt).
        let pastDeadline = Calendar.current.date(byAdding: .day, value: -8, to: Date())!
        let result = BlueprintCheckResult(
            blueprint: BlueprintChecker.halfMarathonBlueprint,
            goal: goal,
            milestones: [
                MilestoneStatus(id: "m1", description: "16 km duurloop",
                                isSatisfied: false, satisfiedByDate: nil,
                                deadline: pastDeadline,
                                weeksBefore: 4)
            ]
        )

        let output = BlueprintContextFormatter.format(results: [result])
        XCTAssertTrue(output.contains("Achter op schema"), "Verstreken open milestone hoort 'Achter op schema' te triggeren. Output: \(output)")
        XCTAssertTrue(output.contains("(0/1 kritieke eisen behaald)"))
        XCTAssertTrue(output.contains("16 km duurloop"))
        XCTAssertTrue(output.contains("deadline:"))
        XCTAssertTrue(output.contains("4 weken voor race"))
    }

    func test_format_multipleResults_separatedByNewlines() {
        let g1 = FitnessGoal(title: "Goal A",
                             targetDate: Calendar.current.date(byAdding: .day, value: 30, to: Date())!)
        let g2 = FitnessGoal(title: "Goal B",
                             targetDate: Calendar.current.date(byAdding: .day, value: 60, to: Date())!)
        let r1 = BlueprintCheckResult(blueprint: BlueprintChecker.marathonBlueprint, goal: g1, milestones: [])
        let r2 = BlueprintCheckResult(blueprint: BlueprintChecker.cyclingTourBlueprint, goal: g2, milestones: [])

        let output = BlueprintContextFormatter.format(results: [r1, r2])
        XCTAssertTrue(output.contains("Goal A"))
        XCTAssertTrue(output.contains("Goal B"))
    }
}
