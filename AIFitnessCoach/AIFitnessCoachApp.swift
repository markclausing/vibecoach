import SwiftUI
import SwiftData
import UserNotifications
import Combine

/// Globale navigatiestatus van de app.
/// Dit wordt gebruikt om programmatisch van tabblad te wisselen en diepe links
/// of notificaties af te handelen.
@MainActor
class AppNavigationState: ObservableObject {
    /// De beschikbare tabbladen in de applicatie.
    enum Tab {
        case dashboard
        case goals
        case coach
        case memory
        case settings
    }

    /// Het momenteel geselecteerde tabblad.
    @Published var selectedTab: Tab = .dashboard

    /// Een eventueel specifiek Strava Activity ID dat vanuit een notificatie
    /// is meegegeven en geanalyseerd moet worden door de coach.
    @Published var targetActivityId: Int64? = nil

    /// Bepaalt of de AI coach bottom sheet zichtbaar is, ongeacht welk tabblad actief is.
    @Published var showingChatSheet: Bool = false

    /// Optionele statische shared instance voor toegang buiten SwiftUI views (bijv. AppDelegate).
    /// Let op: Dit vereist dat we de properties updaten op de main thread.
    static let shared = AppNavigationState()

    // Init is public zodat Previews een eigen instance kunnen maken.
    init() {}

    /// Stelt de app in om een specifieke activiteit in het Dashboard / Coach scherm te openen.
    nonisolated func openActivityAnalysis(activityId: Int64) {
        Task { @MainActor in
            self.selectedTab = .dashboard
            self.targetActivityId = activityId
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Zorg dat we delegate zijn van het notification center om in-app (foreground) notificaties af te handelen
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Wordt aangeroepen wanneer de app succesvol een APNs token heeft ontvangen
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        print("✅ APNs Device Token ontvangen!")
        print("Kopieer dit token naar je backend .env bestand onder TEST_DEVICE_TOKEN:")
        print("--------------------------------------------------")
        print(token)
        print("--------------------------------------------------")
    }

    // Wordt aangeroepen als er iets misgaat bij het registreren voor APNs
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Fout bij registreren voor Push Notifications: \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Deze methode zorgt ervoor dat notificaties ook getoond worden als de app op de voorgrond (foreground) open is.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("🔔 Notificatie ontvangen in de voorgrond: \(notification.request.content.title)")
        // Toon de notificatie als een banner (en speel geluid af)
        completionHandler([.banner, .sound])
    }

    // Deze methode wordt aangeroepen wanneer de gebruiker DAADWERKELIJK op de notificatie tikt
    // (werkt als de app op de achtergrond zat, in de voorgrond is, of vanuit gesloten toestand is gestart).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        print("📱 Gebruiker heeft op notificatie getikt!")

        // Haal het activityId uit de payload
        if let activityId = userInfo["activityId"] as? Int64 {
            print("  ➡️ Strava Activity ID gedetecteerd in payload: \(activityId)")

            // Trigger navigatie & analyse via onze globale AppNavigationState
            AppNavigationState.shared.openActivityAnalysis(activityId: activityId)
        } else if let activityIdString = userInfo["activityId"] as? String, let activityId = Int64(activityIdString) {
            print("  ➡️ Strava Activity ID (String) gedetecteerd in payload: \(activityId)")
            AppNavigationState.shared.openActivityAnalysis(activityId: activityId)
        } else {
            print("  ⚠️ Geen geldig activityId gevonden in payload: \(userInfo)")
        }

        completionHandler()
    }
}

@main
struct AIFitnessCoachApp: App {
    // Inject the custom AppDelegate voor APNs en Push Notifications (Fase 5)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Luister naar de app status (foreground/background)
    @Environment(\.scenePhase) private var scenePhase

    // Globale navigatiestatus (voor notificaties & deep links)
    @StateObject private var appState = AppNavigationState.shared

    // Globale shared state voor het trainingsschema (Epic 11)
    @StateObject private var planManager = TrainingPlanManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(planManager)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        // SPRINT 12.3: Trigger de automatische historische datasync wanneer de app open is.
                        // We sturen hiervoor een notificatie, zodat ContentView dit netjes afhandelt met context toegang.
                        NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoSync"), object: nil)
                    }
                }
        }
        .modelContainer(for: [FitnessGoal.self, ActivityRecord.self, UserPreference.self]) // Voeg SwiftData containers toe
    }
}
