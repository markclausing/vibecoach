import HealthKit

// MARK: - Epic 38 Story 38.2: HealthKit sync-status evaluator
//
// Pure-Swift decision logic for the "silent sync" banner on the Dashboard.
// By isolating the rule as a testable static function, we don't need to build an
// `HKHealthStore` mock to validate when the banner appears
// — the caller passes the two inputs and gets a Bool back. No UI,
// AppStorage or HealthKit-query dependency.
//
// Strict condition (38.2): banner only when there are 0 workouts in the 365d
// window AND the workout type is not explicitly `.sharingAuthorized`.
// Partial authorization (workouts yes, heart rate no) is deliberately out of
// scope — those degrade visibly on their own in empty HR charts (Epic 32/40).
// A separate banner per missing type would make the dashboard too busy.

enum HealthKitSyncStatusEvaluator {

    /// Returns `true` when we should show the "check permissions" banner.
    /// Logic: 0 workouts in the window and workout auth status not
    /// `sharingAuthorized` (i.e. `denied` or `notDetermined`).
    /// - Parameters:
    ///   - workoutCount: number of workouts the last sync returned from HK
    ///     in the 365d window (cached via AppStorage by `AppTabHostView`).
    ///   - workoutAuthStatus: `HKHealthStore.authorizationStatus(for:)` on
    ///     `HKObjectType.workoutType()` at the moment of banner render.
    static func shouldWarn(workoutCount: Int,
                           workoutAuthStatus: HKAuthorizationStatus) -> Bool {
        workoutCount == 0 && workoutAuthStatus != .sharingAuthorized
    }
}
