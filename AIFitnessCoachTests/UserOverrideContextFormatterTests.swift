import XCTest
@testable import AIFitnessCoach

/// Unit tests voor `UserOverrideContextFormatter`. Borgt dat handmatig verplaatste
/// workouts in een eigen prompt-blok komen mét expliciete instructie aan de coach
/// om de keuze te respecteren.
final class UserOverrideContextFormatterTests: XCTestCase {

    private func workout(id: UUID = UUID(),
                         dateOrDay: String,
                         activityType: String = "Hardlopen",
                         scheduledDate: Date? = nil,
                         isSwapped: Bool = false) -> SuggestedWorkout {
        SuggestedWorkout(
            id: id,
            dateOrDay: dateOrDay,
            activityType: activityType,
            suggestedDurationMinutes: 60,
            targetTRIMP: 80,
            description: "Test",
            scheduledDate: scheduledDate,
            isSwapped: isSwapped
        )
    }

    func testEmptyWhenNoSwappedWorkouts() {
        let plan = [
            workout(dateOrDay: "Maandag"),
            workout(dateOrDay: "Woensdag"),
        ]
        XCTAssertEqual(UserOverrideContextFormatter.format(workouts: plan), "",
                       "Geen swap = geen prompt-blok — anders verplichten we de AI om met lege state te dealen")
    }

    func testEmptyForFullyEmptyPlan() {
        XCTAssertEqual(UserOverrideContextFormatter.format(workouts: []), "")
    }

    func testIncludesSwappedWorkoutWithCriticalInstruction() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 30))!
        let plan = [
            workout(dateOrDay: "Dinsdag", activityType: "Intervallen",
                    scheduledDate: date, isSwapped: true)
        ]
        let result = UserOverrideContextFormatter.format(workouts: plan)

        XCTAssertTrue(result.contains("USER_OVERRIDE"))
        XCTAssertTrue(result.contains("Intervallen"))
        XCTAssertTrue(result.contains("KRITIEKE INSTRUCTIE"))
        XCTAssertTrue(result.contains("Verschuif ze NIET terug"))
    }

    func testIncludesNewDayLabelNotOriginalDateOrDay() {
        // Verplaatst van dinsdag naar donderdag. Het USER_OVERRIDE-blok hoort de
        // NIEUWE dag te vermelden — niet de oorspronkelijke 'Dinsdag'-string van
        // de AI-suggestie. Dat voorkomt dat de coach denkt dat de override 'op
        // dinsdag' staat (waar hij dan opnieuw aan zou willen sleutelen).
        let thursday = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 30))!
        let plan = [
            workout(dateOrDay: "Dinsdag", scheduledDate: thursday, isSwapped: true)
        ]
        let result = UserOverrideContextFormatter.format(workouts: plan)
        XCTAssertTrue(result.contains("Donderdag"))
        XCTAssertFalse(result.contains("Dinsdag"))
    }

    func testMultipleSwapsAreAllListed() {
        let date1 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 28))!
        let date2 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 30))!
        let plan = [
            workout(dateOrDay: "Maandag",  activityType: "Intervallen",
                    scheduledDate: date1, isSwapped: true),
            workout(dateOrDay: "Woensdag", activityType: "Hersteltraining",
                    scheduledDate: date2, isSwapped: true),
            workout(dateOrDay: "Vrijdag",  activityType: "Lange duurloop",
                    isSwapped: false), // niet verplaatst — moet niet verschijnen
        ]
        let result = UserOverrideContextFormatter.format(workouts: plan)

        XCTAssertTrue(result.contains("Intervallen"))
        XCTAssertTrue(result.contains("Hersteltraining"))
        XCTAssertFalse(result.contains("Lange duurloop"),
                       "Niet-verplaatste workouts horen niet in het USER_OVERRIDE-blok")
    }
}
