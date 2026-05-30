import HealthKit

// MARK: - Epic 38 Story 38.1: HealthKit permission types (single source of truth)
//
// Central definition of all HealthKit types the coach uses. Prevents
// drift between "what we request" (`requestAuthorization` call) and "what we check
// for `.notDetermined` status" (foreground-return retrigger). Before Epic 38 the
// type sets lived as inline arrays in two different methods on `HealthKitManager`,
// so a missed type only surfaced as a runtime error ("Authorization not
// determined" on the first query).
//
// Cardio Fitness = Apple's term for `HKQuantityTypeIdentifier.vo2Max` — no
// separate identifier needed. `activeEnergyBurned` was added in Epic 38.1
// because it was missing from the old list but is consumed by the
// coaching context.

enum HealthKitPermissionTypes {

    /// Read types: all data the coach analyses (workouts, HR, HRV, sleep,
    /// VO2Max/Cardio Fitness, active energy, sample streams from Epic 32).
    static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType.quantityType(forIdentifier: .heartRate)!,
        HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
        HKQuantityType.quantityType(forIdentifier: .vo2Max)!,
        HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKQuantityType.quantityType(forIdentifier: .stepCount)!,
        HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
        HKQuantityType.quantityType(forIdentifier: .height)!,
        HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
        HKObjectType.characteristicType(forIdentifier: .biologicalSex)!,
        // Epic 32 — workout sample streams
        HKQuantityType.quantityType(forIdentifier: .cyclingPower)!,
        HKQuantityType.quantityType(forIdentifier: .cyclingCadence)!,
        HKQuantityType.quantityType(forIdentifier: .runningSpeed)!,
        HKQuantityType.quantityType(forIdentifier: .distanceCycling)!,
        HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKQuantityType.quantityType(forIdentifier: .distanceSwimming)!
    ]

    /// Write types: only body measurements for the Two-Way Sync (Epic 24).
    static let writeTypes: Set<HKSampleType> = [
        HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
        HKQuantityType.quantityType(forIdentifier: .height)!
    ]

    /// Critical types whose missing permission causes a "silent failure"
    /// (no workouts → empty dashboard → no coaching). Used by the
    /// foreground-return retrigger to only show a prompt when something
    /// genuinely goes wrong — not for optional types like `bodyMass`.
    static let critical: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType.quantityType(forIdentifier: .heartRate)!,
        HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    ]

    /// Returns all critical types whose status is `.notDetermined`. An empty
    /// set means: all critical types are already explicit (`sharingAuthorized`
    /// or `sharingDenied`) — no retrigger needed.
    static func criticalNotDetermined(in store: HKHealthStore) -> Set<HKObjectType> {
        critical.filter { store.authorizationStatus(for: $0) == .notDetermined }
    }
}
