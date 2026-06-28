import Foundation

/// Epic #62 stories 62.3 + 62.5 — pure-Swift mapping of raw permission / background-engine
/// facts to a display status for the Settings "Permissions & background" overview.
///
/// AppStorage/framework-free (§6): the View/service reads the framework state (HealthKit
/// authorization, `UNAuthorizationStatus`, the persisted engine flags) and passes plain
/// values; this type owns only the decision logic so it is unit-testable. The View maps the
/// returned levels to icon/colour/copy and the "Open Settings" action.
enum PermissionStatusEvaluator {

    /// How a user-grantable permission stands. `partial` covers HealthKit's quirk where we
    /// asked but read nothing back (HealthKit deliberately hides read-grant state).
    enum AccessLevel: Equatable {
        case granted        // working
        case partial        // asked, but data isn't coming through — check Apple Health
        case denied         // explicitly refused
        case notRequested   // never asked
    }

    /// Whether a background engine (A = workout trigger, B = daily check) is operating.
    enum EngineStatus: Equatable {
        case active
        case failed         // setup/registration returned an error
        case inactive       // not set up (e.g. HealthKit not granted, or never started)
    }

    /// HealthKit status for the overview row. Read authorization can't be read back reliably,
    /// so we combine two honest signals: whether the critical types were ever asked
    /// (`anyCriticalNotDetermined`), and the last historical-sync workout count (Epic #38's
    /// `vibecoach_lastHKWorkoutsCount`) — asked-but-zero means the grant likely didn't stick.
    static func healthKitLevel(available: Bool,
                               anyCriticalNotDetermined: Bool,
                               lastWorkoutCount: Int?) -> AccessLevel {
        guard available else { return .denied }
        if anyCriticalNotDetermined { return .notRequested }
        if let count = lastWorkoutCount, count == 0 { return .partial }
        return .granted
    }

    /// Notification status from the three mutually-exclusive `UNAuthorizationStatus` buckets the
    /// View collapses into (authorized/provisional/ephemeral → authorized).
    static func notificationLevel(authorized: Bool, denied: Bool) -> AccessLevel {
        if authorized { return .granted }
        if denied { return .denied }
        return .notRequested
    }

    /// Engine A (HKObserverQuery + background delivery) — needs HealthKit; a stored
    /// background-delivery error means it failed to arm.
    static func engineAStatus(healthKitGranted: Bool,
                              backgroundDeliveryActive: Bool,
                              hasError: Bool) -> EngineStatus {
        guard healthKitGranted else { return .inactive }
        if hasError { return .failed }
        return backgroundDeliveryActive ? .active : .inactive
    }

    /// Engine B (daily BGAppRefreshTask) — a stored scheduling error means submit() threw.
    static func engineBStatus(scheduled: Bool, hasError: Bool) -> EngineStatus {
        if hasError { return .failed }
        return scheduled ? .active : .inactive
    }
}
