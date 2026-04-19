import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
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

        // SPRINT 13.2 — Engine B: Registreer de BGAppRefreshTask handler.
        // Dit MOET vóór het einde van didFinishLaunching gebeuren.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: ProactiveNotificationService.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            ProactiveNotificationService.shared.handleEngineBTask(refreshTask)
        }

        // Sprint 19: Sla alle toestemming-popups en achtergrond-engines over tijdens UI-tests.
        // De simulator heeft geen echte HealthKit-data en OS-alerts blokkeren anders de tests.
        guard !ProcessInfo.processInfo.arguments.contains("-isRunningUITests") else {
            return true
        }

        // Sprint 20.2: Toestemmingen worden NIET meer hier uitgevraagd.
        // De onboarding-flow vraagt HealthKit en Notificaties op het juiste moment.
        // De achtergrond-engines starten pas nadat de gebruiker de onboarding heeft afgerond
        // (zie ContentView.onAppear-guard op hasSeenOnboarding).

        // SPRINT 13.2 — Engine A & B: Starten alleen als de gebruiker onboarding al heeft afgerond.
        // Dit voorkomt dat de engines actief zijn voordat de gebruiker überhaupt permissie heeft gegeven.
        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
        if hasOnboarded {
            ProactiveNotificationService.shared.setupEngineA()
            ProactiveNotificationService.shared.scheduleEngineB()
        }

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

        // Haal het activityId uit de payload (Strava webhook notificaties)
        if let activityId = userInfo["activityId"] as? Int64 {
            print("  ➡️ Strava Activity ID gedetecteerd in payload: \(activityId)")
            AppNavigationState.shared.openActivityAnalysis(activityId: activityId)
        } else if let activityIdString = userInfo["activityId"] as? String, let activityId = Int64(activityIdString) {
            print("  ➡️ Strava Activity ID (String) gedetecteerd in payload: \(activityId)")
            AppNavigationState.shared.openActivityAnalysis(activityId: activityId)
        } else if let type = userInfo["type"] as? String, type == "goalRisk" {
            // SPRINT 13.2 / Epic 23: Proactieve coach-notificatie — open de Doelen tab
            // De herstelplan-banner staat nu in de Doelen tab, niet op het Dashboard.
            print("  ➡️ Doel-risico notificatie gedetecteerd — Doelen tab openen")
            Task { @MainActor in
                AppNavigationState.shared.selectedTab = .goals
            }
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

    // Epic 29: Globale theme-engine voor de Serene Visual Overhaul
    @StateObject private var themeManager = ThemeManager()

    // Sprint 20.2: Bepaalt of de onboarding al is afgerond.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    // Epic 30: Kleurmodus instelling (light / dark / auto)
    @AppStorage("vibecoach_colorScheme") private var colorSchemeRaw: String = "auto"

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    /// True alleen in DEBUG builds met het -UITesting launch argument.
    private var isUITestingEnvironment: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UITesting")
        #else
        return false
        #endif
    }

    init() {
        // Sprint 26.1: Activeer de mock-omgeving als de app via XCUITest gestart is.
        // Dit injecteert reproduceerbare testdata en bypassed live API-calls.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            UITestMockEnvironment.setup()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenOnboarding {
                    ContentView()
                        .environmentObject(appState)
                        .environmentObject(planManager)
                        .environmentObject(themeManager)
                } else {
                    OnboardingView()
                }
            }
            .preferredColorScheme(preferredColorScheme)
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active && hasSeenOnboarding {
                    // SPRINT 12.3: Trigger de automatische historische datasync wanneer de app open is.
                    // We sturen hiervoor een notificatie, zodat ContentView dit netjes afhandelt met context toegang.
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoSync"), object: nil)
                }
            }
            .onChange(of: hasSeenOnboarding) { _, isOnboarded in
                // Sprint 20.2: Zodra de onboarding is afgerond, starten we de achtergrond-engines.
                // Dit is het eerste moment dat de gebruiker permissies heeft gegeven.
                if isOnboarded {
                    ProactiveNotificationService.shared.setupEngineA()
                    ProactiveNotificationService.shared.scheduleEngineB()
                }
            }
        }
        // Sprint 26.1: gebruik in-memory store tijdens UI-tests zodat elke run
        // met een lege database start en goals van vorige runs niet lekken.
        .modelContainer(for: [FitnessGoal.self, ActivityRecord.self, UserPreference.self, DailyReadiness.self, Symptom.self], inMemory: isUITestingEnvironment) // Epic 18: Symptom toegevoegd
    }
}
