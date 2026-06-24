import XCTest
@testable import AIFitnessCoach

/// Story 61.4 (L-2) — `TrainingPlanSafetyValidator`.
/// Verifies the code-side clamp of model-proposed plan parameters:
///  • absurd / negative durations and TRIMP are bounded,
///  • in-range plans pass through untouched (clampedCount == 0),
///  • clamp count reflects affected workouts,
///  • identity/override fields (id, scheduledDate, isSwapped) are preserved.
final class TrainingPlanSafetyValidatorTests: XCTestCase {

    private func workout(
        duration: Int,
        trimp: Int?,
        id: UUID = UUID(),
        scheduledDate: Date? = nil,
        isSwapped: Bool = false
    ) -> SuggestedWorkout {
        SuggestedWorkout(
            id: id,
            dateOrDay: "Maandag",
            activityType: "Hardlopen",
            suggestedDurationMinutes: duration,
            targetTRIMP: trimp,
            description: "Zone 2",
            scheduledDate: scheduledDate,
            isSwapped: isSwapped
        )
    }

    func testSanitize_InRangePlan_IsUnchanged() {
        let plan = SuggestedTrainingPlan(
            motivation: "Go",
            workouts: [workout(duration: 45, trimp: 60), workout(duration: 0, trimp: 0)]
        )
        let result = TrainingPlanSafetyValidator.sanitize(plan)
        XCTAssertEqual(result.clampedCount, 0)
        XCTAssertEqual(result.plan, plan)
    }

    func testSanitize_AbsurdDuration_IsClampedToMax() {
        let plan = SuggestedTrainingPlan(motivation: "x", workouts: [workout(duration: 9999, trimp: 50)])
        let result = TrainingPlanSafetyValidator.sanitize(plan)
        XCTAssertEqual(result.clampedCount, 1)
        XCTAssertEqual(result.plan.workouts[0].suggestedDurationMinutes, TrainingPlanSafetyValidator.maxDurationMinutes)
        XCTAssertEqual(result.plan.workouts[0].targetTRIMP, 50, "in-range TRIMP must be left alone")
    }

    func testSanitize_NegativeValues_AreFlooredToZero() {
        let plan = SuggestedTrainingPlan(motivation: "x", workouts: [workout(duration: -30, trimp: -5)])
        let result = TrainingPlanSafetyValidator.sanitize(plan)
        XCTAssertEqual(result.clampedCount, 1)
        XCTAssertEqual(result.plan.workouts[0].suggestedDurationMinutes, 0)
        XCTAssertEqual(result.plan.workouts[0].targetTRIMP, 0)
    }

    func testSanitize_AbsurdTRIMP_IsClampedToMax() {
        let plan = SuggestedTrainingPlan(motivation: "x", workouts: [workout(duration: 60, trimp: 99999)])
        let result = TrainingPlanSafetyValidator.sanitize(plan)
        XCTAssertEqual(result.clampedCount, 1)
        XCTAssertEqual(result.plan.workouts[0].targetTRIMP, TrainingPlanSafetyValidator.maxTargetTRIMP)
    }

    func testSanitize_NilTRIMP_StaysNil() {
        let plan = SuggestedTrainingPlan(motivation: "x", workouts: [workout(duration: 60, trimp: nil)])
        let result = TrainingPlanSafetyValidator.sanitize(plan)
        XCTAssertEqual(result.clampedCount, 0)
        XCTAssertNil(result.plan.workouts[0].targetTRIMP)
    }

    func testSanitize_CountsOnlyAffectedWorkouts() {
        let plan = SuggestedTrainingPlan(motivation: "x", workouts: [
            workout(duration: 45, trimp: 50),      // ok
            workout(duration: 9999, trimp: 50),    // clamp
            workout(duration: 30, trimp: 99999)    // clamp
        ])
        let result = TrainingPlanSafetyValidator.sanitize(plan)
        XCTAssertEqual(result.clampedCount, 2)
    }

    func testSanitize_PreservesIdentityAndOverrideFields() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = SuggestedTrainingPlan(motivation: "x", workouts: [
            workout(duration: 9999, trimp: 50, id: id, scheduledDate: date, isSwapped: true)
        ])
        let result = TrainingPlanSafetyValidator.sanitize(plan)
        let w = result.plan.workouts[0]
        XCTAssertEqual(w.id, id)
        XCTAssertEqual(w.scheduledDate, date)
        XCTAssertTrue(w.isSwapped)
    }
}
