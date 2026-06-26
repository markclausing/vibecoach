import SwiftUI
import SwiftData
import Charts

struct AppTabHostView: View {
    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var planManager: TrainingPlanManager
    @EnvironmentObject var themeManager: ThemeManager

    // We create the ViewModel here so we can share it with the DashboardView
    // for pull-to-refresh and the ChatView as an overlay.
    @StateObject private var sharedChatViewModel = ChatViewModel()

    // Auto-Sync Dependencies (Sprint 12.3)
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    private let fitnessDataService = FitnessDataService()

    /// Guard against concurrent auto-sync runs (race condition fix for duplicate records).
    @State private var isAutoSyncing = false

    /// Epic #51-F1/F2/F5: writes per-source success/error messages so that
    /// `SyncStatusBanner` on the Dashboard can show them directly. Deliberately silent
    /// for `.missingToken` — a user without a Strava connection gets no
    /// banner about a sync they never enabled.
    private let syncStatusStore = SyncStatusStore()

    /// Asynchronously runs the data synchronization for the last 14 days in the background.
    /// Epic #42 Story 42.1: HK + Strava run independently, regardless of `selectedDataSource`.
    /// The toggle has thereby become a "preference" (label/tiebreaker), no longer an exclusive
    /// choice. Cross-source duplicates are caught by `ActivityDeduplicator.smartInsert`.
    private func performAutoSync() {
        guard !isAutoSyncing else {
            AppLoggers.fitnessDataService.notice("Auto-sync skipped: a previous sync is still active")
            return
        }
        isAutoSyncing = true
        Task {
            defer { Task { @MainActor in isAutoSyncing = false } }
            async let hk: Void = runHealthKitAutoSync()
            async let strava: Void = runStravaAutoSync()
            _ = await (hk, strava)
        }
    }

    @MainActor
    private func runHealthKitAutoSync() async {
        do {
            // Epic #38 Story 38.2: cache the number of workouts HK returned in the
            // 365d window, so that `DashboardView` can determine via
            // `HealthKitSyncStatusEvaluator` whether the "silent sync" banner should be
            // shown. 0 workouts + workout-auth != .sharingAuthorized = banner.
            let count = try await HealthKitSyncService().syncHistoricalWorkouts(to: modelContext)
            UserDefaults.standard.set(count, forKey: "vibecoach_lastHKWorkoutsCount")
            syncStatusStore.recordHKSuccess()

            // fix/workout-samples-loading: ask DeepSync directly for samples for the
            // just-inserted workouts. Without this trigger DeepSync only picks up
            // at DashboardView.task — a user who opens the Coach or Goals tab
            // right after a workout would otherwise stay stuck forever on the
            // "Deep Sync running" placeholder. Idempotent: the processed-UUID set in
            // DeepSyncService prevents repeated HK quantity fetches.
            let store = WorkoutSampleStore(modelContainer: modelContext.container)
            let ingest = WorkoutSampleIngestService()
            let deepSync = DeepSyncService(ingestService: ingest, store: store)
            await deepSync.runIfNeeded()
        } catch {
            // Silent error: HK may be unauthorized, no reason to block.
            // Write count=0 so the banner evaluator can still trigger if
            // the auth status supports it.
            UserDefaults.standard.set(0, forKey: "vibecoach_lastHKWorkoutsCount")
            syncStatusStore.recordHKError(error)
            AppLoggers.fitnessDataService.error("Auto-sync HealthKit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Epic #38 Story 38.1: foreground-return retrigger. On every `.active`
    /// transition we check whether one of the critical types is `.notDetermined` —
    /// can arise after an iOS permission reset (e.g. partially after reinstall
    /// or via Privacy & Security settings). The helper only shows a
    /// prompt for types where no decision has been made yet; users with
    /// explicit `.sharingAuthorized` or `.sharingDenied` see no UX change.
    @MainActor
    private func retriggerHealthKitPermissionsIfNeeded() async {
        do {
            try await HealthKitManager.shared.requestPermissionsForCriticalNotDetermined()
        } catch {
            AppLoggers.fitnessDataService.error("HealthKit permission retrigger failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func runStravaAutoSync() async {
        do {
            // Only fetch the last 14 days — short enough for the Burn Rate graph + well
            // within Strava's rate limit.
            let activities = try await fitnessDataService.fetchRecentActivities(days: 14)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()

            for activity in activities {
                let date = formatter.date(from: activity.start_date) ?? fallbackFormatter.date(from: activity.start_date) ?? Date()

                // SPRINT 12.4: basic TRIMP fallback during sync.
                let basicTRIMPFallback: Double? = {
                    if let hr = activity.average_heartrate, hr > 100 {
                        let durationMins = Double(activity.moving_time) / 60.0
                        let simulatedDeltaHR = (hr - 60.0) / (190.0 - 60.0)
                        return durationMins * simulatedDeltaHR * 0.64 * exp(1.92 * simulatedDeltaHR)
                    } else {
                        return (Double(activity.moving_time) / 60.0) * 1.5
                    }
                }()

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
                // Epic #50: fetch historical weather data for outdoor Strava rides
                // without iPhone presence (Garmin/bike-computer-only). Fails
                // gracefully — on an API error the record simply stays without weather data.
                await HistoricalWeatherService.enrichRecord(record, from: activity, startDate: date)
                _ = try? ActivityDeduplicator.smartInsert(record, into: modelContext)
            }
            try? modelContext.save()
            syncStatusStore.recordStravaSuccess()
        } catch FitnessDataError.missingToken {
            // User has not connected Strava — no reason to log on every launch.
            // Deliberately no `recordStravaError` so we don't show a banner to someone
            // without a Strava connection (Epic #51-F1).
        } catch {
            syncStatusStore.recordStravaError(error)
            AppLoggers.fitnessDataService.error("Auto-sync Strava failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            // Tab 1: Overview (Dashboard & Calendar)
            DashboardView(viewModel: sharedChatViewModel)
                .tabItem {
                    Label("Overzicht", systemImage: "house")
                }
                .tag(AppNavigationState.Tab.dashboard)

            // Tab 2: Goals — long-term analysis center (Epic 23)
            GoalsListView(viewModel: sharedChatViewModel)
                .tabItem {
                    Label("Doelen", systemImage: "scope")
                }
                .tag(AppNavigationState.Tab.goals)

            // Tab 3: Coach — real tab so the TabBar always stays visible (Sprint 13.4)
            ChatView(viewModel: sharedChatViewModel)
                .tabItem {
                    Label("Coach", systemImage: "bubble.left")
                }
                .tag(AppNavigationState.Tab.coach)

            // Tab 4: Memory
            NavigationStack {
                PreferencesListView()
            }
            .tabItem {
                Label("Geheugen", systemImage: "person.and.background.dotted")
            }
            .tag(AppNavigationState.Tab.memory)

            // Tab 5: Settings
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Instellingen", systemImage: "gearshape")
            }
            .tag(AppNavigationState.Tab.settings)
        }
        .tint(themeManager.primaryAccentColor)
        .saturation(themeManager.themeSaturation)
        // SPRINT 13.4: showingChatSheet = true now redirects to the Coach tab
        // so that all existing call sites (banners, notifications, deep links) keep working
        // without changes, and the TabBar always stays visible.
        .onChange(of: appState.showingChatSheet) { _, isShowing in
            if isShowing {
                appState.selectedTab = .coach
                // Reset so the trigger can be used again
                Task { @MainActor in appState.showingChatSheet = false }
            }
        }
        .onAppear {
            sharedChatViewModel.setTrainingPlanManager(planManager)
            // Story 61.7: inject the SwiftData context so the PHI prompt-context
            // caches load from the protected store instead of UserDefaults.
            sharedChatViewModel.configure(with: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerAutoSync"))) { _ in
            performAutoSync()
        }
        // Epic #38 Story 38.1: on foreground return, prompt for types that
        // have become `.notDetermined` in the meantime (e.g. iOS reinstall with
        // partial permission reset). iOS 17+ two-arg onChange syntax.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await retriggerHealthKitPermissionsIfNeeded() }
        }
    }
}
