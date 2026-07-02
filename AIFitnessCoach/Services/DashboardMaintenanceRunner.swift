import Foundation
import SwiftData
import HealthKit

// MARK: - DashboardMaintenanceRunner
//
// Epic #65 story 65.4: owns DashboardView's post-sync maintenance orchestration —
// the four background jobs (`backfillStravaStreams`, `runAutoDedupe`,
// `runSessionReclassification`, `refreshChatContextCaches`) that used to live as
// `.task` methods on the view. A plain `@MainActor` type with an injected
// `ModelContext`, so the ordering/wiring is unit-testable; the individual jobs keep
// their own dedicated service tests (`ActivityDeduplicator`, `SessionReclassifier`,
// `WorkoutPatternDetector`, …), so the runner tests only assert light orchestration.
//
// `calculateAndSaveVibeScore` stays in `DashboardView`: it is genuinely view-bound —
// it drives `@State` (`isVibeScoreLoading`, `isVibeScoreUnavailable`,
// `dashboardRestingHR/VO2Max`) and has no clean seam that wouldn't just re-plumb the
// same view state back in. That residual glue is what CLAUDE.md §6 still exempts.

@MainActor
final class DashboardMaintenanceRunner {

    private let modelContext: ModelContext
    private let fitnessDataService: FitnessDataService

    init(modelContext: ModelContext,
         fitnessDataService: FitnessDataService = FitnessDataService()) {
        self.modelContext = modelContext
        self.fitnessDataService = fitnessDataService
    }

    /// The ordered post-sync sequence DashboardView runs from its `.task`.
    /// Order matters: stream backfill first (so sample counts are current for the
    /// dedupe richness heuristic — Strava records with just-arrived power win), then
    /// dedupe, then reclassification (records now have fine-grained samples), then a
    /// refresh of the coach context caches.
    func runPostSyncMaintenance(context: CoachContextStore) async {
        await backfillStravaStreams()
        await runAutoDedupe()
        await runSessionReclassification()
        await refreshChatContextCaches(into: context)
    }

    // MARK: - Strava stream backfill

    /// Epic 40 Story 40.3: filter the last 10 Strava records (id not UUID-parseable)
    /// without 5s samples in the DB and fetch their streams. 100ms throttle between
    /// calls to comfortably respect Strava's rate limit (100 req/15min). A per-record
    /// error does not block the batch — just continue with the next.
    func backfillStravaStreams() async {
        let store = WorkoutSampleStore(modelContainer: modelContext.container)
        let ingest = StravaStreamIngestService()
        let api = fitnessDataService

        // Fetch the newest records and keep only the Strava ones (numeric id → not a UUID).
        let descriptor = FetchDescriptor<ActivityRecord>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let candidates = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { UUID(uuidString: $0.id) == nil }       // Strava only
            .prefix(10)

        for activity in candidates {
            let workoutUUID = UUID.deterministic(fromStravaID: activity.id)
            let existingCount = (try? await store.sampleCount(forWorkoutUUID: workoutUUID)) ?? 0
            guard existingCount == 0 else { continue }

            guard let stravaID = Int64(activity.id) else { continue }
            do {
                let streams = try await api.fetchActivityStreams(for: stravaID)
                try await ingest.ingestStreams(
                    streams,
                    activityID: activity.id,
                    startDate: activity.startDate,
                    durationSeconds: activity.movingTime,
                    into: store
                )
            } catch {
                // One error (404, 429 rate-limit, decode failure) does not block the batch.
                AppLoggers.dashboard.warning("Strava-stream backfill failed for activity \(activity.id, privacy: .private): \(error.localizedDescription, privacy: .public)")
            }
            // 100ms throttle — cautious + cooperative cancel.
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - Dedupe

    /// Epic 41: auto-dedupe via `ActivityDeduplicator`. Idempotent — a clean DB stays
    /// clean. Runs after the Strava backfill so sample counts are correct for the
    /// richness heuristic (Strava records with just-arrived power win).
    func runAutoDedupe() async {
        let store = WorkoutSampleStore(modelContainer: modelContext.container)
        do {
            let removed = try await ActivityDeduplicator.runDedupe(in: modelContext, store: store)
            if removed > 0 {
                AppLoggers.dashboard.info("Auto-dedupe: removed \(removed, privacy: .public) duplicate ActivityRecord(s)")
            }
        } catch {
            AppLoggers.dashboard.error("Auto-dedupe failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Session reclassification

    /// Epic 40 Story 40.4: after the stream backfill (and the subsequent dedupe),
    /// records that previously only had avg-HR suddenly have fine-grained samples. We let
    /// `SessionReclassifier` rerun the zone-distribution strategy — manually chosen
    /// sessionTypes stay protected via `manualSessionTypeOverride`.
    func runSessionReclassification() async {
        let store = WorkoutSampleStore(modelContainer: modelContext.container)
        let birthDate: Date? = {
            do {
                let dob = try HKHealthStore().dateOfBirthComponents()
                return Calendar.current.date(from: dob)
            } catch {
                return nil
            }
        }()
        let maxHR = HeartRateZones.estimatedMaxHeartRate(birthDate: birthDate)
        do {
            let updated = try await SessionReclassifier.rerun(
                in: modelContext,
                store: store,
                maxHeartRate: maxHR
            )
            if updated > 0 {
                AppLoggers.dashboard.info("Session-rerun: \(updated, privacy: .public) record(s) reclassified")
            }
        } catch {
            AppLoggers.dashboard.error("Session-rerun failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Coach context caches

    /// Epic 45 Story 45.3: fills both the 7-day pulse cache and the 14-day rich
    /// per-workout block in one shared loop. Per workout `WorkoutPatternDetector.detectAll`
    /// is called exactly once — both caches eat from the same `[WorkoutEntry]` array. That
    /// halves the SwiftData fetch I/O and prevents duplicate detector calls. Silent no-op
    /// if there are no workouts in the window — caches are then emptied so a stable week
    /// also cleans up the cache.
    func refreshChatContextCaches(into context: CoachContextStore) async {
        let store = WorkoutSampleStore(modelContainer: modelContext.container)
        let now = Date()
        let cutoff14 = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let cutoff7  = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        // Epic #44 story 44.5: fetch the profile once and pass it to detectAll so the zone
        // gates per workout consistently use the same thresholds.
        let profile = UserProfileService.cachedProfile()

        // Bounded fetch to the 14-day window (the widest consumer here).
        let descriptor = FetchDescriptor<ActivityRecord>(
            predicate: #Predicate<ActivityRecord> { $0.startDate >= cutoff14 },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        let activities = (try? modelContext.fetch(descriptor)) ?? []

        var entries: [WorkoutHistoryContextBuilder.WorkoutEntry] = []
        var patterns7d: [WorkoutPattern] = []

        for activity in activities {
            let uuid = UUID.forActivityRecordID(activity.id)
            let samples = (try? await store.samples(forWorkoutUUID: uuid)) ?? []
            let detected: [WorkoutPattern] = samples.isEmpty
                ? []
                : WorkoutPatternDetector.detectAll(in: samples, profile: profile)

            entries.append(WorkoutHistoryContextBuilder.WorkoutEntry(
                startDate: activity.startDate,
                displayName: activity.name,
                sportCategory: activity.sportCategory,
                sessionType: activity.sessionType,
                movingTime: activity.movingTime,
                trimp: activity.trimp,
                averageHeartrate: activity.averageHeartrate,
                averagePower: nil,                  // Epic #40 hookup later
                patterns: detected
            ))

            if activity.startDate >= cutoff7 {
                patterns7d.append(contentsOf: detected)
            }
        }

        context.workoutPatternsContext = WorkoutPatternFormatter.chatContextLine(for: patterns7d) ?? ""
        context.workoutHistoryContext = WorkoutHistoryContextBuilder.build(entries: entries)
    }
}
