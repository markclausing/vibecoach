import XCTest
@testable import AIFitnessCoach

/// Unit tests voor `PlanResetPromptBuilder`. Borgt dat de heilige sessies expliciet
/// in de prompt staan met ISO-datums, en dat de instructie niet onderhandelbaar is
/// over het behoud daarvan.
final class PlanResetPromptBuilderTests: XCTestCase {

    private let referenceDate = Date(timeIntervalSince1970: 1_745_625_600) // 2025-04-26

    private func makeWorkout(activityType: String,
                             scheduledDate: Date,
                             targetTRIMP: Int? = 80,
                             isSwapped: Bool = true) -> SuggestedWorkout {
        SuggestedWorkout(
            dateOrDay: "Maandag",
            activityType: activityType,
            suggestedDurationMinutes: 60,
            targetTRIMP: targetTRIMP,
            description: "Test",
            scheduledDate: scheduledDate,
            isSwapped: isSwapped
        )
    }

    // MARK: Eén swap

    func testSingleSwapMentionsHeiligeSessie() {
        let date = Calendar.current.date(byAdding: .day, value: 2, to: referenceDate)!
        let plan = [makeWorkout(activityType: "Intervaltraining", scheduledDate: date, targetTRIMP: 90)]
        let (system, user) = PlanResetPromptBuilder.build(swappedWorkouts: plan, now: referenceDate)

        XCTAssertTrue(system.contains("Heilige verplaatste sessies"),
                      "De heilige-sectie moet bovenaan zodat de coach 'm niet kan missen")
        XCTAssertTrue(system.contains("Intervaltraining"))
        XCTAssertTrue(system.contains("TRIMP 90"))
        XCTAssertTrue(user.contains("verplaatste sessie") && !user.contains("sessies"),
                      "User-facing tekst moet enkelvoud gebruiken bij één swap")
    }

    func testSingleSwapIncludesISODate() {
        let date = Calendar.current.date(byAdding: .day, value: 2, to: referenceDate)!
        let isoFormatter = DateFormatter(); isoFormatter.dateFormat = "yyyy-MM-dd"
        let expectedIso = isoFormatter.string(from: date)

        let plan = [makeWorkout(activityType: "Tempo", scheduledDate: date)]
        let (system, _) = PlanResetPromptBuilder.build(swappedWorkouts: plan, now: referenceDate)

        XCTAssertTrue(system.contains(expectedIso),
                      "ISO-datum moet zichtbaar zodat Gemini niet hoeft te raden over weekday-mapping")
    }

    // MARK: Meerdere swaps

    func testMultipleSwapsMentionsAllAndUsesPlural() {
        let dayA = Calendar.current.date(byAdding: .day, value: 1, to: referenceDate)!
        let dayB = Calendar.current.date(byAdding: .day, value: 3, to: referenceDate)!
        let plan = [
            makeWorkout(activityType: "Intervaltraining", scheduledDate: dayA, targetTRIMP: 90),
            makeWorkout(activityType: "Lange duurloop", scheduledDate: dayB, targetTRIMP: 130)
        ]
        let (system, user) = PlanResetPromptBuilder.build(swappedWorkouts: plan, now: referenceDate)

        XCTAssertTrue(system.contains("Intervaltraining"))
        XCTAssertTrue(system.contains("Lange duurloop"))
        XCTAssertTrue(user.contains("2 verplaatste sessies"),
                      "User-facing tekst moet meervoud + telling gebruiken bij meerdere swaps")
    }

    // MARK: Geen swaps — edge case

    func testEmptySwapsStillProducesValidPrompt() {
        let (system, user) = PlanResetPromptBuilder.build(swappedWorkouts: [], now: referenceDate)
        XCTAssertTrue(system.contains("schoon 7-daags plan"),
                      "Bij geen swaps moet de instructie helder zijn dat het een vers plan wordt")
        XCTAssertFalse(system.contains("Heilige"),
                       "Geen heilige-sectie als er niets te beschermen is — anders verwarrend")
        XCTAssertFalse(user.isEmpty)
    }

    // MARK: Strenge instructies aanwezig

    func testPromptIncludesNonNegotiableInstructions() {
        let date = Calendar.current.date(byAdding: .day, value: 2, to: referenceDate)!
        let plan = [makeWorkout(activityType: "Tempo", scheduledDate: date)]
        let (system, _) = PlanResetPromptBuilder.build(swappedWorkouts: plan, now: referenceDate)

        XCTAssertTrue(system.contains("VOLLEDIGE 7-daagse schema"),
                      "AI moet expliciet weten dat hij ALLE dagen moet retourneren")
        XCTAssertTrue(system.contains("ISO-datums") || system.contains("yyyy-MM-dd"),
                      "ISO-datum-instructie verkleint kans op weekday-string-ambiguïteit")
        XCTAssertTrue(system.contains("App-side merge filtert"),
                      "Coach moet weten dat z'n output door een veiligheidsnet gaat — minder druk om perfect te zijn")
    }

    func testTodayIsISOFormatted() {
        let isoFormatter = DateFormatter(); isoFormatter.dateFormat = "yyyy-MM-dd"
        let expectedToday = isoFormatter.string(from: referenceDate)
        let (system, _) = PlanResetPromptBuilder.build(swappedWorkouts: [], now: referenceDate)
        XCTAssertTrue(system.contains(expectedToday),
                      "Vandaag-ISO moet expliciet in de prompt — anders gaat AI 'vandaag' aannemen i.p.v. de echte datum")
    }
}
