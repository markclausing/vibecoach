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
    @AppStorage("selectedDataSource") private var selectedDataSource: DataSource = .healthKit
    @Environment(\.modelContext) private var modelContext
    private let fitnessDataService = FitnessDataService()

    /// Guard tegen gelijktijdige auto-sync runs (race condition fix voor duplicate records).
    @State private var isAutoSyncing = false

    /// Voert asynchroon de data-synchronisatie voor de afgelopen 14 dagen uit op de achtergrond.
    private func performAutoSync() {
        guard !isAutoSyncing else {
            print("⚠️ Auto-sync overgeslagen: vorige sync is nog actief")
            return
        }
        isAutoSyncing = true
        Task {
            defer { Task { @MainActor in isAutoSyncing = false } }
            do {
                if selectedDataSource == .healthKit {
                    let syncService = HealthKitSyncService()
                    try await syncService.syncHistoricalWorkouts(to: modelContext) // Note: HealthKitSyncService by default is fast if already authorized
                } else {
                    // Strava API (Alleen laatste 14 dagen ophalen om API limieten en laadtijden kort te houden voor de Burn Rate graph)
                    let activities = try await fitnessDataService.fetchRecentActivities(days: 14)

                    await MainActor.run {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        let fallbackFormatter = ISO8601DateFormatter()

                        for activity in activities {
                            let currentId = String(activity.id)
                            let fetchDescriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.id == currentId })
                            let existing = try? modelContext.fetch(fetchDescriptor)

                            if existing?.isEmpty ?? true {
                                let date = formatter.date(from: activity.start_date) ?? fallbackFormatter.date(from: activity.start_date) ?? Date()

                                // SPRINT 12.4: Voeg basic TRIMP fallback toe bij sync
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
                                    id: currentId,
                                    name: activity.name,
                                    distance: activity.distance,
                                    movingTime: activity.moving_time,
                                    averageHeartrate: activity.average_heartrate,
                                    sportCategory: SportCategory.from(rawString: activity.type),
                                    startDate: date,
                                    trimp: basicTRIMPFallback, // In a real app we could recalculate the local TRIMP hier via PhysiologicalCalculator if missing
                                    deviceWatts: activity.device_watts
                                )
                                modelContext.insert(record)
                            }
                        }
                        try? modelContext.save()
                    }
                }
            } catch {
                print("Auto-sync gefaald op de achtergrond: \(error)")
            }
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
    }
}
