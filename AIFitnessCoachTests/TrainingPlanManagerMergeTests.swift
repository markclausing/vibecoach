import XCTest
@testable import AIFitnessCoach

/// Unit tests voor `TrainingPlanManager.mergeReplannedPlan(_:)`. Borgt dat
/// handmatig verplaatste sessies (`isSwapped == true`) leidend zijn boven AI-output —
/// een AI die de swap-dag "vergeet" mag de gebruiker NIET overrulen.
@MainActor
final class TrainingPlanManagerMergeTests: XCTestCase {

    private var manager: TrainingPlanManager!
    private let calendar = Calendar.current

    override func setUpWithError() throws {
        // Schoon AppStorage zodat tests onafhankelijk zijn.
        UserDefaults.standard.removeObject(forKey: "latestSuggestedPlanData")
        manager = TrainingPlanManager()
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "latestSuggestedPlanData")
        manager = nil
    }

    // MARK: Helpers

    private func makeWorkout(activityType: String,
                             scheduledDate: Date? = nil,
                             isSwapped: Bool = false,
                             targetTRIMP: Int? = 80,
                             dateOrDay: String = "Maandag") -> SuggestedWorkout {
        SuggestedWorkout(
            dateOrDay: dateOrDay,
            activityType: activityType,
            suggestedDurationMinutes: 60,
            targetTRIMP: targetTRIMP,
            description: "Test workout",
            scheduledDate: scheduledDate,
            isSwapped: isSwapped
        )
    }

    private func plan(_ workouts: [SuggestedWorkout]) -> SuggestedTrainingPlan {
        SuggestedTrainingPlan(motivation: "Test plan", workouts: workouts)
    }

    // MARK: Geen actief plan

    func testMergeReturnsFalseWhenNoActivePlan() {
        let aiPlan = plan([makeWorkout(activityType: "Tempo")])
        XCTAssertFalse(manager.mergeReplannedPlan(aiPlan),
                       "Zonder actief plan is er niets om mee te mergen — caller moet dan updatePlan rechtstreeks aanroepen")
    }

    // MARK: Geen swaps — AI vervangt 1-op-1

    func testMergeWithoutSwapsActsLikeReplace() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 27))!
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!

        let original = plan([
            makeWorkout(activityType: "Hardlopen", scheduledDate: monday),
            makeWorkout(activityType: "Rust", scheduledDate: tuesday)
        ])
        manager.updatePlan(original)

        let aiPlan = plan([
            makeWorkout(activityType: "Intervaltraining", scheduledDate: monday),
            makeWorkout(activityType: "Easy run", scheduledDate: tuesday)
        ])
        manager.mergeReplannedPlan(aiPlan)

        let result = manager.activePlan?.workouts.map(\.activityType)
        XCTAssertEqual(result, ["Intervaltraining", "Easy run"],
                       "Zonder swaps wint AI volledig — geen filter")
    }

    // MARK: Eén swap — AI mag die dag NIET vervangen

    func testMergeFiltersAIOutputThatOverlapsWithSwap() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 27))!
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!

        let original = plan([
            // Maandag is verplaatste sessie — heilig
            makeWorkout(activityType: "Lange duurloop", scheduledDate: monday, isSwapped: true),
            makeWorkout(activityType: "Rust", scheduledDate: tuesday)
        ])
        manager.updatePlan(original)

        // AI suggereert óók iets op maandag — dat moet geweerd worden
        let aiPlan = plan([
            makeWorkout(activityType: "VO2 intervallen", scheduledDate: monday),
            makeWorkout(activityType: "Tempo", scheduledDate: tuesday),
            makeWorkout(activityType: "Easy", scheduledDate: wednesday)
        ])
        manager.mergeReplannedPlan(aiPlan)

        let result = manager.activePlan?.workouts.map(\.activityType) ?? []
        XCTAssertTrue(result.contains("Lange duurloop"),
                      "Heilige swap moet bewaard blijven")
        XCTAssertFalse(result.contains("VO2 intervallen"),
                       "AI's voorstel voor de heilige dag moet weggefilterd zijn — defense in depth")
        XCTAssertTrue(result.contains("Tempo"))
        XCTAssertTrue(result.contains("Easy"))
    }

    // MARK: Volgorde — UI moet chronologisch zijn

    func testMergedPlanIsSortedByDisplayDate() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 27))!
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
        let friday = calendar.date(byAdding: .day, value: 4, to: monday)!

        let original = plan([
            // Verplaatste sessie op vrijdag
            makeWorkout(activityType: "Lange duurloop", scheduledDate: friday, isSwapped: true)
        ])
        manager.updatePlan(original)

        let aiPlan = plan([
            makeWorkout(activityType: "Tempo", scheduledDate: wednesday),
            makeWorkout(activityType: "Easy", scheduledDate: monday)
        ])
        manager.mergeReplannedPlan(aiPlan)

        let dates = manager.activePlan?.workouts.map(\.displayDate) ?? []
        XCTAssertEqual(dates, dates.sorted(),
                       "Resultaat moet chronologisch — anders renderen UI's de volgorde verkeerd")
    }

    // MARK: AI plant niets nieuws — alleen swaps overblijven

    func testMergeWithEmptyAIPlanKeepsOnlySwaps() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 27))!
        let original = plan([
            makeWorkout(activityType: "Lange duurloop", scheduledDate: monday, isSwapped: true)
        ])
        manager.updatePlan(original)

        let aiPlan = plan([])
        manager.mergeReplannedPlan(aiPlan)

        let result = manager.activePlan?.workouts.map(\.activityType) ?? []
        XCTAssertEqual(result, ["Lange duurloop"],
                       "Lege AI-output mag niet leiden tot verlies van swap")
    }

    // MARK: AI's motivation overneemt

    func testMergedPlanUsesAIMotivation() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 27))!
        let original = plan([makeWorkout(activityType: "Tempo", scheduledDate: monday, isSwapped: true)])
        manager.updatePlan(original)

        let aiPlan = SuggestedTrainingPlan(
            motivation: "Hier is je herziene week — let op je herstel.",
            workouts: []
        )
        manager.mergeReplannedPlan(aiPlan)

        XCTAssertEqual(manager.activePlan?.motivation, "Hier is je herziene week — let op je herstel.",
                       "AI's motivatie hoort de oude te vervangen — anders krijg je 'Test plan' te zien")
    }

    // MARK: Swap-status blijft behouden

    func testMergedSwapsKeepIsSwappedFlag() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 27))!
        let original = plan([
            makeWorkout(activityType: "Lange duurloop", scheduledDate: monday, isSwapped: true)
        ])
        manager.updatePlan(original)

        manager.mergeReplannedPlan(plan([]))

        let swap = manager.activePlan?.workouts.first
        XCTAssertEqual(swap?.isSwapped, true,
                       "Bewaarde swap moet zijn isSwapped-flag behouden — anders verdwijnt de 'Verplaatst'-badge")
    }
}
