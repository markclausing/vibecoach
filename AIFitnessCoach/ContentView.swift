import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ChatView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        }
    }
}

#Preview {
    ContentView()
}
