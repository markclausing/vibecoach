import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppNavigationState

    // We maken de ViewModel hier aan zodat we hem kunnen delen met de DashboardView
    // voor pull-to-refresh en de ChatView als overlay.
    @StateObject private var sharedChatViewModel = ChatViewModel()

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            // Tab 1: Overzicht (Dashboard & Kalender)
            DashboardView(viewModel: sharedChatViewModel)
                .tabItem {
                    Label("Overzicht", systemImage: "house.fill")
                }
                .tag(AppNavigationState.Tab.dashboard)

            // Tab 2: Doelen
            GoalsListView()
                .tabItem {
                    Label("Doelen", systemImage: "target")
                }
                .tag(AppNavigationState.Tab.goals)

            // Tab 3: Geheugen
            NavigationStack {
                PreferencesListView()
            }
            .tabItem {
                Label("Geheugen", systemImage: "brain.head.profile")
            }
            .tag(AppNavigationState.Tab.memory)

            // Tab 4: Instellingen
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Instellingen", systemImage: "gearshape.fill")
            }
            .tag(AppNavigationState.Tab.settings)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppNavigationState())
}
