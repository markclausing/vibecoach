import Foundation
import HealthKit

// swiftlint:disable force_unwrapping
// Epic 65.6 force-unwrap audit: the `!`s in this HealthKit-boundary file fall into
// two never-nil idioms — (1) `HKObjectType.quantityType(forIdentifier:)` for a
// *built-in* HealthKit identifier (Apple guarantees non-nil for its own
// identifiers), and (2) `Calendar.current.date(byAdding:...)` with fixed
// hour/day/month offsets on a valid `startOfDay` date (never nil in the Gregorian
// calendar). Both are audited as benign; the rule is disabled file-wide so the
// query boilerplate stays readable instead of carrying ~19 inline suppressions.

/// Manages the Apple HealthKit integration and permissions
final class HealthKitManager: @unchecked Sendable {

    /// Epic #31 Sprint 31.2: Shared singleton so the onboarding flow and
    /// background services share the same instance. Existing call sites that use
    /// `HealthKitManager()` keep working (the init is still available).
    static let shared = HealthKitManager()

    // Lazy: HKHealthStore is created only on first real use, not at app start.
    // This shortens the launch time significantly.
    lazy var healthStore: HKHealthStore = HKHealthStore()

    /// Epic #31 Sprint 31.2 + Epic #38 Story 38.1: Permission request for the
    /// onboarding flow. Now requests the **complete** set of HK types the coach
    /// uses (see `HealthKitPermissionTypes.readTypes`) so a user doesn't
    /// accidentally forget a subset — iOS shows one permission sheet with all
    /// categories. Before this change, 38.1 onboarding requested only 4 types;
    /// the rest was retrieved later via `requestAuthorization`, which led to
    /// silent failures when iOS had partially reset permissions after a reinstall.
    ///
    /// - Returns: `true` if the HealthKit dialog was presented successfully and
    ///   iOS registered an answer. Note: this says nothing about per-type
    ///   permission — HealthKit doesn't reveal read access.
    /// - Throws: `FitnessDataError.networkError` when HealthKit isn't available
    ///   on the device.
    @discardableResult
    func requestOnboardingPermissions() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw FitnessDataError.networkError("HealthKit is niet beschikbaar op dit apparaat.")
        }

        // Epic #38 Story 38.1: complete set in one permission sheet (single
        // source of truth in `HealthKitPermissionTypes.readTypes`).
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: HealthKitPermissionTypes.writeTypes,
                                             read: HealthKitPermissionTypes.readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    /// Epic #38 Story 38.1: foreground-return retrigger. Requests permission
    /// only for the **critical** types whose status is `.notDetermined`.
    /// Existing users with `.sharingAuthorized`/`.sharingDenied` see no
    /// unexpected prompt — iOS only shows a dialog when there's actually
    /// something to decide. Empty set → no-op (no prompt, no exception).
    @discardableResult
    func requestPermissionsForCriticalNotDetermined() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let notDetermined = HealthKitPermissionTypes.criticalNotDetermined(in: healthStore)
        guard !notDetermined.isEmpty else { return true }

        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: nil, read: notDetermined) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    /// Requests permission from the user to read the required health data.
    /// Epic #38 Story 38.1: types now come from `HealthKitPermissionTypes` so
    /// onboarding and this "expand later" call request the same set — no more
    /// drift between "what we ask" and "what we check on `.notDetermined`".
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, FitnessDataError.networkError("HealthKit is niet beschikbaar op dit apparaat."))
            return
        }

        healthStore.requestAuthorization(toShare: HealthKitPermissionTypes.writeTypes,
                                         read: HealthKitPermissionTypes.readTypes) { success, error in
            completion(success, error)
        }
    }

    /// Computes the average weekly training volume (in seconds) directly from HealthKit.
    /// Doesn't query SwiftData — always current data.
    func fetchAverageWeeklyDurationSeconds(weeks: Int = 4) async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let now = Date()
        guard let startDate = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: now) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let workouts = samples as? [HKWorkout] ?? []
                let totalSeconds = Int(workouts.reduce(0.0) { $0 + $1.duration })
                continuation.resume(returning: totalSeconds / max(1, weeks))
            }
            healthStore.execute(query)
        }
    }

    /// Fetches the most recent workout from HealthKit (regardless of type)
    /// Including duration, heart-rate statistics and raw heart-rate samples.
    func fetchLatestWorkoutDetails() async throws -> WorkoutDetails? {
        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!

        // No specific predicate anymore, we want the latest workout of any type
        let predicate: NSPredicate? = nil

        // Sort on end date to actually take the most recently finished activity
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
                guard let self = self else {
                    continuation.resume(throwing: FitnessDataError.networkError("Manager deallocated"))
                    return
                }

                if let error = error {
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HealthKit workout: \(error.localizedDescription)"))
                    return
                }

                guard let workout = samples?.first as? HKWorkout else {
                    continuation.resume(returning: nil)
                    return
                }

                Task {
                    do {
                        // Fetch the raw heart-rate samples for this workout
                        let hrSamples = try await self.fetchHeartRateSamples(for: workout, quantityType: heartRateType)
                        let heartRateData = hrSamples.map { HeartRateSample(timestamp: $0.startDate, bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }

                        // Compute avg and max from the raw samples
                        let avgHR = heartRateData.isEmpty ? 0 : heartRateData.reduce(0) { $0 + $1.bpm } / Double(heartRateData.count)
                        let maxHR = heartRateData.max(by: { $0.bpm < $1.bpm })?.bpm ?? 0

                        // Fetch the latest resting heart rate
                        let restingHR = try await self.fetchLatestRestingHeartRate(quantityType: restingHeartRateType)

                        let sport = SportCategory.from(hkType: workout.workoutActivityType.rawValue)
                        let workoutName = sport.workoutName.prefix(1).uppercased() + sport.workoutName.dropFirst()
                        let details = WorkoutDetails(
                            name: String(workoutName),
                            startDate: workout.startDate,
                            duration: workout.duration,
                            averageHeartRate: avgHR,
                            maxHeartRate: maxHR,
                            restingHeartRate: restingHR,
                            heartRateSamples: heartRateData
                        )
                        continuation.resume(returning: details)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            healthStore.execute(query)
        }
    }

    /// Fetches workouts from the past specific number of days
    func fetchRecentWorkouts(days: Int) async throws -> [WorkoutDetails] {
        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!

        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
                guard let self = self else {
                    continuation.resume(throwing: FitnessDataError.networkError("Manager deallocated"))
                    return
                }

                if let error = error {
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HealthKit workouts: \(error.localizedDescription)"))
                    return
                }

                guard let workoutSamples = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                Task {
                    do {
                        var recentWorkouts: [WorkoutDetails] = []

                        let restingHR = try await self.fetchLatestRestingHeartRate(quantityType: restingHeartRateType)

                        for workout in workoutSamples {
                            let hrSamples = try await self.fetchHeartRateSamples(for: workout, quantityType: heartRateType)
                            let heartRateData = hrSamples.map { HeartRateSample(timestamp: $0.startDate, bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }

                            let avgHR = heartRateData.isEmpty ? 0 : heartRateData.reduce(0) { $0 + $1.bpm } / Double(heartRateData.count)
                            let maxHR = heartRateData.max(by: { $0.bpm < $1.bpm })?.bpm ?? 0

                            let wSport = SportCategory.from(hkType: workout.workoutActivityType.rawValue)
                            let wName = wSport.workoutName.prefix(1).uppercased() + wSport.workoutName.dropFirst()
                            let details = WorkoutDetails(
                                name: String(wName),
                                startDate: workout.startDate,
                                duration: workout.duration,
                                averageHeartRate: avgHR,
                                maxHeartRate: maxHR,
                                restingHeartRate: restingHR,
                                heartRateSamples: heartRateData
                            )
                            recentWorkouts.append(details)
                        }

                        continuation.resume(returning: recentWorkouts)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            healthStore.execute(query)
        }
    }

    /// Helper to fetch the raw heart-rate samples belonging to a specific workout.
    private func fetchHeartRateSamples(for workout: HKWorkout, quantityType: HKQuantityType) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HR samples: \(error.localizedDescription)"))
                    return
                }

                let hrSamples = (samples as? [HKQuantitySample]) ?? []
                continuation.resume(returning: hrSamples)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Epic 14: Readiness Score Data

    /// Fetches the average HRV (SDNN, in milliseconds) of the past night.
    /// When `sleepStart`/`sleepEnd` are provided, only the HRV within that exact
    /// sleep session is used — post-workout drops are thus definitively excluded.
    /// Without a sleep window the query falls back to the fixed night window
    /// (yesterday 18:00 → today 14:00).
    /// - Returns: Average HRV in ms, or nil if no measurement is available.
    func fetchRecentHRV(sleepStart: Date? = nil, sleepEnd: Date? = nil) async throws -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            AppLoggers.athleticProfileManager.error("[HRV] HKQuantityType voor heartRateVariabilitySDNN niet beschikbaar")
            return nil
        }

        // Use the exact sleep window if known; otherwise the fixed night window.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let defaultEnd   = calendar.date(byAdding: .hour, value: 14, to: today)!
        let yesterday    = calendar.date(byAdding: .day, value: -1, to: today)!
        let defaultStart = calendar.date(byAdding: .hour, value: 18, to: yesterday)!

        let windowStart = sleepStart ?? defaultStart
        let windowEnd   = sleepEnd   ?? defaultEnd

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        if sleepStart != nil {
            AppLoggers.athleticProfileManager.debug("[HRV] Query gestart — gekoppeld aan slaapvenster")
        } else {
            AppLoggers.athleticProfileManager.debug("[HRV] Query gestart — standaard nachtvenster: gisteren 18:00 → vandaag 14:00")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    AppLoggers.athleticProfileManager.error("[HRV] HealthKit fout: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HRV: \(error.localizedDescription)"))
                    return
                }

                guard let hrvSamples = samples as? [HKQuantitySample], !hrvSamples.isEmpty else {
                    AppLoggers.athleticProfileManager.debug("[HRV] Geen samples gevonden in afgelopen 48 uur — Watch mogelijk niet gedragen")
                    continuation.resume(returning: nil)
                    return
                }

                // Compute the average of all available measurements in the time window
                let unit = HKUnit.secondUnit(with: .milli)
                let totalHRV = hrvSamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
                let averageHRV = totalHRV / Double(hrvSamples.count)

                // HRV value is user-specific physiological data → private.
                AppLoggers.athleticProfileManager.info("[HRV] Data ontvangen: \(String(format: "%.1f", averageHRV), privacy: .private) ms (\(hrvSamples.count, privacy: .public) meting(en))")
                continuation.resume(returning: averageHRV)
            }
            healthStore.execute(query)
        }
    }

    /// Fetches the average HRV over the past `days` days as a personal baseline.
    /// Used by ReadinessCalculator to contextualize tonight's HRV.
    /// - Returns: Average HRV in ms over the given window, or nil if there's no data.
    func fetchHRVBaseline(days: Int = 7) async throws -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            AppLoggers.athleticProfileManager.error("[HRV-Baseline] HKQuantityType niet beschikbaar")
            return nil
        }

        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        AppLoggers.athleticProfileManager.debug("[HRV-Baseline] Query gestart — venster: \(days, privacy: .public) dagen")

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    AppLoggers.athleticProfileManager.error("[HRV-Baseline] HealthKit fout: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HRV baseline: \(error.localizedDescription)"))
                    return
                }

                guard let hrvSamples = samples as? [HKQuantitySample], !hrvSamples.isEmpty else {
                    AppLoggers.athleticProfileManager.debug("[HRV-Baseline] Geen samples gevonden in afgelopen \(days, privacy: .public) dagen")
                    continuation.resume(returning: nil)
                    return
                }

                let unit = HKUnit.secondUnit(with: .milli)
                let total = hrvSamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
                let average = total / Double(hrvSamples.count)

                // HRV baseline is user-specific physiological data → private.
                AppLoggers.athleticProfileManager.info("[HRV-Baseline] Data ontvangen: \(String(format: "%.1f", average), privacy: .private) ms (\(days, privacy: .public) dagen, \(hrvSamples.count, privacy: .public) meting(en))")
                continuation.resume(returning: average)
            }
            healthStore.execute(query)
        }
    }

    /// Computes the number of actually slept hours of the past night.
    /// Sums only `.asleepCore`, `.asleepDeep` and `.asleepREM` (iOS 16+ / watchOS 9+).
    /// This prevents double counting: on modern hardware Apple Watch writes the
    /// stage-specific samples, but some third-party sources also write a generic
    /// `.asleep` aggregate. By counting only the three stages we exclude both inBed
    /// and double counting. Falls back to `.asleep` (legacy) if no stage data is present.
    /// - Returns: Total sleep time in hours (e.g. 7.5), or nil if no data available.
    func fetchLastNightSleep() async throws -> Double? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            AppLoggers.athleticProfileManager.error("[Slaap] HKCategoryType voor sleepAnalysis niet beschikbaar")
            return nil
        }

        // Fixed night window: yesterday 18:00 to today 14:00.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let windowEnd = calendar.date(byAdding: .hour, value: 14, to: today)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let windowStart = calendar.date(byAdding: .hour, value: 18, to: yesterday)!

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        AppLoggers.athleticProfileManager.debug("[Slaap] Query gestart — venster: gisteren 18:00 → vandaag 14:00")

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    AppLoggers.athleticProfileManager.error("[Slaap] HealthKit fout: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen slaapdata: \(error.localizedDescription)"))
                    return
                }

                guard let sleepSamples = samples as? [HKCategorySample], !sleepSamples.isEmpty else {
                    AppLoggers.athleticProfileManager.debug("[Slaap] Geen samples gevonden in nachtvenster")
                    continuation.resume(returning: nil)
                    return
                }

                // Phase 1: try stage-specific values (watchOS 9+ / iOS 16+).
                // By counting ONLY these three we avoid double counting with legacy .asleep.
                let stageValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let stageSamples = sleepSamples.filter { stageValues.contains($0.value) }

                let totalSleepSeconds: Double
                if stageSamples.isEmpty {
                    // Phase 2 (fallback): older Apple Watch model — use the generic .asleep value.
                    let asleepValue: Int
                    if #available(iOS 16.0, *) {
                        asleepValue = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                    } else {
                        asleepValue = HKCategoryValueSleepAnalysis.asleep.rawValue
                    }
                    totalSleepSeconds = sleepSamples
                        .filter { $0.value == asleepValue }
                        .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                    AppLoggers.athleticProfileManager.debug("[Slaap] Geen stage-data — fallback naar generieke slaapwaarde")
                } else {
                    // Modern Apple Watch: sum Core + Deep + REM
                    totalSleepSeconds = stageSamples
                        .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                }

                guard totalSleepSeconds > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let totalSleepHours = totalSleepSeconds / 3600.0
                let hours = Int(totalSleepHours)
                let minutes = Int((totalSleepHours - Double(hours)) * 60)

                // Sleep hours are user-specific data → private.
                AppLoggers.athleticProfileManager.info("[Slaap] Afgelopen nacht: \(hours, privacy: .private)u \(minutes, privacy: .private)m (Core+Deep+REM = \(String(format: "%.2f", totalSleepHours), privacy: .private) uur)")
                continuation.resume(returning: totalSleepHours)
            }
            healthStore.execute(query)
        }
    }

    /// Epic 21 Sprint 2: Fetches the sleep stages of the past night.
    /// Returns nil if HealthKit isn't available or if there's no stage-specific data
    /// (e.g. an older Apple Watch model that only records the generic `.asleep` value).
    /// The returned `SleepStages` also contains `sessionStart`/`sessionEnd` — the exact
    /// boundaries of the sleep session — so the HRV query can hook into it seamlessly.
    func fetchSleepStages() async throws -> SleepStages? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            AppLoggers.athleticProfileManager.error("[Slaapfases] HKCategoryType niet beschikbaar")
            return nil
        }

        // Same fixed night window as fetchLastNightSleep(): yesterday 18:00 → today 14:00.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let windowEnd = calendar.date(byAdding: .hour, value: 14, to: today)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let windowStart = calendar.date(byAdding: .hour, value: 18, to: yesterday)!

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        AppLoggers.athleticProfileManager.debug("[Slaapfases] Query gestart — venster: gisteren 18:00 → vandaag 14:00")

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    AppLoggers.athleticProfileManager.error("[Slaapfases] HealthKit fout: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let sleepSamples = samples as? [HKCategorySample], !sleepSamples.isEmpty else {
                    AppLoggers.athleticProfileManager.debug("[Slaapfases] Geen samples gevonden")
                    continuation.resume(returning: nil)
                    return
                }

                // Filter on the three stage-specific values (watchOS 9+ / iOS 16+).
                let deepSamples = sleepSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
                let remSamples  = sleepSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue  }
                let coreSamples = sleepSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue }

                let deepSec = deepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let remSec  = remSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let coreSec = coreSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

                // If all stage-specific values are zero this is an older device.
                guard deepSec + remSec + coreSec > 0 else {
                    AppLoggers.athleticProfileManager.debug("[Slaapfases] Geen stage-specifieke data — ouder device")
                    continuation.resume(returning: nil)
                    return
                }

                // Sleep window: earliest start and latest end of the real sleep stages.
                // This window is passed to fetchRecentHRV() to exclude post-workout HRV.
                let allStageSamples = deepSamples + remSamples + coreSamples
                let sessionStart = allStageSamples.map { $0.startDate }.min()
                let sessionEnd   = allStageSamples.map { $0.endDate   }.max()

                let totalSec = deepSec + remSec + coreSec
                let stages = SleepStages(
                    deepMinutes: Int(deepSec  / 60),
                    remMinutes: Int(remSec   / 60),
                    coreMinutes: Int(coreSec  / 60),
                    totalMinutes: Int(totalSec / 60),
                    sessionStart: sessionStart,
                    sessionEnd: sessionEnd
                )

                // Sleep minutes are user-specific physiological data → private.
                AppLoggers.athleticProfileManager.info("[Slaapfases] Diep: \(stages.deepMinutes, privacy: .private)m · REM: \(stages.remMinutes, privacy: .private)m · Kern: \(stages.coreMinutes, privacy: .private)m · Ratio diep: \(String(format: "%.0f%%", stages.deepRatio * 100), privacy: .private)")
                continuation.resume(returning: stages)
            }
            healthStore.execute(query)
        }
    }

    /// Fetches the most recent VO2max estimate from HealthKit (ml/kg/min). Returns nil if no data.
    func fetchVO2Max() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return nil }
        let now = Date()
        let pastDate = Calendar.current.date(byAdding: .month, value: -6, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: pastDate, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let vo2 = sample.quantity.doubleValue(for: HKUnit(from: "ml/kg·min"))
                continuation.resume(returning: vo2)
            }
            healthStore.execute(query)
        }
    }

    /// Fetches the most recent resting heart rate from HealthKit. Returns nil if there's no measurement.
    func fetchRestingHeartRate() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        let now = Date()
        let pastDate = Calendar.current.date(byAdding: .month, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: pastDate, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: bpm)
            }
            healthStore.execute(query)
        }
    }

    /// Helper to fetch the most recent resting heart rate.
    private func fetchLatestRestingHeartRate(quantityType: HKQuantityType) async throws -> Double {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let now = Date()
        let pastDate = Calendar.current.date(byAdding: .month, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: pastDate, end: now, options: .strictEndDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen RHR: \(error.localizedDescription)"))
                    return
                }

                guard let latestSample = samples?.first as? HKQuantitySample else {
                    // Fall back to a default value if none was measured in the past month
                    continuation.resume(returning: 60.0)
                    return
                }

                let restingBpm = latestSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: restingBpm)
            }
            healthStore.execute(query)
        }
    }
}
// swiftlint:enable force_unwrapping
