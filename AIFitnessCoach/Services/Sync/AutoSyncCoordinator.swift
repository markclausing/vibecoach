import Foundation
import SwiftData

// MARK: - Injection seams (Epic #65 story 65.4)
//
// Thin protocols wrapping the two sync services so `AutoSyncCoordinator` can be
// unit-tested with mocks instead of touching HealthKit or the Strava network.
// Deliberately co-located with their sole consumer (same pattern as
// `WeatherURLFetcher` living next to `HistoricalWeatherService`).

/// Seam over `HealthKitSyncService.syncHistoricalWorkouts`. The requirement stays
/// `@MainActor` because the real implementation writes `ActivityRecord`s into the
/// SwiftData context — so SwiftData work keeps running on the main actor.
protocol HealthKitWorkoutSyncing: Sendable {
    @MainActor func syncHistoricalWorkouts(to context: ModelContext) async throws -> Int
}

extension HealthKitSyncService: HealthKitWorkoutSyncing {}

/// Seam over `FitnessDataService.fetchRecentActivities` (Strava). Actor-isolated in
/// the real implementation; the coordinator only needs the async Sendable result.
protocol StravaActivityFetching: Sendable {
    func fetchRecentActivities(days: Int) async throws -> [StravaActivity]
}

extension FitnessDataService: StravaActivityFetching {}

// MARK: - AutoSyncCoordinator
//
// Epic #65 story 65.4: owns the entire auto-sync pipeline that used to live in
// `AppTabHostView` (`performAutoSync` + the HK/Strava fan-out + the foreground
// permission retrigger). Extracting it turns the previously "documented-not-tested"
// view-orchestration into unit-tested code (CLAUDE.md §6).
//
// Isolation: `@MainActor`. The whole pipeline writes SwiftData (`ActivityRecord`
// inserts + `save()`), and both HK sync and the weather-apply step mutate
// non-Sendable `@Model` objects, so it must stay on the main actor. The only place
// concurrency buys us anything is the *awaits* — the HK/Strava fan-out (`async let`)
// and the batched weather fetches (bounded task group) suspend, letting the main
// actor interleave other work. Behaviour is identical to the previous view code.

/// Weather-tuple type shared by the injected fetch seam and the internal batcher.
typealias WeatherFetchResult = (temperatureCelsius: Double?, humidityPercent: Double?)

@MainActor
final class AutoSyncCoordinator {

    private let modelContext: ModelContext
    private let healthKitSync: HealthKitWorkoutSyncing
    private let stravaFetch: StravaActivityFetching
    private let syncStatusStore: SyncStatusStore
    private let defaults: UserDefaults
    private let weatherConcurrency: Int
    private let fetchWeather: @Sendable (_ latitude: Double, _ longitude: Double, _ startDate: Date) async -> WeatherFetchResult
    private let runDeepSync: () async -> Void
    private let retriggerPermissions: () async -> Void

    /// Guard against concurrent auto-sync runs (race-condition fix for duplicate
    /// records). `@MainActor` isolation makes the plain `Bool` access safe.
    private var isSyncing = false

    /// - Parameters:
    ///   - modelContext: SwiftData context the synced records are written into.
    ///   - fetchWeather: seam over `HistoricalWeatherService.fetchWeather`; swallows
    ///     transport errors and returns `(nil, nil)` so a failed lookup never fails the
    ///     sync (mirrors `HistoricalWeatherService.enrichRecord`'s `do/catch`).
    ///   - runDeepSync: seam over the post-HK `DeepSyncService.runIfNeeded` trigger.
    ///   - retriggerPermissions: seam over the foreground HealthKit permission retrigger.
    init(
        modelContext: ModelContext,
        healthKitSync: HealthKitWorkoutSyncing = HealthKitSyncService(),
        stravaFetch: StravaActivityFetching = FitnessDataService(),
        syncStatusStore: SyncStatusStore = SyncStatusStore(),
        defaults: UserDefaults = .standard,
        weatherConcurrency: Int = 4,
        fetchWeather: (@Sendable (Double, Double, Date) async -> WeatherFetchResult)? = nil,
        runDeepSync: (() async -> Void)? = nil,
        retriggerPermissions: (() async -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.healthKitSync = healthKitSync
        self.stravaFetch = stravaFetch
        self.syncStatusStore = syncStatusStore
        self.defaults = defaults
        self.weatherConcurrency = max(1, weatherConcurrency)

        self.fetchWeather = fetchWeather ?? { latitude, longitude, startDate in
            let service = HistoricalWeatherService()
            do {
                return try await service.fetchWeather(latitude: latitude, longitude: longitude, startDate: startDate)
            } catch {
                AppLoggers.weather.error("Open-Meteo fetch failed during auto-sync: \(error.localizedDescription, privacy: .public)")
                return (nil, nil)
            }
        }

        self.runDeepSync = runDeepSync ?? {
            // fix/workout-samples-loading: ask DeepSync directly for the samples of the
            // just-inserted workouts so a user opening the Coach/Goals tab right after a
            // workout is not stuck on the "Deep Sync running" placeholder. Idempotent via
            // DeepSyncService's processed-UUID set.
            let store = WorkoutSampleStore(modelContainer: modelContext.container)
            let ingest = WorkoutSampleIngestService()
            let deepSync = DeepSyncService(ingestService: ingest, store: store)
            await deepSync.runIfNeeded()
        }

        self.retriggerPermissions = retriggerPermissions ?? {
            do {
                try await HealthKitManager.shared.requestPermissionsForCriticalNotDetermined()
            } catch {
                AppLoggers.fitnessDataService.error("HealthKit permission retrigger failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Public triggers

    /// Fire-and-forget entry used by the `AppTabHostView` triggers
    /// (`.triggerAutoSync` notification + `.active` scene phase).
    func performAutoSync() {
        Task { await self.runAutoSync() }
    }

    /// Structured, awaitable entry (used by the triggers via `performAutoSync` and by
    /// unit tests directly). Enforces a single in-flight sync.
    ///
    /// Epic #42 Story 42.1: HK + Strava run independently, regardless of
    /// `selectedDataSource`. Cross-source duplicates are caught by
    /// `ActivityDeduplicator.smartInsert`.
    func runAutoSync() async {
        guard !isSyncing else {
            AppLoggers.fitnessDataService.notice("Auto-sync skipped: a previous sync is still active")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        async let hk: Void = runHealthKitSync()
        async let strava: Void = runStravaSync()
        _ = await (hk, strava)
    }

    /// Epic #38 Story 38.1: on foreground return, prompt for HealthKit types that have
    /// become `.notDetermined` in the meantime (e.g. an iOS reinstall with a partial
    /// permission reset). Types with an explicit decision see no UX change.
    func retriggerHealthKitPermissionsIfNeeded() async {
        await retriggerPermissions()
    }

    // MARK: - HealthKit

    private func runHealthKitSync() async {
        do {
            // Epic #38 Story 38.2: cache the number of workouts HK returned so the
            // Dashboard's "silent sync" banner evaluator can decide whether to warn
            // (0 workouts + workout-auth != .sharingAuthorized = banner).
            let count = try await healthKitSync.syncHistoricalWorkouts(to: modelContext)
            defaults.set(count, forKey: AppStorageKeys.lastHKWorkoutsCount)
            syncStatusStore.recordHKSuccess()
            await runDeepSync()
        } catch {
            // Silent error: HK may be unauthorized, no reason to block. Write count=0 so
            // the banner evaluator can still trigger if the auth status supports it.
            defaults.set(0, forKey: AppStorageKeys.lastHKWorkoutsCount)
            syncStatusStore.recordHKError(error)
            AppLoggers.fitnessDataService.error("Auto-sync HealthKit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Strava

    private func runStravaSync() async {
        do {
            // Only the last 14 days — short enough for the Burn Rate graph + well within
            // Strava's rate limit.
            let activities = try await stravaFetch.fetchRecentActivities(days: 14)

            // Phase 1 (main actor): build every record + persist GPS coords, and collect
            // the outstanding weather fetches. Mirrors `HistoricalWeatherService.enrichRecord`'s
            // coords-persist + "skip snapshot if already set" guard, but defers the network
            // awaits so Phase 2 can batch them.
            var records: [ActivityRecord] = []
            var pending: [(index: Int, latitude: Double, longitude: Double, startDate: Date)] = []

            for activity in activities {
                // Epic 65.1: cached ISO-8601 formatters (no per-activity allocation).
                let date = AppDateFormatters.iso8601WithFractionalSeconds.date(from: activity.start_date)
                    ?? AppDateFormatters.iso8601.date(from: activity.start_date)
                    ?? Date()

                // SPRINT 12.4: basic TRIMP fallback during sync (Epic 65.1: centralised).
                let basicTRIMPFallback = PhysiologicalCalculator.basicFallbackTRIMP(
                    durationSec: Double(activity.moving_time),
                    avgHR: activity.average_heartrate
                )

                let record = ActivityRecord(
                    id: String(activity.id),
                    name: activity.name,
                    distance: activity.distance,
                    movingTime: activity.moving_time,
                    averageHeartrate: activity.average_heartrate,
                    sportCategory: SportCategory.from(rawString: activity.type),
                    startDate: date,
                    trimp: basicTRIMPFallback,
                    deviceWatts: activity.device_watts
                )

                let index = records.count
                records.append(record)

                // Epic #50/#52: persist coords immediately (independent of the weather
                // fetch), and queue a fetch only when coords exist and no snapshot is set
                // yet — the exact guard from `enrichRecord`.
                if let coords = activity.start_latlng, coords.count == 2 {
                    if record.startLatitude == nil { record.startLatitude = coords[0] }
                    if record.startLongitude == nil { record.startLongitude = coords[1] }
                    if record.temperatureCelsius == nil, record.humidityPercent == nil {
                        pending.append((index: index, latitude: coords[0], longitude: coords[1], startDate: date))
                    }
                }
            }

            // Phase 2: fan the per-record weather fetches out with bounded concurrency
            // (~4). Only Sendable values cross the task boundary; a per-record failure
            // yields `(nil, nil)` and leaves that record without weather — it never fails
            // the sync (per-record failure isolation).
            let weather = await fetchWeatherBatch(pending)
            for (index, values) in weather {
                if let temp = values.temperatureCelsius { records[index].temperatureCelsius = temp }
                if let humidity = values.humidityPercent { records[index].humidityPercent = humidity }
            }

            // Phase 3: dedupe-insert every record, then one save.
            for record in records {
                _ = try? ActivityDeduplicator.smartInsert(record, into: modelContext)
            }
            // Epic 65.1: log a failed save instead of silently swallowing it (§11).
            do {
                try modelContext.save()
            } catch {
                AppLoggers.fitnessDataService.error("Auto-sync Strava save failed: \(error.localizedDescription, privacy: .public)")
            }
            syncStatusStore.recordStravaSuccess()
        } catch FitnessDataError.missingToken {
            // User has not connected Strava — no reason to log on every launch, and
            // deliberately no `recordStravaError` so someone without a Strava connection
            // never sees a banner about a sync they never enabled (Epic #51-F1).
        } catch {
            syncStatusStore.recordStravaError(error)
            AppLoggers.fitnessDataService.error("Auto-sync Strava failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Runs the outstanding weather fetches with a sliding-window task group bounded to
    /// `weatherConcurrency`. Returns a map keyed by the record index. Errors are already
    /// swallowed inside `fetchWeather`, so a failure surfaces as `(nil, nil)`.
    private func fetchWeatherBatch(
        _ pending: [(index: Int, latitude: Double, longitude: Double, startDate: Date)]
    ) async -> [Int: WeatherFetchResult] {
        guard !pending.isEmpty else { return [:] }
        let fetch = fetchWeather
        let limit = weatherConcurrency
        var results: [Int: WeatherFetchResult] = [:]

        await withTaskGroup(of: (Int, WeatherFetchResult).self) { group in
            var iterator = pending.makeIterator()
            var running = 0
            while running < limit, let item = iterator.next() {
                group.addTask { (item.index, await fetch(item.latitude, item.longitude, item.startDate)) }
                running += 1
            }
            while let finished = await group.next() {
                results[finished.0] = finished.1
                if let item = iterator.next() {
                    group.addTask { (item.index, await fetch(item.latitude, item.longitude, item.startDate)) }
                }
            }
        }
        return results
    }
}
