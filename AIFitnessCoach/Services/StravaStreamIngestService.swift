import Foundation

// MARK: - Epic 40 Story 40.3: StravaStreamIngestService
//
// Spiegelt de architectuur van `WorkoutSampleIngestService` (HealthKit) maar voor
// Strava-streams. Hergebruikt `SampleResampler` (story 32.1) voor de 5s-bucket-conversie
// en `WorkoutSampleStore` (`@ModelActor`) voor idempotente opslag.
//
// Ontwerp:
//   • Pure-Swift parsing van `StravaStreamSet` → `[TimedValue]` per signaal
//   • Resampler-strategieën identiek aan WorkoutSampleIngestService:
//       - average voor HR / power / cadence
//       - linear interpolation voor speed (velocity_smooth)
//   • Opslag via `replaceSamples(forWorkoutUUID:)` — idempotent, zelfde UUID
//     herschrijft de set
//   • UUID-koppeling via `UUID.deterministic(fromStravaID:)` — zelfde Strava-ID
//     levert altijd dezelfde foreign key

final class StravaStreamIngestService {

    private let resampler: SampleResampler

    init(resampler: SampleResampler = SampleResampler()) {
        self.resampler = resampler
    }

    /// Eén Strava-activity volledig ingesten: API-response converteren, resamplen en opslaan.
    /// - Parameters:
    ///   - streams: De StravaStreamSet zoals teruggegeven door `FitnessDataService.fetchActivityStreams`.
    ///   - activityID: Strava-activity-ID (string, zoals opgeslagen in `ActivityRecord.id`).
    ///   - startDate: Workout-startdatum, basis voor absolute timestamps (Strava `time`-stream is offset in seconden vanaf start).
    ///   - durationSeconds: Geplande duur — bepaalt het bucket-window-eind.
    ///   - store: De `WorkoutSampleStore` (`@ModelActor`) waar samples in landen.
    func ingestStreams(_ streams: StravaStreamSet,
                       activityID: String,
                       startDate: Date,
                       durationSeconds: Int,
                       into store: WorkoutSampleStore) async throws {

        let workoutUUID = UUID.deterministic(fromStravaID: activityID)
        let endDate = startDate.addingTimeInterval(TimeInterval(durationSeconds))

        // Strava's time-stream is een lineaire offset-array (seconden vanaf start).
        // Zonder time-stream kunnen we de andere data niet aan absolute tijdstippen koppelen.
        guard let timeStream = streams.time, !timeStream.data.isEmpty else {
            // Niets te ingesten — gracefully skip, geen error.
            return
        }

        let timestamps: [Date] = timeStream.data.map { offset in
            startDate.addingTimeInterval(offset)
        }

        let hrSamples       = Self.zip(stream: streams.heartrate,        with: timestamps)
        let powerSamples    = Self.zip(stream: streams.watts,            with: timestamps)
        let cadenceSamples  = Self.zip(stream: streams.cadence,          with: timestamps)
        let speedSamples    = Self.zip(stream: streams.velocity_smooth,  with: timestamps)

        let hrBuckets      = resampler.resample(samples: hrSamples,      from: startDate, to: endDate, strategy: .average)
        let powerBuckets   = resampler.resample(samples: powerSamples,   from: startDate, to: endDate, strategy: .average)
        let cadenceBuckets = resampler.resample(samples: cadenceSamples, from: startDate, to: endDate, strategy: .average)
        let speedBuckets   = resampler.resample(samples: speedSamples,   from: startDate, to: endDate, strategy: .linearInterpolation)

        // De HR-grid dient als kanonieke tijdas — alle resamplers produceren dezelfde
        // bucket-tijdstempels (zelfde start/end/bucketSize) dus indices matchen 1-op-1.
        // Bij ontbrekende HR-stream pakken we de eerste beschikbare grid.
        let canonicalGrid: [(timestamp: Date, value: Double?)] = !hrBuckets.isEmpty ? hrBuckets
            : !powerBuckets.isEmpty ? powerBuckets
            : !cadenceBuckets.isEmpty ? cadenceBuckets
            : speedBuckets

        let combined: [WorkoutSample] = canonicalGrid.indices.compactMap { i in
            let timestamp = canonicalGrid[i].timestamp
            let hrValue   = hrBuckets.indices.contains(i)      ? hrBuckets[i].value      : nil
            let pwValue   = powerBuckets.indices.contains(i)   ? powerBuckets[i].value   : nil
            let cdValue   = cadenceBuckets.indices.contains(i) ? cadenceBuckets[i].value : nil
            let spValue   = speedBuckets.indices.contains(i)   ? speedBuckets[i].value   : nil

            // Distance-stream is niet meegevraagd uit Strava (kan later via /streams als
            // distance-key). Voor nu: nil. WorkoutSampleService doet hetzelfde voor non-
            // running HK-records, dus consistent.
            if hrValue == nil && pwValue == nil && cdValue == nil && spValue == nil {
                return nil
            }
            return WorkoutSample(
                workoutUUID: workoutUUID,
                timestamp: timestamp,
                heartRate: hrValue,
                speed: spValue,
                power: pwValue,
                cadence: cdValue,
                distance: nil
            )
        }

        try await store.replaceSamples(combined, forWorkoutUUID: workoutUUID)
    }

    /// Pure-Swift mapping van een Strava-stream + bijbehorende timestamps naar
    /// `[TimedValue]`. Internal voor unit-tests.
    static func zip(stream: StravaStream?, with timestamps: [Date]) -> [TimedValue] {
        guard let stream, !stream.data.isEmpty else { return [] }
        let count = min(stream.data.count, timestamps.count)
        return (0..<count).map { i in
            TimedValue(timestamp: timestamps[i], value: stream.data[i])
        }
    }
}
