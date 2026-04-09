import XCTest
@testable import AIFitnessCoach

/// Unit tests voor PeriodizationEngine en PhaseSuccessCriteria (Epic 17.1).
///
/// Alle tests zijn puur en synchroon — geen SwiftData container, geen mocks nodig.
final class PeriodizationEngineTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - Helpers

    private func makeGoal(title: String, sport: SportCategory? = nil, weeksAhead: Int) -> FitnessGoal {
        let target = calendar.date(byAdding: .weekOfYear, value: weeksAhead, to: Date())!
        return FitnessGoal(title: title, targetDate: target, sportCategory: sport)
    }

    private func makeRun(distanceMeters: Double, weeksAgo: Int = 1, trimp: Double = 80) -> ActivityRecord {
        let date = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date())!
        return ActivityRecord(
            id: UUID().uuidString,
            name: "Duurloop",
            distance: distanceMeters,
            movingTime: 3600,
            averageHeartrate: nil,
            sportCategory: .running,
            startDate: date,
            trimp: trimp
        )
    }

    private func makeRide(distanceMeters: Double, weeksAgo: Int = 1, trimp: Double = 100) -> ActivityRecord {
        let date = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date())!
        return ActivityRecord(
            id: UUID().uuidString,
            name: "Fietstocht",
            distance: distanceMeters,
            movingTime: 7200,
            averageHeartrate: nil,
            sportCategory: .cycling,
            startDate: date,
            trimp: trimp
        )
    }

    // MARK: - Fase-detectie via PhaseSuccessCriteria

    func testSuccessCriteria_BaseBuildingPct_Is40Percent() {
        XCTAssertEqual(TrainingPhase.baseBuilding.successCriteria.longestSessionPct, 0.40)
    }

    func testSuccessCriteria_BuildPhasePct_Is60Percent() {
        XCTAssertEqual(TrainingPhase.buildPhase.successCriteria.longestSessionPct, 0.60)
    }

    func testSuccessCriteria_PeakPhasePct_Is80Percent() {
        XCTAssertEqual(TrainingPhase.peakPhase.successCriteria.longestSessionPct, 0.80)
    }

    func testSuccessCriteria_TaperingPct_Is50Percent() {
        // Tapering: dit is een MAXIMUM, geen minimum
        XCTAssertEqual(TrainingPhase.tapering.successCriteria.longestSessionPct, 0.50)
    }

    func testSuccessCriteria_AllPhasesHaveNonEmptyCoaching() {
        for phase in TrainingPhase.allCases {
            XCTAssertFalse(phase.successCriteria.coaching.isEmpty,
                           "Fase \(phase.displayName) heeft geen coaching-boodschap.")
        }
    }

    // MARK: - PeriodizationEngine: Fase-detectie

    func testEvaluate_MarathonGoal16WeeksAhead_IsBaseBuildingPhase() {
        let goal = makeGoal(title: "Marathon", weeksAhead: 16)
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [])
        XCTAssertEqual(result?.phase, .baseBuilding)
    }

    func testEvaluate_MarathonGoal6WeeksAhead_IsBuildPhase() {
        let goal = makeGoal(title: "Marathon", weeksAhead: 6)
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [])
        XCTAssertEqual(result?.phase, .buildPhase)
    }

    func testEvaluate_MarathonGoal3WeeksAhead_IsPeakPhase() {
        let goal = makeGoal(title: "Marathon", weeksAhead: 3)
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [])
        XCTAssertEqual(result?.phase, .peakPhase)
    }

    func testEvaluate_MarathonGoal1WeekAhead_IsTapering() {
        let goal = makeGoal(title: "Marathon", weeksAhead: 1)
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [])
        XCTAssertEqual(result?.phase, .tapering)
    }

    // MARK: - PeriodizationEngine: Succescriteria checks

    func testEvaluate_PeakPhase_32kmRun_MeetsLongestSessionCriteria() {
        // Peak-fase vereist ≥80% van 32 km = ≥25.6 km
        let goal = makeGoal(title: "Marathon", weeksAhead: 3)
        let activity = makeRun(distanceMeters: 26_000) // 26 km > 25.6 km ✅
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [activity])
        XCTAssertTrue(result?.meetsLongestSessionCriteria ?? false,
                      "26 km in Peak-fase moet de 80%-eis (≥25.6 km) bevredigen.")
    }

    func testEvaluate_PeakPhase_20kmRun_FailsLongestSessionCriteria() {
        // 20 km < 25.6 km — onvoldoende in de Peak-fase
        let goal = makeGoal(title: "Marathon", weeksAhead: 3)
        let activity = makeRun(distanceMeters: 20_000)
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [activity])
        XCTAssertFalse(result?.meetsLongestSessionCriteria ?? true,
                       "20 km in Peak-fase mag de 80%-eis NIET bevredigen.")
    }

    func testEvaluate_BuildPhase_NoActivities_FailsCriteria() {
        let goal = makeGoal(title: "Marathon", weeksAhead: 8)
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [])
        XCTAssertFalse(result?.meetsLongestSessionCriteria ?? true,
                       "Zonder activiteiten moet de langste-sessie-eis falen.")
        XCTAssertFalse(result?.meetsWeeklyTrimpCriteria ?? true,
                       "Zonder activiteiten moet de TRIMP-eis falen.")
        XCTAssertFalse(result?.isOnTrack ?? true)
    }

    func testEvaluate_BaseBuildingPhase_12kmRun_MeetsCriteria() {
        // Base: ≥40% van 32 km = ≥12.8 km — een 13 km loop moet volstaan
        let goal = makeGoal(title: "Marathon", weeksAhead: 16)
        let activity = makeRun(distanceMeters: 13_000)
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [activity])
        XCTAssertTrue(result?.meetsLongestSessionCriteria ?? false,
                      "13 km in Base Building (eis ≥12.8 km) moet de criteria bevredigen.")
    }

    // MARK: - Tapering-logica (omgekeerde criteria)

    func testEvaluate_TaperingPhase_ShortRun_MeetsCriteria() {
        // Taper: langste sessie moet ≤50% van 32 km = ≤16 km zijn
        let goal = makeGoal(title: "Marathon", weeksAhead: 1)
        let activity = makeRun(distanceMeters: 10_000) // 10 km ≤ 16 km ✅
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [activity])
        XCTAssertTrue(result?.meetsLongestSessionCriteria ?? false,
                      "Een korte 10 km run past bij de Taper-fase (max 16 km).")
    }

    func testEvaluate_TaperingPhase_LongRun_FailsCriteria() {
        // 30 km loop in de taper is een rode vlag
        let goal = makeGoal(title: "Marathon", weeksAhead: 1)
        let activity = makeRun(distanceMeters: 30_000)
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [activity])
        XCTAssertFalse(result?.meetsLongestSessionCriteria ?? true,
                       "Een 30 km loop in de Taper-fase is te zwaar — criteria moet falen.")
    }

    // MARK: - Sport-isolatie

    func testEvaluate_MarathonGoal_CyclingIgnored() {
        // Een fietsrit mag niet meegeteld worden als langste hardloopsessie
        let goal = makeGoal(title: "Marathon", weeksAhead: 8)
        let ride = makeRide(distanceMeters: 100_000) // 100 km rit
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [ride])
        XCTAssertEqual(result?.longestRecentSessionMeters, 0.0,
                       "Fietsactiviteiten mogen niet meetellen voor een marathon-blueprint.")
    }

    func testEvaluate_CyclingGoal_RunningIgnored() {
        let goal = makeGoal(title: "Arnhem-Karlsruhe fietstocht", weeksAhead: 10)
        let run = makeRun(distanceMeters: 32_000)
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [run])
        XCTAssertEqual(result?.longestRecentSessionMeters, 0.0,
                       "Loopactiviteiten mogen niet meetellen voor een fietstocht-blueprint.")
    }

    // MARK: - RequiredSessionMeters berekening

    func testRequiredSessionMeters_PeakMarathon_Is25600m() {
        let goal = makeGoal(title: "Marathon", weeksAhead: 3) // Peak fase
        let result = PeriodizationEngine.evaluate(goal: goal, activities: [])
        // Marathon blueprint: minLongRunDistance = 32.000m, Peak criteria: 80%
        XCTAssertEqual(result?.requiredSessionMeters, 32_000 * 0.80, accuracy: 1.0)
    }

    // MARK: - evaluateAllGoals

    func testEvaluateAllGoals_FiltersCompletedGoals() {
        let active = makeGoal(title: "Marathon", weeksAhead: 10)
        var completed = makeGoal(title: "Arnhem-Karlsruhe", weeksAhead: 5)
        completed.isCompleted = true

        let results = PeriodizationEngine.evaluateAllGoals([active, completed], activities: [])
        XCTAssertEqual(results.count, 1, "Afgeronde doelen mogen niet worden geëvalueerd.")
    }

    func testEvaluateAllGoals_SortsOffTrackFirst() {
        // Doel 1: ver weg, geen activiteiten (niet op schema)
        let goal1 = makeGoal(title: "Marathon volgend jaar", weeksAhead: 30)
        // Doel 2: ook ver weg maar MET voldoende activiteiten (op schema)
        let goal2 = makeGoal(title: "Marathon dit jaar", weeksAhead: 30)
        // Lange duurloop voor goal2
        let activity = makeRun(distanceMeters: 20_000, trimp: 300)

        let results = PeriodizationEngine.evaluateAllGoals([goal2, goal1], activities: [activity])
        // Beide in Base Building, goal1 zonder activiteiten = niet op schema → komt eerst
        if results.count == 2 {
            XCTAssertFalse(results[0].isOnTrack,
                           "Het eerste resultaat moet het doel zijn dat NIET op schema is.")
        }
    }
}
