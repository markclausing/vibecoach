import SwiftUI
import SwiftData

@main
struct AIFitnessCoachApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: FitnessGoal.self) // Voeg SwiftData container toe voor lokale doelen tracking
    }
}
