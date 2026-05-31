import Foundation
import SwiftData

// MARK: - Epic 40 Story 40.4: SessionReclassifier
//
// After a stream backfill (Strava 40.3 or HK DeepSync 32.1) a record that earlier
// only had avg HR (or nothing) suddenly has fine-grained samples. The zone-distribution
// strategy of `SessionClassifier` (story 33.1a) then yields a more accurate sessionType
// than the avg-HR fallback. This helper finds such records and reclassifies them.
//
// Protected:
//   • `manualSessionTypeOverride == true` — the user chose themselves (see
//     `WorkoutAnalysisView.setSessionType`); a rerun must never override it.
//   • Records without samples — nothing to upgrade, so no work to do.
//   • Idempotent: if the classifier returns the same type as already set, no save.
//
// The pure-Swift `decide` layer is fully testable without SwiftData; `rerun` is the
// SwiftData action wrapper, the same pattern as `ActivityDeduplicator.runDedupe`.

enum SessionReclassifier {

    /// Proposed change for one record. `decide` produces a list of these;
    /// `rerun` applies them.
    struct Change {
        let record: ActivityRecord
        let newType: SessionType
    }

    // MARK: Decide

    /// Pure-Swift core. Loops through records, requests samples via the injected
    /// lookup, runs the classifier and yields only genuinely changing proposals.
    /// - Parameters:
    ///   - records: Records to consider (typically everything from the DB).
    ///   - maxHeartRate: HRmax for zone calculation (Tanaka or fallback).
    ///   - samplesProvider: Lookup function that returns the samples per record.
    ///     Empty array = no samples available → the record is skipped.
    /// - Returns: List of proposed changes. Records for which the classifier
    ///   returns `nil` or the existing type are not included.
    static func decide(records: [ActivityRecord],
                       maxHeartRate: Double,
                       samplesProvider: (ActivityRecord) -> [WorkoutSample]) -> [Change] {
        // Epic #44 story 44.5: use the LTHR from the profile if present
        // — Friel zones are more precise for athletic users with a deviating
        // LTHR/max ratio.
        let cachedLTHR = UserProfileService.cachedThreshold(forKey: UserProfileService.lactateThresholdHRKey)?.value
        let classifier = SessionClassifier(maxHeartRate: maxHeartRate, lactateThresholdHR: cachedLTHR)
        var changes: [Change] = []

        for record in records {
            // Manual override: the user has the last word — never override.
            if record.manualSessionTypeOverride == true { continue }

            let samples = samplesProvider(record)
            // Without samples the classifier falls back to avg HR — which already
            // ran at ingest, so a rerun adds nothing. Skip to avoid reprocessing
            // records without upgrade potential every time.
            guard !samples.isEmpty else { continue }

            let suggested = classifier.classify(
                samples: samples,
                averageHeartRate: record.averageHeartrate,
                durationSeconds: record.movingTime,
                title: record.name
            )

            guard let suggested, suggested != record.sessionType else { continue }
            changes.append(Change(record: record, newType: suggested))
        }
        return changes
    }

    // MARK: Rerun (SwiftData)

    /// Performs the reclassification on a ModelContext: writes `sessionType` for
    /// every proposed change and saves once at the end. Idempotent —
    /// a second call on an already-classified DB does nothing.
    /// - Parameters:
    ///   - context: ModelContext to read from and write to.
    ///   - store: WorkoutSampleStore for the samples lookup per record.
    ///   - maxHeartRate: HRmax for zone calculation (Tanaka or fallback).
    /// - Returns: Number of reclassified records.
    @MainActor
    static func rerun(in context: ModelContext,
                      store: WorkoutSampleStore,
                      maxHeartRate: Double) async throws -> Int {
        let descriptor = FetchDescriptor<ActivityRecord>(sortBy: [SortDescriptor(\.startDate, order: .forward)])
        let allRecords = try context.fetch(descriptor)

        // Pre-fetch samples per record. Acceptable for ~100 records; at 1000+
        // we can move to a batched fetch.
        var samplesByID: [String: [WorkoutSample]] = [:]
        for record in allRecords {
            if record.manualSessionTypeOverride == true { continue }
            let uuid = UUID.forActivityRecordID(record.id)
            let samples = (try? await store.samples(forWorkoutUUID: uuid)) ?? []
            if !samples.isEmpty {
                samplesByID[record.id] = samples
            }
        }

        let changes = decide(records: allRecords, maxHeartRate: maxHeartRate) {
            samplesByID[$0.id] ?? []
        }

        for change in changes {
            change.record.sessionType = change.newType
        }
        if !changes.isEmpty {
            try context.save()
        }
        return changes.count
    }
}
