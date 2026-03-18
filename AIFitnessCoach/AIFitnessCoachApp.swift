import SwiftUI

@main
struct AIFitnessCoachApp: App {
    // Koppeling naar de App Delegate voor APNs (Apple Push Notifications) events
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Globale notificatie manager, beschikbaar voor dependency injection in views
    @StateObject private var notificationManager = NotificationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notificationManager)
                .onAppear {
                    // Check initial permission status silently upon launch without prompting the user.
                    notificationManager.checkAuthorizationStatus()
                }
        }
    }
}
