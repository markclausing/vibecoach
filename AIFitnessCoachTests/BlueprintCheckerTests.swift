import XCTest
@testable import AIFitnessCoach

/// Unit tests voor BlueprintChecker (Epic 17, Sprint 17.1).
///
/// BlueprintChecker is een pure struct zonder side-effects —
/// alle tests werken met synthetische FitnessGoal en ActivityRecord objecten.
final class BlueprintCheckerTests: XCTestCase {

    // MARK: - Helpers

    private let calendar = Calendar.current

    /// Maakt een FitnessGoal aan met een targetDate N weken in de toekomst.
    private func makeGoal(title: String, sport: SportCategory? = nil, weeksAhead: Int = 16) -> FitnessGoal {
        let target = calendar.date(byAdding: .weekOfYear, value: weeksAhead, to: Date())!
        return FitnessGoal(title: title, targetDate: target, sportCategory: sport)
    }

    /// Maakt een ActivityRecord aan met opgegeven afstand en N weken geleden als startdatum.
    private func makeActivity(sport: SportCategory, distanceMeters: Double, weeksAgo: Int = 1) -> ActivityRecord {
        let date = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date())!
        return ActivityRecord(
            id: UUID().uuidString,
            name: "Test Training",
            distance: distanceMeters,
            movingTime: 3600,
            averageHeartrate: nil,
            sportCategory: sport,
            startDate: date
        )
    }

    // MARK: - Blueprint Detectie

    func testDetectBlueprintType_MarathonInTitle_ReturnsMarathon() {
        let goal = makeGoal(title: "Amsterdam Marathon 2026")
        XCTAssertEqual(BlueprintChecker.detectBlueprintType(for: goal), .marathon)
    }

    func testDetectBlueprintType_HalveMarathonInTitle_ReturnsHalfMarathon() {
        let goal = makeGoal(title: "Halve Marathon Rotterdam")
        XCTAssertEqual(BlueprintChecker.detectBlueprintType(for: goal), .halfMarathon)
    }

    func testDetectBlueprintType_ArnhemKarlsruhe_ReturnsCyclingTour() {
        let goal = makeGoal(title: "Arnhem–Karlsruhe fietstocht")
        XCTAssertEqual(BlueprintChecker.detectBlueprintType(for: goal), .cyclingTour)
    }

    func testDetectBlueprintType_FallbackOnSportCategory_Running() {
        let goal = makeGoal(title: "Mijn hardloopdoel", sport: .running)
        XCTAssertEqual(BlueprintChecker.detectBlueprintType(for: goal), .marathon)
    }

    func testDetectBlueprintType_UnknownGoal_ReturnsNil() {
        let goal = makeGoal(title: "Gezonder leven", sport: .strength)
        XCTAssertNil(BlueprintChecker.detectBlueprintType(for: goal))
    }

    // MARK: - Marathon Milestones

    func testMarathon_NoActivities_AllMilestonesUnsatisfied() {
        let goal = makeGoal(title: "Marathon", weeksAhead: 20)
        let result = BlueprintChecker.check(goal: goal, activities: [])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.milestones.count, 2)
        XCTAssertTrue(result?.milestones.allSatisfy { !$0.isSatisfied } ?? false,
                      "Zonder activiteiten mogen er geen voldane milestones zijn.")
    }

    func testMarathon_32kmRunBeforeDeadline_LongRunMilestoneSatisfied() {
        let goal = makeGoal(title: "Marathon", weeksAhead: 20)
        // 32 km run 5 weken geleden — ruim vóór de 3-weken-deadline
        let activity = makeActivity(sport: .running, distanceMeters: 32_500, weeksAgo: 5)
        let result = BlueprintChecker.check(goal: goal, activities: [activity])

        let longRunMilestone = result?.milestones.first { $0.id == "marathon_long_run_32" }
        XCTAssertEqual(longRunMilestone?.isSatisfied, true,
                       "Een 32 km loop ruimschoots voor de deadline moet de milestone groen maken.")
    }

    func testMarathon_28kmRunOnly_PartialSatisfaction() {
        let goal = makeGoal(title: "Marathon", weeksAhead: 20)
        let activity = makeActivity(sport: .running, distanceMeters: 28_500, weeksAgo: 8)
        let result = BlueprintChecker.check(goal: goal, activities: [activity])

        let longRun28 = result?.milestones.first { $0.id == "marathon_long_run_28" }
        let longRun32 = result?.milestones.first { $0.id == "marathon_long_run_32" }
        XCTAssertEqual(longRun28?.isSatisfied, true, "28 km rit moet de 28 km milestone bevredigen.")
        XCTAssertEqual(longRun32?.isSatisfied, false, "28 km rit mag NIET de 32 km milestone bevredigen.")
    }

    func testMarathon_CyclingActivityIgnored_MilestoneUnsatisfied() {
        let goal = makeGoal(title: "Marathon", weeksAhead: 20)
        // Fietstocht van 50 km — moet worden genegeerd voor de hardloopeis
        let activity = makeActivity(sport: .cycling, distanceMeters: 50_000, weeksAgo: 5)
        let result = BlueprintChecker.check(goal: goal, activities: [activity])
        XCTAssertTrue(result?.milestones.allSatisfy { !$0.isSatisfied } ?? false,
                      "Een fietsactiviteit mag NOOIT een hardloop-milestone bevredigen.")
    }

    // MARK: - Fietstocht Milestones

    func testCyclingTour_100kmRideBeforeDeadline_MilestoneSatisfied() {
        let goal = makeGoal(title: "Arnhem-Karlsruhe", weeksAhead: 12)
        let activity = makeActivity(sport: .cycling, distanceMeters: 105_000, weeksAgo: 5)
        let result = BlueprintChecker.check(goal: goal, activities: [activity])

        let longRide = result?.milestones.first { $0.id == "cycling_long_ride_100" }
        XCTAssertEqual(longRide?.isSatisfied, true)
    }

    // MARK: - isOnTrack logica

    func testIsOnTrack_AllDeadlinesInFuture_AlwaysOnTrack() {
        // Alle deadlines liggen ver in de toekomst — geen deadline verstreken → altijd op schema
        let goal = makeGoal(title: "Marathon", weeksAhead: 20)
        let result = BlueprintChecker.check(goal: goal, activities: [])
        XCTAssertTrue(result?.isOnTrack ?? false,
                      "Als geen deadline verstreken is, is de sporter altijd op schema.")
    }

    func testCheckAllGoals_FiltersCompletedGoals() {
        let activeGoal = makeGoal(title: "Marathon", weeksAhead: 20)
        var completedGoal = makeGoal(title: "Arnhem-Karlsruhe", weeksAhead: 10)
        completedGoal.isCompleted = true

        let results = BlueprintChecker.checkAllGoals([activeGoal, completedGoal], activities: [])
        XCTAssertEqual(results.count, 1, "Afgeronde doelen mogen niet in de blueprint-check verschijnen.")
    }
}
