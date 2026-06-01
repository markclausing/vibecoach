import Foundation
import HealthKit
import SwiftData

/// SPRINT 7.4 - New service for asynchronously syncing historical workouts directly from Apple HealthKit.
actor HealthKitSyncService {
    private let healthKitManager: HealthKitManager
    private let physiologicalCalculator: PhysiologicalCalculatorProtocol

    init(healthKitManager: HealthKitManager = HealthKitManager(),
         physiologicalCalculator: PhysiologicalCalculatorProtocol = PhysiologicalCalculator()) {
        self.healthKitManager = healthKitManager
        self.physiologicalCalculator = physiologicalCalculator
    }

    /// Fetches 1 year (365 days) of historical workouts from HealthKit, computes TRIMP locally,
    /// and stores them as `ActivityRecord`s in the SwiftData context.
    /// - Parameter context: The context in which the synced data should be stored.
    /// - Returns: Number of HK workouts the query returned in the 365d window. Epic #38 Story 38.2
    ///   uses this count to trigger the "silent sync" banner on the Dashboard when
    ///   `count == 0 && workoutAuthStatus != .sharingAuthorized` — prevents the user from
    ///   walking around for days with an empty dashboard without knowing it's a permissions issue.
    @MainActor
    func syncHistoricalWorkouts(to context: ModelContext) async throws -> Int {
        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!

        // Epic 33 Story 33.1b: derive maxHR via the Tanaka formula + dateOfBirth.
        // Once per sync (not per workout) — the birth date doesn't change anyway.
        // On missing permission/data the classifier falls back to the 190 bpm default.
        let birthDate: Date? = {
            do {
                let dob = try healthKitManager.healthStore.dateOfBirthComponents()
                return Calendar.current.date(from: dob)
            } catch {
                return nil
            }
        }()
        let estimatedMaxHR = HeartRateZones.estimatedMaxHeartRate(birthDate: birthDate)
        let sessionClassifier = SessionClassifier(maxHeartRate: estimatedMaxHR)

        let now = Date()
        // Look back 365 days
        guard let oneYearAgo = Calendar.current.date(byAdding: .day, value: -365, to: now) else {
            throw FitnessDataError.networkError("Kan datum voor historie niet berekenen.")
        }

        // We don't filter on type; all workouts between 1 year ago and now are fetched
        let predicate = HKQuery.predicateForSamples(withStart: oneYearAgo, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        // Use withCheckedThrowingContinuation to safely bridge the asynchronous HealthKit query
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HealthKit historie: \(error.localizedDescription)"))
                    return
                }

                let results = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: results)
            }
            healthKitManager.healthStore.execute(query)
        }

        // Loop asynchronously through all found workouts to fetch heart rate (average, max) and resting HR
        // Local Set as an extra safety net: catches duplicates HealthKit returns itself
        // (same batch, same UUID) — `smartInsert` does the DB-side dedupe for us.
        var seenWorkoutIds = Set<String>()

        for workout in workouts {
            // Unique ID based on the HealthKit UUID
            let workoutId = workout.uuid.uuidString

            // In-batch UUID dedupe: HealthKit can return the same workout twice
            // within one query (Watch + iPhone). `smartInsert` doesn't see unsaved
            // records, so this layer stays necessary to prevent duplicate inserts within one run.
            guard seenWorkoutIds.insert(workoutId).inserted else {
                AppLoggers.fitnessDataService.debug("Sync: HealthKit UUID \(workoutId, privacy: .private) al verwerkt in deze batch — overgeslagen")
                continue
            }

            let sport = SportCategory.from(hkType: workout.workoutActivityType.rawValue)

            var avgHR: Double?
            var maxHR: Double = 0
            var restHR: Double = 60 // Default value as fallback

            do {
                // Fetch the raw samples for this workout (reusing the function from HealthKitManager isn't directly available via public scope here; we either do the queries explicitly or add a helper. Since we already have the manager, we could in theory make it public there, or rewrite the call briefly).
                // To avoid calling private methods of the manager, we use a custom fetch
                let hrSamples = try await fetchHeartRateSamples(for: workout, quantityType: heartRateType)
                let heartRateData = hrSamples.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }

                if !heartRateData.isEmpty {
                    avgHR = heartRateData.reduce(0, +) / Double(heartRateData.count)
                    maxHR = heartRateData.max() ?? 0
                }

                // Fetch the resting heart rate on the day of the workout (simplified approach)
                restHR = try await fetchRestingHeartRate(near: workout.startDate, quantityType: restingHeartRateType)
            } catch {
                AppLoggers.fitnessDataService.error("Kon geen HR data ophalen voor workout. Fout: \(error.localizedDescription, privacy: .public)")
            }

            // Compute TRIMP (or use nil if no heart rate was measured)
            let calcTSS = await physiologicalCalculator.calculateTSS(durationInSeconds: workout.duration, averageHeartRate: avgHR ?? 0, maxHeartRate: maxHR, restingHeartRate: restHR)
            let trimp = (avgHR != nil) ? calcTSS : nil

            // Map the HealthKit Workout to our ActivityRecord (SwiftData Model)
            // Use the human SportCategory name so the coach sees "wandeling", not "HealthKit 52"
            // `sport` is already declared based on workoutActivityType (Layer 1b above)
            let recordName = sport.workoutName.prefix(1).uppercased() + sport.workoutName.dropFirst()

            // Epic 33 Story 33.1b: propose a sessionType based on avg HR + duration.
            // HealthKit records have no rich title — the keyword strategy usually yields
            // nothing here; the classifier automatically falls back to the avg-HR route.
            // On a later DeepSync (samples) this type can be reclassified;
            // for 33.1b we use only the at-ingest signal.
            let suggestedSessionType = sessionClassifier.classify(
                samples: nil,
                averageHeartRate: avgHR,
                durationSeconds: Int(workout.duration),
                title: nil
            )

            // Epic 49: read weather metadata from HKWorkout. During outdoor workouts
            // the iPhone writes `HKMetadataKeyWeatherTemperature` (HKQuantity in
            // degrees Fahrenheit) and `HKMetadataKeyWeatherHumidity` (HKQuantity in
            // percent). For records without metadata both stay nil — the coach then
            // falls back to generic assumptions instead of asking about heat.
            let (weatherTempC, weatherHumidity) = Self.extractWeather(from: workout.metadata)

            let record = ActivityRecord(
                id: workoutId,
                name: recordName,
                distance: workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0,
                movingTime: Int(workout.duration),
                averageHeartrate: avgHR,
                sportCategory: SportCategory.from(hkType: workout.workoutActivityType.rawValue),
                startDate: workout.startDate,
                trimp: trimp,
                sessionType: suggestedSessionType,
                temperatureCelsius: weatherTempC,
                humidityPercent: weatherHumidity
            )

            // Epic 41.4: smart-insert protects against cross-source impoverishment.
            // A Strava record with deviceWatts that's already in the DB within ±5s stays;
            // a poorer HK record no longer overwrites it.
            let result = try ActivityDeduplicator.smartInsert(record, into: context)
            switch result {
            case .skippedExistingRicher:
                AppLoggers.fitnessDataService.debug("Sync: HK-workout \(workoutId, privacy: .private) [\(sport.rawValue, privacy: .public)] overgeslagen — bestaand record is rijker (Epic 41.4)")
            case .replaced:
                AppLoggers.fitnessDataService.debug("Sync: bestaand armer record vervangen door HK-workout \(workoutId, privacy: .private)")
            case .inserted, .skippedSameSource:
                break
            }
        }

        try context.save()
        return workouts.count
    }

    // Helper for raw samples within this actor domain
    private func fetchHeartRateSamples(for workout: HKWorkout, quantityType: HKQuantityType) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthKitManager.healthStore.execute(query)
        }
    }

    // Helper for resting heart rate
    private func fetchRestingHeartRate(near date: Date, quantityType: HKQuantityType) async throws -> Double {
        // Fetch the RHR in a window of 30 days preceding the activity
        guard let pastDate = Calendar.current.date(byAdding: .month, value: -1, to: date) else { return 60.0 }
        let predicate = HKQuery.predicateForSamples(withStart: pastDate, end: date, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if error != nil {
                    continuation.resume(returning: 60.0) // Fallback on error
                    return
                }

                guard let latestSample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: 60.0) // Fallback if no data
                    return
                }

                let restingBpm = latestSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: restingBpm)
            }
            healthKitManager.healthStore.execute(query)
        }
    }

    // MARK: - Weather metadata (Epic 49)

    /// Extracts temperature (in degrees Celsius) and humidity (%) from an
    /// HKWorkout metadata dictionary. During outdoor workouts Apple stores these
    /// as HKQuantity values in degF and % respectively. Returns (nil, nil) when
    /// the keys are absent (Strava-only ingest, indoor workout, old iOS).
    /// Static + internal for unit-test visibility.
    static func extractWeather(from metadata: [String: Any]?) -> (temperatureCelsius: Double?, humidityPercent: Double?) {
        guard let metadata else { return (nil, nil) }
        var tempC: Double?
        var humidity: Double?

        if let q = metadata[HKMetadataKeyWeatherTemperature] as? HKQuantity {
            // Apple uses degF in metadata; convert explicitly to Celsius
            // so we don't depend on the user's locale.
            if q.is(compatibleWith: .degreeCelsius()) {
                tempC = q.doubleValue(for: .degreeCelsius())
            } else if q.is(compatibleWith: .degreeFahrenheit()) {
                tempC = q.doubleValue(for: .degreeFahrenheit())
                tempC = tempC.map { ($0 - 32) * 5 / 9 }
            }
        }
        if let q = metadata[HKMetadataKeyWeatherHumidity] as? HKQuantity,
           q.is(compatibleWith: .percent()) {
            // HK provides percent as 0–1 or 0–100 depending on source — normalize
            // to 0–100 for the coach prompt and UI formatting.
            let raw = q.doubleValue(for: .percent())
            humidity = raw <= 1.0 ? raw * 100 : raw
        }
        return (tempC, humidity)
    }
}
