import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            // Tab 1: Coach (Huidige Chat Interface)
            ChatView()
                .tabItem {
                    Label("Coach", systemImage: "message.fill")
                }

            // Tab 2: Doelen
            GoalsListView()
                .tabItem {
                    Label("Doelen", systemImage: "flag.fill")
                }
        }
    }
}

#Preview {
    ContentView()
}
