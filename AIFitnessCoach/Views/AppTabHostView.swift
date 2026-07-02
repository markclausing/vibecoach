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

    /// Epic #65 story 65.4: the whole auto-sync pipeline (HK + Strava fan-out, weather
    /// enrichment, per-source status writes, concurrency guard, foreground permission
    /// retrigger) now lives in `AutoSyncCoordinator`. This view only owns the instance and
    /// fires one-line triggers. Created lazily in `.onAppear` because the coordinator needs
    /// the environment `modelContext`, which is not available at property-init time. Held in
    /// `@State` so the single instance (and its in-flight guard) survives re-renders.
    @State private var syncCoordinator: AutoSyncCoordinator?

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
            sharedChatViewModel.context.configure(with: modelContext)
            // Epic #65 story 65.4: lazily build the coordinator once the environment
            // modelContext is available. A single instance keeps the in-flight guard alive.
            if syncCoordinator == nil {
                syncCoordinator = AutoSyncCoordinator(modelContext: modelContext)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerAutoSync)) { _ in
            syncCoordinator?.performAutoSync()
        }
        // Epic #38 Story 38.1: on foreground return, prompt for types that
        // have become `.notDetermined` in the meantime (e.g. iOS reinstall with
        // partial permission reset). iOS 17+ two-arg onChange syntax.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await syncCoordinator?.retriggerHealthKitPermissionsIfNeeded() }
        }
    }
}
