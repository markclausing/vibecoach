import Foundation
import HealthKit
import SwiftData
import os.log

// MARK: - Epic 32 Story 32.1: WorkoutSampleService
//
// Brengt drie verantwoordelijkheden samen:
//   1. `WorkoutSampleStore`: thread-safe opslag-laag (`@ModelActor`).
//   2. `WorkoutSampleIngestService`: HealthKit-fetch via `HKQuantitySeriesSampleQuery` + resampling naar 5s.
//   3. Per-workout idempotente flow: wipe + insert zodat hersyncs nooit duplicaten opleveren.

private let log = Logger(subsystem: "com.markclausing.aifitnesscoach", category: "WorkoutSamples")

// MARK: - Storage (ModelActor)

/// `@ModelActor` zorgt dat alle SwiftData-mutaties op een achtergrondcontext draaien.
/// Geen `@MainActor`-blokkades tijdens een 30-daagse re-sync van duizenden samples.
@ModelActor
actor WorkoutSampleStore {

    /// Idempotente vervanging: bestaande samples voor `workoutUUID` worden eerst gewist,
    /// daarna worden de nieuwe ingevoegd. Voorkomt dubbelingen bij re-syncs.
    func replaceSamples(_ samples: [WorkoutSample], forWorkoutUUID workoutUUID: UUID) throws {
        let predicate = #Predicate<WorkoutSample> { $0.workoutUUID == workoutUUID }
        let descriptor = FetchDescriptor<WorkoutSample>(predicate: predicate)
        let existing = try modelContext.fetch(descriptor)
        for sample in existing {
            modelContext.delete(sample)
        }
        for sample in samples {
            modelContext.insert(sample)
        }
        try modelContext.save()
    }

    /// Aantal opgeslagen samples voor een workout. Gebruikt door tests en als idempotentie-check.
    func sampleCount(forWorkoutUUID workoutUUID: UUID) throws -> Int {
        let predicate = #Predicate<WorkoutSample> { $0.workoutUUID == workoutUUID }
        let descriptor = FetchDescriptor<WorkoutSample>(predicate: predicate)
        return try modelContext.fetchCount(descriptor)
    }
}

// MARK: - Ingest

/// Haalt fysiologische tijdreeksdata op uit HealthKit en resamplet naar 5s-buckets.
final class WorkoutSampleIngestService {

    private let healthStore: HKHealthStore
    private let resampler: SampleResampler

    init(healthStore: HKHealthStore = HKHealthStore(), resampler: SampleResampler = SampleResampler()) {
        self.healthStore = healthStore
        self.resampler = resampler
    }

    /// Eén workout volledig ophalen, resamplen en idempotent opslaan via de store.
    /// Niet-beschikbare metrieken (bijv. power op een hardloop-workout) leveren stil `nil` op
    /// in plaats van een fout — dat is correct: niet elke sport meet alle vijf de signalen.
    func ingestSamples(for workout: HKWorkout, into store: WorkoutSampleStore) async throws {
        let start = workout.startDate
        let end   = workout.endDate

        // Parallel ophalen — alle vijf de quantity types zijn onafhankelijk.
        async let heartRateSeries = fetchSeries(in: workout, identifier: .heartRate, unit: HKUnit(from: "count/min"))
        async let powerSeries     = fetchSeries(in: workout, identifier: .cyclingPower, unit: .watt())
        async let cadenceSeries   = fetchSeries(in: workout, identifier: cadenceIdentifier(for: workout), unit: HKUnit(from: "count/min"))
        async let speedSeries     = fetchSeries(in: workout, identifier: speedIdentifier(for: workout), unit: HKUnit.meter().unitDivided(by: .second()))
        async let distanceSeries  = fetchSeries(in: workout, identifier: distanceIdentifier(for: workout), unit: .meter())

        let hr       = try await heartRateSeries
        let power    = try await powerSeries
        let cadence  = try await cadenceSeries
        let speed    = try await speedSeries
        let distance = try await distanceSeries

        // Resample elk signaal volgens zijn fysiologisch correcte strategie.
        let hrBuckets       = resampler.resample(samples: hr,       from: start, to: end, strategy: .average)
        let powerBuckets    = resampler.resample(samples: power,    from: start, to: end, strategy: .average)
        let cadenceBuckets  = resampler.resample(samples: cadence,  from: start, to: end, strategy: .average)
        let speedBuckets    = resampler.resample(samples: speed,    from: start, to: end, strategy: .linearInterpolation)
        let distanceBuckets = resampler.resample(samples: distance, from: start, to: end, strategy: .deltaAccumulation)

        // Combineer per bucket-timestamp tot één WorkoutSample. We gebruiken de hartslag-buckets
        // als kanonieke grid — alle resamplers produceren identieke tijdstempels (zelfde start/end/bucketSize).
        let workoutUUID = workout.uuid
        let combined: [WorkoutSample] = hrBuckets.indices.compactMap { i in
            let timestamp = hrBuckets[i].timestamp
            let hrValue   = hrBuckets[i].value
            let pwValue   = powerBuckets.indices.contains(i)    ? powerBuckets[i].value    : nil
            let cdValue   = cadenceBuckets.indices.contains(i)  ? cadenceBuckets[i].value  : nil
            let spValue   = speedBuckets.indices.contains(i)    ? speedBuckets[i].value    : nil
            let dsValue   = distanceBuckets.indices.contains(i) ? distanceBuckets[i].value : nil

            // Sla buckets zonder enige meting niet op — bespaart storage en houdt queries scherp.
            if hrValue == nil && pwValue == nil && cdValue == nil && spValue == nil && dsValue == nil {
                return nil
            }
            return WorkoutSample(
                workoutUUID: workoutUUID,
                timestamp: timestamp,
                heartRate: hrValue,
                speed: spValue,
                power: pwValue,
                cadence: cdValue,
                distance: dsValue
            )
        }

        log.info("Ingested \(combined.count, privacy: .public) samples for workout \(workoutUUID, privacy: .public)")
        try await store.replaceSamples(combined, forWorkoutUUID: workoutUUID)
    }

    // MARK: Private — HealthKit fetch

    /// Haalt alle (quantity, datum)-paren binnen het workout-window op via `HKQuantitySeriesSampleQuery`.
    /// Werkt zowel op series-samples (Apple Watch beat-to-beat HR) als op losse samples.
    /// Retourneert een lege array bij niet-ondersteunde types of ontbrekende toestemming — geen fout.
    private func fetchSeries(in workout: HKWorkout,
                             identifier: HKQuantityTypeIdentifier?,
                             unit: HKUnit) async throws -> [TimedValue] {
        guard let identifier, let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate,
                                                    end: workout.endDate,
                                                    options: .strictStartDate)

        // Stap 1: haal alle parent quantity samples binnen het workout-window op.
        let parentSamples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType,
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        guard !parentSamples.isEmpty else { return [] }

        // Stap 2: per parent sample de series-ticks ophalen. Voor non-series samples krijg je één tick per call.
        var collected: [TimedValue] = []
        for parent in parentSamples {
            let ticks = try await fetchSeriesTicks(for: parent, unit: unit)
            collected.append(contentsOf: ticks)
        }
        return collected
    }

    private func fetchSeriesTicks(for sample: HKQuantitySample, unit: HKUnit) async throws -> [TimedValue] {
        try await withCheckedThrowingContinuation { continuation in
            var buffer: [TimedValue] = []
            var didResume = false
            // iOS 26 SDK biedt alleen nog `init(sample:quantityHandler:)` — vijf-arg handler met `Date?`.
            let query = HKQuantitySeriesSampleQuery(sample: sample) { _, quantity, date, done, error in
                if didResume { return }
                if let error {
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }
                if let quantity, let date {
                    buffer.append(TimedValue(timestamp: date, value: quantity.doubleValue(for: unit)))
                }
                if done {
                    didResume = true
                    continuation.resume(returning: buffer)
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: Sport-specifieke quantity-type-keuzes

    /// Distance-type hangt af van de workout: `running`, `cycling`, `swimming` of nil voor types zonder afstand.
    private func distanceIdentifier(for workout: HKWorkout) -> HKQuantityTypeIdentifier? {
        switch workout.workoutActivityType {
        case .running, .walking, .hiking:
            return .distanceWalkingRunning
        case .cycling:
            return .distanceCycling
        case .swimming:
            return .distanceSwimming
        default:
            return nil
        }
    }

    /// Speed-type — alleen `runningSpeed` is breed beschikbaar. Voor andere sporten leiden we
    /// snelheid in een latere story af uit afstand-delta. Voor nu: nil → geen speed-samples.
    private func speedIdentifier(for workout: HKWorkout) -> HKQuantityTypeIdentifier? {
        switch workout.workoutActivityType {
        case .running:
            return .runningSpeed
        default:
            return nil
        }
    }

    /// Cadence-type — `cyclingCadence` voor fietsen, `runningStrideLength` heeft geen cadans dus we
    /// laten running-cadence (nog) leeg. Story 32.x kan dit uitbreiden.
    private func cadenceIdentifier(for workout: HKWorkout) -> HKQuantityTypeIdentifier? {
        switch workout.workoutActivityType {
        case .cycling:
            return .cyclingCadence
        default:
            return nil
        }
    }
}
