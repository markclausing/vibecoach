import Foundation

// MARK: - Epic 40 Story 40.3: StravaStreamIngestService
//
// Mirrors the architecture of `WorkoutSampleIngestService` (HealthKit) but for
// Strava streams. Reuses `SampleResampler` (story 32.1) for the 5s-bucket conversion
// and `WorkoutSampleStore` (`@ModelActor`) for idempotent storage.
//
// Design:
//   • Pure-Swift parsing of `StravaStreamSet` → `[TimedValue]` per signal
//   • Resampler strategies identical to WorkoutSampleIngestService:
//       - average for HR / power / cadence
//       - linear interpolation for speed (velocity_smooth)
//   • Storage via `replaceSamples(forWorkoutUUID:)` — idempotent, the same UUID
//     rewrites the set
//   • UUID linking via `UUID.deterministic(fromStravaID:)` — the same Strava ID
//     always yields the same foreign key

final class StravaStreamIngestService {

    private let resampler: SampleResampler

    init(resampler: SampleResampler = SampleResampler()) {
        self.resampler = resampler
    }

    /// Fully ingest one Strava activity: convert the API response, resample and store.
    /// - Parameters:
    ///   - streams: The StravaStreamSet as returned by `FitnessDataService.fetchActivityStreams`.
    ///   - activityID: Strava activity ID (string, as stored in `ActivityRecord.id`).
    ///   - startDate: Workout start date, the basis for absolute timestamps (the Strava `time` stream is an offset in seconds from the start).
    ///   - durationSeconds: Planned duration — determines the bucket-window end.
    ///   - store: The `WorkoutSampleStore` (`@ModelActor`) where samples land.
    func ingestStreams(_ streams: StravaStreamSet,
                       activityID: String,
                       startDate: Date,
                       durationSeconds: Int,
                       into store: WorkoutSampleStore) async throws {

        let workoutUUID = UUID.deterministic(fromStravaID: activityID)
        let endDate = startDate.addingTimeInterval(TimeInterval(durationSeconds))

        // Strava's time stream is a linear offset array (seconds from the start).
        // Without the time stream we can't link the other data to absolute timestamps.
        guard let timeStream = streams.time, !timeStream.data.isEmpty else {
            // Nothing to ingest — skip gracefully, no error.
            return
        }

        let timestamps: [Date] = timeStream.data.map { offset in
            startDate.addingTimeInterval(offset)
        }

        let hrSamples       = Self.zip(stream: streams.heartrate, with: timestamps)
        let powerSamples    = Self.zip(stream: streams.watts, with: timestamps)
        let cadenceSamples  = Self.zip(stream: streams.cadence, with: timestamps)
        let speedSamples    = Self.zip(stream: streams.velocity_smooth, with: timestamps)

        let hrBuckets      = resampler.resample(samples: hrSamples, from: startDate, to: endDate, strategy: .average)
        let powerBuckets   = resampler.resample(samples: powerSamples, from: startDate, to: endDate, strategy: .average)
        let cadenceBuckets = resampler.resample(samples: cadenceSamples, from: startDate, to: endDate, strategy: .average)
        let speedBuckets   = resampler.resample(samples: speedSamples, from: startDate, to: endDate, strategy: .linearInterpolation)

        // The HR grid serves as the canonical time axis — all resamplers produce the same
        // bucket timestamps (same start/end/bucketSize) so indices match 1-to-1.
        // On a missing HR stream we take the first available grid.
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

            // The distance stream is not requested from Strava (could later be added via /streams as a
            // distance key). For now: nil. WorkoutSampleService does the same for non-
            // running HK records, so it's consistent.
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

    /// Pure-Swift mapping of a Strava stream + corresponding timestamps to
    /// `[TimedValue]`. Internal for unit tests.
    static func zip(stream: StravaStream?, with timestamps: [Date]) -> [TimedValue] {
        guard let stream, !stream.data.isEmpty else { return [] }
        let count = min(stream.data.count, timestamps.count)
        return (0..<count).map { i in
            TimedValue(timestamp: timestamps[i], value: stream.data[i])
        }
    }
}
