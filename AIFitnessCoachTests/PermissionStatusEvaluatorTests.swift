import XCTest
@testable import AIFitnessCoach

/// Epic #62 stories 62.3 + 62.5 — permission/engine status mapping for the Settings overview.
final class PermissionStatusEvaluatorTests: XCTestCase {

    typealias Access = PermissionStatusEvaluator.AccessLevel
    typealias Engine = PermissionStatusEvaluator.EngineStatus

    // MARK: - HealthKit

    func testHealthKitUnavailableIsDenied() {
        XCTAssertEqual(PermissionStatusEvaluator.healthKitLevel(available: false, anyCriticalNotDetermined: false, lastWorkoutCount: 10), .denied)
    }

    func testHealthKitNotDeterminedIsNotRequested() {
        XCTAssertEqual(PermissionStatusEvaluator.healthKitLevel(available: true, anyCriticalNotDetermined: true, lastWorkoutCount: nil), .notRequested)
    }

    func testHealthKitAskedButZeroWorkoutsIsPartial() {
        XCTAssertEqual(PermissionStatusEvaluator.healthKitLevel(available: true, anyCriticalNotDetermined: false, lastWorkoutCount: 0), .partial)
    }

    func testHealthKitAskedWithWorkoutsIsGranted() {
        XCTAssertEqual(PermissionStatusEvaluator.healthKitLevel(available: true, anyCriticalNotDetermined: false, lastWorkoutCount: 12), .granted)
    }

    func testHealthKitAskedWithUnknownCountIsGranted() {
        // No cached count yet (nil) but the types were asked → treat as granted, not partial.
        XCTAssertEqual(PermissionStatusEvaluator.healthKitLevel(available: true, anyCriticalNotDetermined: false, lastWorkoutCount: nil), .granted)
    }

    // MARK: - Notifications

    func testNotificationAuthorized() {
        XCTAssertEqual(PermissionStatusEvaluator.notificationLevel(authorized: true, denied: false), .granted)
    }

    func testNotificationDenied() {
        XCTAssertEqual(PermissionStatusEvaluator.notificationLevel(authorized: false, denied: true), .denied)
    }

    func testNotificationNotDetermined() {
        XCTAssertEqual(PermissionStatusEvaluator.notificationLevel(authorized: false, denied: false), .notRequested)
    }

    // MARK: - Engine A

    func testEngineAInactiveWithoutHealthKit() {
        XCTAssertEqual(PermissionStatusEvaluator.engineAStatus(healthKitGranted: false, backgroundDeliveryActive: true, hasError: false), .inactive)
    }

    func testEngineAFailedOnError() {
        XCTAssertEqual(PermissionStatusEvaluator.engineAStatus(healthKitGranted: true, backgroundDeliveryActive: false, hasError: true), .failed)
    }

    func testEngineAActiveWhenDeliveryOn() {
        XCTAssertEqual(PermissionStatusEvaluator.engineAStatus(healthKitGranted: true, backgroundDeliveryActive: true, hasError: false), .active)
    }

    func testEngineAInactiveWhenGrantedButNotArmed() {
        XCTAssertEqual(PermissionStatusEvaluator.engineAStatus(healthKitGranted: true, backgroundDeliveryActive: false, hasError: false), .inactive)
    }

    // MARK: - Engine B

    func testEngineBActiveWhenScheduled() {
        XCTAssertEqual(PermissionStatusEvaluator.engineBStatus(scheduled: true, hasError: false), .active)
    }

    func testEngineBFailedOnError() {
        XCTAssertEqual(PermissionStatusEvaluator.engineBStatus(scheduled: false, hasError: true), .failed)
    }

    func testEngineBInactiveWhenNotScheduled() {
        XCTAssertEqual(PermissionStatusEvaluator.engineBStatus(scheduled: false, hasError: false), .inactive)
    }
}
