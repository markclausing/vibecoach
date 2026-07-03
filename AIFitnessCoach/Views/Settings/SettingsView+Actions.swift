import SwiftUI
import UserNotifications

// Epic #65 story 65.5: split out of SettingsView.swift (§5 file-split). Pure move —
// no semantic changes; access relaxed private -> internal only where the split
// requires it (listed in the PR body).

extension SettingsView {

    // Recalculate the local athletic profile based on SwiftData
    func refreshProfile() {
        do {
            self.athleticProfile = try profileManager.calculateProfile(context: modelContext)
        } catch {
            AppLoggers.athleticProfileManager.error("Athletic profile calculation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // Triggers fetching historical workouts.
    // Epic #42 Story 42.1: HK + Strava run independently; the dedupe layer from
    // Epic #41 covers cross-source. `selectedDataSource` no longer determines
    // which source we fetch — only which one is labelled as "primary".
    func syncHistoricalData() {
        guard !isSyncingHistory else { return }
        isSyncingHistory = true
        feedbackMessage = "Synchroniseren gestart..."

        Task {
            async let hk = runHealthKitHistoricalSync()
            async let strava = runStravaHistoricalSync()
            let (hkMessage, stravaMessage) = await (hk, strava)

            await MainActor.run {
                isSyncingHistory = false
                feedbackMessage = "\(hkMessage) · \(stravaMessage)"
                refreshProfile()
            }
        }
    }

    @MainActor
    private func runHealthKitHistoricalSync() async -> String {
        do {
            // Epic #38 Story 38.2: cache count for the Dashboard banner evaluator.
            let count = try await HealthKitSyncService().syncHistoricalWorkouts(to: modelContext)
            UserDefaults.standard.set(count, forKey: AppStorageKeys.lastHKWorkoutsCount)
            return "HealthKit (1 jaar) gesynchroniseerd — \(count) workouts"
        } catch {
            UserDefaults.standard.set(0, forKey: AppStorageKeys.lastHKWorkoutsCount)
            return "HealthKit-fout: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func runStravaHistoricalSync() async -> String {
        do {
            // SPRINT 6.1 & 7.4: fetch at most 12 months of Strava history.
            let activities = try await fitnessDataService.fetchHistoricalActivities(monthsBack: 12)

            var newRecordsCount = 0

            for activity in activities {
                // Epic 65.1: use the cached ISO-8601 formatters (no per-activity allocation).
                let date = AppDateFormatters.iso8601WithFractionalSeconds.date(from: activity.start_date)
                    ?? AppDateFormatters.iso8601.date(from: activity.start_date)
                    ?? Date()

                // SPRINT 12.4: basic TRIMP fallback during sync (Epic 65.1: centralised).
                let basicTRIMPFallback: Double? = PhysiologicalCalculator.basicFallbackTRIMP(
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
                // Epic #50: historical weather data via Open-Meteo for Strava-only
                // rides (Garmin/bike computer). Sequential — for 12 months ≈
                // 100 calls, ~10s extra on the "Sync historische data" button. Fault-
                // tolerant: API error = continue without weather.
                await HistoricalWeatherService.enrichRecord(record, from: activity, startDate: date)
                if let result = try? ActivityDeduplicator.smartInsert(record, into: modelContext),
                   result == .inserted || result == .replaced {
                    newRecordsCount += 1
                }
            }
            try? modelContext.save()
            return "Strava: \(newRecordsCount) nieuwe activiteiten"
        } catch FitnessDataError.missingToken {
            return "Strava niet gekoppeld"
        } catch {
            return "Strava-fout: \(error.localizedDescription)"
        }
    }

    // Check the current status of Push Notifications permission
    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsEnabled = (settings.authorizationStatus == .authorized)
            }
        }
    }

    // Explicitly request permission from the user for local notifications.
    // The proactive engines (A & B) use only `UNUserNotificationCenter`
    // scheduling — there is no APNs receiver anymore since the Node.js backend disappeared.
    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
                if granted {
                    self.feedbackMessage = "Notificaties succesvol ingeschakeld."
                } else if let error = error {
                    self.feedbackMessage = "Fout bij aanvragen notificaties: \(error.localizedDescription)"
                } else {
                    self.feedbackMessage = "Notificatie toestemming geweigerd. Zet dit aan in de iOS Instellingen app."
                }
            }
        }
    }

    // Function to connect Apple Health
    func koppelAppleHealth() {
        let healthKitManager = HealthKitManager()
        healthKitManager.requestAuthorization { success, error in
            DispatchQueue.main.async {
                if success {
                    self.isHealthKitLinked = true
                    self.feedbackMessage = "Apple Health succesvol gekoppeld."
                } else {
                    self.feedbackMessage = "Fout bij koppelen Apple Health: \(error?.localizedDescription ?? "Onbekende fout")"
                }
            }
        }
    }

    #if targetEnvironment(simulator)
    func generateDummyData() {
        feedbackMessage = "Genereren van dummy data..."

        Task { @MainActor in
            let calendar = Calendar.current
            let now = Date()

            // swiftlint:disable force_unwrapping
            // Debug-only dummy-data generator: Calendar day arithmetic on `now`, never nil.
            // 1. Add a dummy FitnessGoal (Marathon)
            let targetDate = calendar.date(byAdding: .day, value: 60, to: now)! // In 2 months
            let createdDate = calendar.date(byAdding: .day, value: -30, to: now)! // Started 1 month ago

            let goal = FitnessGoal(
                title: "Amsterdam Marathon (Test)",
                details: "Gegenereerd via simulator tools",
                targetDate: targetDate,
                createdAt: createdDate,
                sportCategory: .running,
                targetTRIMP: 6500.0
            )
            modelContext.insert(goal)

            // 2. Add 5 realistic activities in the past 45 days
            let workoutDates = [
                calendar.date(byAdding: .day, value: -35, to: now)!, // Time Travel: Before the createdAt!
                calendar.date(byAdding: .day, value: -20, to: now)!,
                calendar.date(byAdding: .day, value: -12, to: now)!,
                calendar.date(byAdding: .day, value: -7, to: now)!,
                calendar.date(byAdding: .day, value: -2, to: now)!
            ]
            // swiftlint:enable force_unwrapping

            let trimps = [150.0, 210.0, 180.0, 320.0, 140.0]
            let durations = [2700, 3600, 3200, 5400, 2400]
            let names = ["Recovery Run", "Tempo Run", "Endurance", "Long Run", "Shakeout"]

            for (index, date) in workoutDates.enumerated() {
                let record = ActivityRecord(
                    id: "dummy_\(index)_\(Int(date.timeIntervalSince1970))",
                    name: names[index],
                    distance: Double(durations[index]) * 2.5, // Rough estimate
                    movingTime: durations[index],
                    averageHeartrate: 145.0 + Double(index * 2),
                    sportCategory: .running,
                    startDate: date,
                    trimp: trimps[index]
                )
                modelContext.insert(record)
            }

            try? modelContext.save()
            feedbackMessage = "Dummy data gegenereerd! Ga naar het Dashboard."
            refreshProfile()
        }
    }
    #endif
}
