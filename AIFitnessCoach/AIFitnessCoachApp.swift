import SwiftUI
import SwiftData

@main
struct AIFitnessCoachApp: App {
    // Inject the custom AppDelegate voor APNs en Push Notifications (Fase 5)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: FitnessGoal.self) // Voeg SwiftData container toe voor lokale doelen tracking
    }
}
