import XCTest
import HealthKit
@testable import AIFitnessCoach

/// Epic 38 Story 38.2 — `HealthKitSyncStatusEvaluator`.
/// Borgt de strikte banner-conditie: alleen tonen bij 0 workouts in het 365d-
/// venster + workout-type-status níet `.sharingAuthorized`. Gedeeltelijke
/// toestemming (workouts wel, HR niet) is buiten scope.
final class HealthKitSyncStatusEvaluatorTests: XCTestCase {

    func testNoWorkoutsAndNotDetermined_ShouldWarn() {
        XCTAssertTrue(HealthKitSyncStatusEvaluator.shouldWarn(
            workoutCount: 0,
            workoutAuthStatus: .notDetermined))
    }

    func testNoWorkoutsAndDenied_ShouldWarn() {
        XCTAssertTrue(HealthKitSyncStatusEvaluator.shouldWarn(
            workoutCount: 0,
            workoutAuthStatus: .sharingDenied))
    }

    func testNoWorkoutsButAuthorized_ShouldNotWarn() {
        // Edge: gebruiker heeft toestemming gegeven maar simpelweg geen workouts
        // in 365d (nieuwe-Watch, eerste week-gebruik). Geen banner — dat zou
        // false-positive zijn.
        XCTAssertFalse(HealthKitSyncStatusEvaluator.shouldWarn(
            workoutCount: 0,
            workoutAuthStatus: .sharingAuthorized))
    }

    func testHasWorkouts_ShouldNotWarn_RegardlessOfStatus() {
        // Sanity: zodra er ook maar één workout terugkomt, geen banner — de
        // sync werkt blijkbaar voldoende. Andere ontbrekende types (HR, HRV)
        // manifesteren zich vanzelf in lege grafieken (38.2 scope-grens).
        for status: HKAuthorizationStatus in [.notDetermined, .sharingDenied, .sharingAuthorized] {
            XCTAssertFalse(HealthKitSyncStatusEvaluator.shouldWarn(
                workoutCount: 1,
                workoutAuthStatus: status),
                          "workoutCount > 0 mag nooit een banner triggeren (status: \(status.rawValue))")
        }
    }
}
