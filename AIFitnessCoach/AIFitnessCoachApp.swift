import SwiftUI

@main
struct AIFitnessCoachApp: App {
    // Koppel de AppDelegate aan de SwiftUI levenscyclus
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
