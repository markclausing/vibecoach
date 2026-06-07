import XCTest
@testable import AIFitnessCoach

/// Epic #48 — `WorkoutInsightService.buildPrompt`. Borgt:
///  • `[GOALS-STATUS]` en `[PERIODIZATION]` blokken verschijnen alleen wanneer
///    de bijbehorende context-velden niet-leeg zijn
///  • Bij geen patterns wordt de fallback-zin "Geen significante patronen
///    gedetecteerd…" gebruikt zodat de coach een positieve frame kan schrijven
///  • Recovery-events blijven correct geformatteerd ongeacht doelen/periodisering
///
/// Geen Gemini-call — we testen alleen de prompt-string-bouw via de internal
/// `buildPrompt`-functie (testable via `@testable import`).
final class WorkoutInsightServicePromptTests: XCTestCase {

    private let service = WorkoutInsightService(
        primaryFactory: { nil },
        fallbackFactory: { nil }
    )

    private func makeContext(goalsContext: String? = nil,
                             periodizationContext: String? = nil,
                             recoveryEvents: [WorkoutInsightService.RecoveryEventSummary] = []) -> WorkoutInsightService.InsightContext {
        WorkoutInsightService.InsightContext(
            sportLabel: "Wielrennen",
            durationMinutes: 120,
            sessionTypeLabel: "Endurance",
            title: "Afternoon Ride",
            zones: nil,
            maxHeartRate: 195,
            lactateThresholdHR: 165,
            ftp: 280,
            recoveryEvents: recoveryEvents,
            goalsContext: goalsContext,
            periodizationContext: periodizationContext
        )
    }

    // MARK: Doelen-status blok

    func testBuildPrompt_GoalsContextNil_BlockOmitted() {
        let prompt = service.buildPrompt(patterns: [], context: makeContext(goalsContext: nil))
        XCTAssertFalse(prompt.contains("[GOALS-STATUS]"),
                       "Bij geen actief doel mag het GOALS-STATUS-blok niet in de prompt staan")
    }

    func testBuildPrompt_GoalsContextEmpty_BlockOmitted() {
        let prompt = service.buildPrompt(patterns: [], context: makeContext(goalsContext: ""))
        XCTAssertFalse(prompt.contains("[GOALS-STATUS]"),
                       "Lege string is functioneel hetzelfde als nil — blok niet renderen")
    }

    func testBuildPrompt_GoalsContextProvided_BlockIncluded() {
        let blueprint = "• Doel 'Marathon Rotterdam' (12.0 weken resterend) — Op schema (2/4 kritieke eisen behaald)."
        let prompt = service.buildPrompt(patterns: [], context: makeContext(goalsContext: blueprint))
        XCTAssertTrue(prompt.contains("[GOALS-STATUS]"))
        XCTAssertTrue(prompt.contains("Marathon Rotterdam"),
                      "Prompt moet de doel-titel doorgeven aan de coach")
    }

    // MARK: Periodisering blok

    func testBuildPrompt_PeriodizationContextNil_BlockOmitted() {
        let prompt = service.buildPrompt(patterns: [], context: makeContext(periodizationContext: nil))
        XCTAssertFalse(prompt.contains("[PERIODIZATION]"))
    }

    func testBuildPrompt_PeriodizationContextProvided_BlockIncluded() {
        let phase = "Doel 'Marathon Rotterdam': Build-fase, TRIMP-target 450/week (huidig 380)."
        let prompt = service.buildPrompt(patterns: [], context: makeContext(periodizationContext: phase))
        XCTAssertTrue(prompt.contains("[PERIODIZATION]"))
        XCTAssertTrue(prompt.contains("Build-fase"))
    }

    // MARK: Combinatie

    func testBuildPrompt_BothContextsProvided_BothBlocksAppearInOrder() {
        let bp = "• Doel 'Halve Marathon' — Op schema (1/3 behaald)."
        let phase = "Halve Marathon: Peak-fase, TRIMP-target 320/week."
        let prompt = service.buildPrompt(patterns: [], context: makeContext(
            goalsContext: bp,
            periodizationContext: phase
        ))
        guard let goalsRange = prompt.range(of: "[GOALS-STATUS]"),
              let phaseRange = prompt.range(of: "[PERIODIZATION]") else {
            return XCTFail("Beide blokken moeten aanwezig zijn")
        }
        XCTAssertLessThan(goalsRange.lowerBound, phaseRange.lowerBound,
                          "GOALS-STATUS moet vóór PERIODIZATION staan voor consistente lees-volgorde")
    }

    // MARK: Geen patterns — Epic #47-fallback

    func testBuildPrompt_EmptyPatterns_ContainsFallbackPhrase() {
        let prompt = service.buildPrompt(patterns: [], context: makeContext())
        XCTAssertTrue(prompt.contains("No significant patterns detected"),
                      "Bij lege patterns moet de fallback-zin in de prompt staan zodat de coach positief kan framen")
    }

    // MARK: Recovery-events onafhankelijk van doelen

    func testBuildPrompt_RecoveryEventsAlongsideGoals_BothPresent() {
        let event = WorkoutInsightService.RecoveryEventSummary(
            durationSeconds: 625,
            drop: 37,
            qualityLabel: "uitstekend"
        )
        let prompt = service.buildPrompt(
            patterns: [],
            context: makeContext(
                goalsContext: "• Doel 'Marathon' — Op schema.",
                recoveryEvents: [event]
            )
        )
        XCTAssertTrue(prompt.contains("Recovery events"))
        XCTAssertTrue(prompt.contains("[GOALS-STATUS]"))
        XCTAssertTrue(prompt.contains("uitstekend"),
                      "Quality-label moet meekomen zodat de coach de juiste toon kan kiezen")
    }
}
