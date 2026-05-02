import SwiftUI
import SwiftData
import Charts

struct AppTabHostView: View {
    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var planManager: TrainingPlanManager
    @EnvironmentObject var themeManager: ThemeManager

    // We maken de ViewModel hier aan zodat we hem kunnen delen met de DashboardView
    // voor pull-to-refresh en de ChatView als overlay.
    @StateObject private var sharedChatViewModel = ChatViewModel()


    // Auto-Sync Dependencies (Sprint 12.3)
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    private let fitnessDataService = FitnessDataService()

    /// Guard tegen gelijktijdige auto-sync runs (race condition fix voor duplicate records).
    @State private var isAutoSyncing = false

    /// Voert asynchroon de data-synchronisatie voor de afgelopen 14 dagen uit op de achtergrond.
    /// Epic #42 Story 42.1: HK + Strava lopen onafhankelijk, ongeacht `selectedDataSource`.
    /// De toggle is daarmee een "voorkeur" geworden (label/tiebreaker), geen exclusieve
    /// keuze meer. Cross-source duplicaten worden afgevangen door `ActivityDeduplicator.smartInsert`.
    private func performAutoSync() {
        guard !isAutoSyncing else {
            print("⚠️ Auto-sync overgeslagen: vorige sync is nog actief")
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
            // Epic #38 Story 38.2: cache het aantal workouts dat HK in 365d-window
            // teruggaf, zodat `DashboardView` via `HealthKitSyncStatusEvaluator` kan
            // bepalen of de "stille sync"-banner getoond moet worden. 0 workouts +
            // workout-auth != .sharingAuthorized = banner.
            let count = try await HealthKitSyncService().syncHistoricalWorkouts(to: modelContext)
            UserDefaults.standard.set(count, forKey: "vibecoach_lastHKWorkoutsCount")
        } catch {
            // Stille fout: HK kan niet-geautoriseerd zijn, geen reden om te blokkeren.
            // Schrijf count=0 zodat de banner-evaluator alsnog kan triggeren als
            // de auth-status dat ondersteunt.
            UserDefaults.standard.set(0, forKey: "vibecoach_lastHKWorkoutsCount")
            print("Auto-sync HealthKit gefaald: \(error.localizedDescription)")
        }
    }

    /// Epic #38 Story 38.1: foreground-return-retrigger. Bij elke `.active`-
    /// transitie checken we of een van de critical types `.notDetermined` is —
    /// kan ontstaan na een iOS-permission-reset (bv. gedeeltelijk na reinstall
    /// of via Privacy & Security-instellingen). De helper toont alléén een
    /// prompt voor types waar nog geen beslissing is genomen; gebruikers met
    /// expliciet `.sharingAuthorized` of `.sharingDenied` zien geen UX-verandering.
    @MainActor
    private func retriggerHealthKitPermissionsIfNeeded() async {
        do {
            try await HealthKitManager.shared.requestPermissionsForCriticalNotDetermined()
        } catch {
            print("HealthKit-retrigger gefaald: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func runStravaAutoSync() async {
        do {
            // Alleen laatste 14 dagen ophalen — kort genoeg voor de Burn Rate-graph + ruim
            // binnen Strava's rate-limit.
            let activities = try await fitnessDataService.fetchRecentActivities(days: 14)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()

            for activity in activities {
                let date = formatter.date(from: activity.start_date) ?? fallbackFormatter.date(from: activity.start_date) ?? Date()

                // SPRINT 12.4: basic TRIMP fallback bij sync.
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
                _ = try? ActivityDeduplicator.smartInsert(record, into: modelContext)
            }
            try? modelContext.save()
        } catch FitnessDataError.missingToken {
            // Gebruiker heeft Strava niet gekoppeld — geen reden om te loggen elke launch.
        } catch {
            print("Auto-sync Strava gefaald: \(error.localizedDescription)")
        }
    }

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            // Tab 1: Overzicht (Dashboard & Kalender)
            DashboardView(viewModel: sharedChatViewModel)
                .tabItem {
                    Label("Overzicht", systemImage: "house")
                }
                .tag(AppNavigationState.Tab.dashboard)

            // Tab 2: Doelen — lange-termijn analysecentrum (Epic 23)
            GoalsListView(viewModel: sharedChatViewModel)
                .tabItem {
                    Label("Doelen", systemImage: "scope")
                }
                .tag(AppNavigationState.Tab.goals)

            // Tab 3: Coach — echte tab zodat de TabBar altijd zichtbaar blijft (Sprint 13.4)
            ChatView(viewModel: sharedChatViewModel)
                .tabItem {
                    Label("Coach", systemImage: "bubble.left")
                }
                .tag(AppNavigationState.Tab.coach)

            // Tab 4: Geheugen
            NavigationStack {
                PreferencesListView()
            }
            .tabItem {
                Label("Geheugen", systemImage: "person.and.background.dotted")
            }
            .tag(AppNavigationState.Tab.memory)

            // Tab 5: Instellingen
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
        // SPRINT 13.4: showingChatSheet = true redirecteert nu naar de Coach tab
        // zodat alle bestaande callsites (banners, notificaties, deep links) blijven werken
        // zonder aanpassingen, en de TabBar altijd zichtbaar blijft.
        .onChange(of: appState.showingChatSheet) { _, isShowing in
            if isShowing {
                appState.selectedTab = .coach
                // Reset zodat de trigger opnieuw gebruikt kan worden
                Task { @MainActor in appState.showingChatSheet = false }
            }
        }
        .onAppear {
            sharedChatViewModel.setTrainingPlanManager(planManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerAutoSync"))) { _ in
            performAutoSync()
        }
        // Epic #38 Story 38.1: bij foreground-return prompten voor types die
        // tussendoor `.notDetermined` zijn geworden (bv. iOS-reinstall met
        // gedeeltelijke permission-reset). iOS 17+ two-arg onChange-syntax.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await retriggerHealthKitPermissionsIfNeeded() }
        }
    }
}
