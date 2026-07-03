import XCTest
@testable import AIFitnessCoach

/// Story 65.3: comprehensive branch coverage for `CoachPromptAssembler`.
///
/// Complements `CoachPromptFixtureTests` (which pins the byte-exact wiring through the real
/// `ChatViewModel` seam): here every context-block branch is exercised with a fully-populated
/// snapshot, and the structural prompt markers are pinned against the `systemInstruction`
/// reference per CLAUDE.md §13.
final class CoachPromptAssemblerTests: XCTestCase {

    private var emptyThresholdProfile: UserPhysicalProfile {
        UserPhysicalProfile(weightKg: 70, heightCm: 180, ageYears: 30, sex: .male,
                            weightSource: .healthKit, heightSource: .healthKit)
    }

    private func fullSnapshot() -> CoachPromptAssembler.CoachContextSnapshot {
        var s = CoachPromptAssembler.CoachContextSnapshot()
        s.todayVibeScoreContext = "VIBE_SENTINEL"
        s.lastWorkoutFeedbackContext = "FEEDBACK_SENTINEL"
        s.userOverrideContext = "USEROVERRIDE_SENTINEL\n\n"
        s.intentExecutionContext = "INTENTEXEC_SENTINEL\n\n"
        s.symptomContext = "SYMPTOM_SENTINEL"
        s.workoutPatternsContext = "PATTERNS_SENTINEL"
        s.workoutHistoryContext = "HISTORY_SENTINEL"
        s.weatherContext = "WEATHER_SENTINEL"
        s.blueprintContext = "BLUEPRINT_SENTINEL"
        s.periodizationContext = "PERIODIZATION_SENTINEL"
        s.intentContext = "INTENT_SENTINEL"
        s.eventWindowContext = "EVENTWINDOW_SENTINEL"
        s.gapAnalysisContext = "GAP_SENTINEL"
        s.projectionContext = "PROJECTION_SENTINEL"
        s.nutritionContext = "NUTRITION_SENTINEL"
        s.profileUpdateNote = "PROFILENOTE_SENTINEL"
        return s
    }

    // MARK: - Context prefix branches

    func testBuildContextPrefix_EmitsEveryPopulatedBlock() {
        let prefix = CoachPromptAssembler.buildContextPrefix(
            context: fullSnapshot(),
            profile: nil,
            activeGoals: [],
            activePreferences: [],
            thresholdProfile: emptyThresholdProfile,
            now: Date(timeIntervalSince1970: 1_751_414_400) // 2025-07-02
        )

        // Structural block headers
        XCTAssertTrue(prefix.contains("[RECOVERY STATUS TODAY: VIBE_SENTINEL"))
        XCTAssertTrue(prefix.contains("[SUBJECTIVE FEEDBACK LAST WORKOUT: FEEDBACK_SENTINEL"))
        XCTAssertTrue(prefix.contains("[CURRENT COMPLAINTS — SINGLE SOURCE OF TRUTH"))
        XCTAssertTrue(prefix.contains("[PHYSIOLOGICAL PATTERNS IN RECENT WORKOUTS:"))
        XCTAssertTrue(prefix.contains("[RECENT TRAINING — 14 DAYS"))
        XCTAssertTrue(prefix.contains("[WEATHER CONDITIONS NEXT 7 DAYS"))
        XCTAssertTrue(prefix.contains("[SPORTS-SCIENCE REQUIREMENTS (BLUEPRINT):"))
        XCTAssertTrue(prefix.contains("[PERIODIZATION — PHASE, SUCCESS CRITERIA & COACH BEHAVIOUR:"))
        XCTAssertTrue(prefix.contains("[GOAL INTENTS AND APPROACH"))
        XCTAssertTrue(prefix.contains("[GAP ANALYSIS — BLUEPRINT VS. REALITY"))

        // Raw pass-through fields appear verbatim
        for token in ["USEROVERRIDE_SENTINEL", "INTENTEXEC_SENTINEL", "SYMPTOM_SENTINEL",
                      "PATTERNS_SENTINEL", "HISTORY_SENTINEL", "WEATHER_SENTINEL",
                      "BLUEPRINT_SENTINEL", "PERIODIZATION_SENTINEL", "INTENT_SENTINEL",
                      "EVENTWINDOW_SENTINEL", "GAP_SENTINEL", "PROJECTION_SENTINEL",
                      "NUTRITION_SENTINEL", "PROFILENOTE_SENTINEL"] {
            XCTAssertTrue(prefix.contains(token), "missing \(token)")
        }

        XCTAssertTrue(prefix.hasSuffix("[QUESTION]: "))
    }

    func testBuildContextPrefix_NoVibeDataSentinel_EmitsNoWatchInstruction() {
        var s = CoachPromptAssembler.CoachContextSnapshot()
        s.todayVibeScoreContext = VibeScoreContextFormatter.noVibeDataSentinel
        let prefix = CoachPromptAssembler.buildContextPrefix(
            context: s, profile: nil, thresholdProfile: emptyThresholdProfile, now: Date()
        )
        XCTAssertTrue(prefix.contains("No objective biometric data is available"))
    }

    func testBuildContextPrefix_EmptyContext_OnlyDateAndQuestion() {
        let prefix = CoachPromptAssembler.buildContextPrefix(
            context: CoachPromptAssembler.CoachContextSnapshot(),
            profile: nil,
            thresholdProfile: emptyThresholdProfile,
            now: Date(timeIntervalSince1970: 1_751_414_400)
        )
        XCTAssertTrue(prefix.hasPrefix("[CURRENT DATE: Today is 2025-07-02."))
        XCTAssertTrue(prefix.hasSuffix("[QUESTION]: "))
        XCTAssertFalse(prefix.contains("[WEATHER"))
    }

    func testBuildContextPrefix_AthleteBlock_WithRecoveryWarning() {
        let profile = AthleticProfile(
            peakDistanceInMeters: 50000, peakDurationInSeconds: 7200,
            averageWeeklyVolumeInSeconds: 20000, daysSinceLastTraining: 0, isRecoveryNeeded: true
        )
        let prefix = CoachPromptAssembler.buildContextPrefix(
            context: CoachPromptAssembler.CoachContextSnapshot(),
            profile: profile, thresholdProfile: emptyThresholdProfile, now: Date()
        )
        XCTAssertTrue(prefix.contains("[ATHLETE CONTEXT: Has a peak performance of 50.0 km"))
        XCTAssertTrue(prefix.contains("URGENT: The athlete shows signs of overtraining"))
    }

    // MARK: - Thresholds block

    func testThresholdsBlock_Empty_WhenNoThresholds() {
        XCTAssertEqual(CoachPromptAssembler.buildTrainingThresholdsBlock(profile: emptyThresholdProfile), "")
    }

    func testThresholdsBlock_EmitsMaxHR() {
        let profile = UserPhysicalProfile(
            weightKg: 70, heightCm: 180, ageYears: 30, sex: .male,
            weightSource: .healthKit, heightSource: .healthKit,
            maxHeartRate: ThresholdValue(value: 200, source: .manual)
        )
        let block = CoachPromptAssembler.buildTrainingThresholdsBlock(profile: profile)
        XCTAssertTrue(block.contains("Max HR: 200 BPM (handmatig)"))
        XCTAssertTrue(block.contains("[TRAINING THRESHOLDS"))
    }

    func testThresholdSourceLabel() {
        XCTAssertEqual(CoachPromptAssembler.thresholdSourceLabel(.automatic), "auto")
        XCTAssertEqual(CoachPromptAssembler.thresholdSourceLabel(.manual), "handmatig")
        XCTAssertEqual(CoachPromptAssembler.thresholdSourceLabel(.strava), "Strava")
    }

    // MARK: - Stored plan / status prompt

    func testStoredPlanString_EmptyData_FallbackText() {
        XCTAssertEqual(CoachPromptAssembler.storedPlanString(from: Data()), "No current planned schedule known.")
    }

    func testCurrentStatusPrompt_ContainsLoadAndInstruction() {
        let now = Date(timeIntervalSince1970: 1_751_414_400)
        let workout = CoachPromptAssembler.DailyWorkout(date: now, name: "Ride", durationMinutes: 60, trimp: 80)
        let prompt = CoachPromptAssembler.currentStatusPrompt(
            workouts: [workout], days: 7, activeGoals: [], storedPlanData: Data(), now: now
        )
        XCTAssertTrue(prompt.contains("Total Cumulative TRIMP: 80"))
        XCTAssertTrue(prompt.contains("Instruction for the Coach:"))
        XCTAssertTrue(prompt.contains("60 min Ride (TRIMP: 80)"))
    }

    // MARK: - Structural markers vs systemInstruction (§13)

    func testStructuralMarkers_PresentInSystemInstruction() {
        let instruction = CoachPromptAssembler.systemInstruction(replyLanguage: "Dutch")
        for marker in CoachPromptAssembler.structuralPromptMarkers {
            XCTAssertTrue(instruction.contains(marker), "systemInstruction is missing structural marker: \(marker)")
        }
    }

    func testSystemInstruction_HonoursReplyLanguage() {
        let instruction = CoachPromptAssembler.systemInstruction(replyLanguage: "Portuguese")
        XCTAssertTrue(instruction.contains("Always reply to the user in Portuguese"))
    }

    /// fix/coach-plan-full-week: the plan JSON contract must require a full 7-day plan with
    /// explicit rest entries, otherwise skipped days render as empty gaps ("—") in the week
    /// strip instead of a rest day.
    func testSystemInstruction_RequiresFull7DayPlanWithExplicitRestDays() {
        let instruction = CoachPromptAssembler.systemInstruction(replyLanguage: "Dutch")
        XCTAssertTrue(instruction.contains("MANDATORY — FULL 7-DAY PLAN"),
                      "systemInstruction must carry the full-week rule.")
        XCTAssertTrue(instruction.contains("EXACTLY ONE entry for EVERY one of the next 7 calendar days"),
                      "The rule must require exactly one entry per day.")
        XCTAssertTrue(instruction.contains("EXPLICIT rest entry"),
                      "Non-training days must be explicit rest entries.")
        // The rest phrasing must be classifiable by SuggestedWorkout.isRestDay in every language.
        for restWord in ["Rustdag", "Rest day", "Ruhetag", "Día de descanso"] {
            XCTAssertTrue(instruction.contains(restWord),
                          "systemInstruction must name the rest word \(restWord).")
            let sample = SuggestedWorkout(dateOrDay: "Maandag", activityType: restWord,
                                          suggestedDurationMinutes: 30, targetTRIMP: 30, description: "x")
            XCTAssertTrue(sample.isRestDay, "\(restWord) must classify as a rest day.")
        }
    }

    /// The coach must write full weekday names — an abbreviation instruction guards the round trip
    /// with SuggestedWorkout.resolvedDate (which now also parses abbreviations defensively).
    func testSystemInstruction_ForbidsWeekdayAbbreviations() {
        let instruction = CoachPromptAssembler.systemInstruction(replyLanguage: "Dutch")
        XCTAssertTrue(instruction.contains("Write the weekday name IN FULL"),
                      "systemInstruction must forbid weekday abbreviations.")
    }

    /// The emitter side: markers the context prefix produces for injury/periodization must
    /// also live in the systemInstruction, so the coach's section lookup stays aligned.
    func testEmitterMarkers_AlignWithSystemInstruction() {
        let instruction = CoachPromptAssembler.systemInstruction(replyLanguage: "Dutch")
        for marker in ["🚫 HARD CONSTRAINT", "✅ RECOVERED", "🎉", "🚨"] {
            XCTAssertTrue(instruction.contains(marker), "systemInstruction missing emitter marker: \(marker)")
        }
    }
}
