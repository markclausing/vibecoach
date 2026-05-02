import HealthKit

// MARK: - Epic 38 Story 38.1: HealthKit-permissie-typen (single source of truth)
//
// Centrale definitie van álle HealthKit-types die de coach gebruikt. Voorkomt
// drift tussen "wat we vragen" (`requestAuthorization`-call) en "wat we checken
// op `.notDetermined`-status" (foreground-return-retrigger). Vóór Epic 38 stonden
// de typesets als inline-arrays in twee verschillende methodes op `HealthKitManager`,
// waardoor een gemiste type alleen runtime-error opleverde ("Authorization not
// determined" bij de eerste query).
//
// Cardio Fitness = Apple's term voor `HKQuantityTypeIdentifier.vo2Max` — geen
// aparte identifier nodig. `activeEnergyBurned` is in Epic 38.1 toegevoegd
// omdat het ontbrak in de oude lijst maar wel door de coaching-context wordt
// geconsumeerd.

enum HealthKitPermissionTypes {

    /// Read-types: alle data die de coach analyseert (workouts, HR, HRV, slaap,
    /// VO2Max/Cardio Fitness, active energy, sample-streams uit Epic 32).
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
        // Epic 32 — workout-sample-streams
        HKQuantityType.quantityType(forIdentifier: .cyclingPower)!,
        HKQuantityType.quantityType(forIdentifier: .cyclingCadence)!,
        HKQuantityType.quantityType(forIdentifier: .runningSpeed)!,
        HKQuantityType.quantityType(forIdentifier: .distanceCycling)!,
        HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKQuantityType.quantityType(forIdentifier: .distanceSwimming)!
    ]

    /// Write-types: alleen body-metingen voor de Two-Way Sync (Epic 24).
    static let writeTypes: Set<HKSampleType> = [
        HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
        HKQuantityType.quantityType(forIdentifier: .height)!
    ]

    /// Cruciale types waarvan ontbrekende toestemming een "stille faal" oplevert
    /// (geen workouts → leeg dashboard → geen coaching). Wordt gebruikt door de
    /// foreground-return-retrigger om alleen prompt te tonen wanneer er écht
    /// iets misgaat — niet voor optionele types zoals `bodyMass`.
    static let critical: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType.quantityType(forIdentifier: .heartRate)!,
        HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    ]

    /// Returns alle critical types waarvan de status `.notDetermined` is. Lege
    /// set betekent: alle critical types zijn al expliciet (`sharingAuthorized`
    /// of `sharingDenied`) — geen retrigger nodig.
    static func criticalNotDetermined(in store: HKHealthStore) -> Set<HKObjectType> {
        critical.filter { store.authorizationStatus(for: $0) == .notDetermined }
    }
}
