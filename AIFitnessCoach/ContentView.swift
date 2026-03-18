import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppNavigationState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            // Tab 1: Coach (Huidige Chat Interface)
            ChatView()
                .tabItem {
                    Label("Coach", systemImage: "message.fill")
                }
                .tag(AppNavigationState.Tab.coach)

            // Tab 2: Doelen
            GoalsListView()
                .tabItem {
                    Label("Doelen", systemImage: "flag.fill")
                }
                .tag(AppNavigationState.Tab.goals)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppNavigationState())
}
