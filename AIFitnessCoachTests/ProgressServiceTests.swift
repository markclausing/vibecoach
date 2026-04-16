import XCTest
@testable import AIFitnessCoach

/// Unit tests voor ProgressService (Epic 23, Sprint 1).
///
/// Dekt drie onderdelen:
///   1. `TRIMPTranslator`         — pure statische functies zonder side-effects
///   2. `BlueprintGap`            — berekende properties van het gap-struct
///   3. `ProgressService`         — filtering, aggregatie en sortering van gaps
///   4. `GoalBlueprint.weeklyKmTarget` — Sprint 23 extension op GoalBlueprint
///
/// FitnessGoal en ActivityRecord zijn @Model klassen maar kunnen
/// zonder SwiftData-context worden aangemaakt voor property-reads (BlueprintCheckerTests-patroon).
final class ProgressServiceTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - Hulpfuncties

    /// Maakt een FitnessGoal aan met een targetDate N weken in de toekomst.
    private func makeGoal(
        title: String,
        sport: SportCategory? = nil,
        weeksAhead: Int = 20,
        weeksAgoCreated: Int = 0,
        isCompleted: Bool = false
    ) -> FitnessGoal {
        let target  = calendar.date(byAdding: .weekOfYear, value: weeksAhead,    to: Date())!
        let created = calendar.date(byAdding: .weekOfYear, value: -weeksAgoCreated, to: Date())!
        return FitnessGoal(
            title: title,
            targetDate: target,
            createdAt: created,
            isCompleted: isCompleted,
            sportCategory: sport
        )
    }

    /// Maakt een ActivityRecord aan met TRIMP, afstand en een startdatum N weken geleden.
    private func makeActivity(
        sport: SportCategory,
        distanceMeters: Double,
        trimp: Double,
        weeksAgo: Int = 1
    ) -> ActivityRecord {
        let date = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date())!
        return ActivityRecord(
            id: UUID().uuidString,
            name: "Test Training",
            distance: distanceMeters,
            movingTime: 3600,
            averageHeartrate: 150,
            sportCategory: sport,
            startDate: date,
            trimp: trimp
        )
    }

    // MARK: - TRIMPTranslator: translate

    /// 8 TRIMP, fietsen: zone2 = ceil(8/2)=4, zone4 = ceil(8/4)=2 → beide zones getoond.
    func testTranslate_CyclingTour_8Trimp_ShowsBothZones() {
        let result = TRIMPTranslator.translate(8.0, for: .cyclingTour)
        XCTAssertEqual(result, "+4 min rustige rit of +2 min tempo-rit",
                       "8 TRIMP cyclingTour moet beide zones tonen met de juiste labels.")
    }

    /// 4 TRIMP, marathon: zone2 = ceil(4/2)=2, zone4 = ceil(4/4)=1 → beide zones getoond.
    func testTranslate_Marathon_4Trimp_ShowsBothZones() {
        let result = TRIMPTranslator.translate(4.0, for: .marathon)
        XCTAssertEqual(result, "+2 min duurloop (Z2) of +1 min intervaltraining (Z4)",
                       "4 TRIMP marathon moet hardloopspecifieke labels gebruiken.")
    }

    // MARK: - GoalBlueprint.weeklyKmTarget

    /// Marathon: Pfitzinger 18/55 → 55 km/week.
    func testWeeklyKmTarget_Marathon_Returns55() {
        let blueprint = BlueprintChecker.blueprint(for: .marathon)
        XCTAssertEqual(blueprint.weeklyKmTarget, 55.0, accuracy: 0.01,
                       "Marathon blueprint moet 55 km/week als opbouwdoel hanteren.")
    }

    // MARK: - ProgressService.analyzeGaps

    /// Lege doellijst → lege uitvoer.
    func testAnalyzeGaps_EmptyGoals_ReturnsEmpty() {
        let result = ProgressService.analyzeGaps(for: [], activities: [])
        XCTAssertTrue(result.isEmpty,
                      "Geen doelen → geen gaps.")
    }

    /// Voltooid doel wordt gefilterd.
    func testAnalyzeGaps_CompletedGoal_IsFiltered() {
        let goal = makeGoal(title: "Marathon Rotterdam", isCompleted: true)
        let result = ProgressService.analyzeGaps(for: [goal], activities: [])
        XCTAssertTrue(result.isEmpty,
                      "Voltooid doel moet worden gefilterd uit de gap-analyse.")
    }
}
