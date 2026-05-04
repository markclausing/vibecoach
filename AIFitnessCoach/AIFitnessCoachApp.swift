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

    /// Bepaalt of de AI coach bottom sheet zichtbaar is, ongeacht welk tabblad actief is.
    @Published var showingChatSheet: Bool = false

    /// Optionele statische shared instance voor toegang buiten SwiftUI views (bijv. AppDelegate).
    /// Let op: Dit vereist dat we de properties updaten op de main thread.
    static let shared = AppNavigationState()

    // Init is public zodat Previews een eigen instance kunnen maken.
    init() {}
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
        // Epic #31 Sprint 1: poortwachter-key gemigreerd naar `hasCompletedOnboarding` (V2.0 flow).
        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if hasOnboarded {
            ProactiveNotificationService.shared.setupEngineA()
            ProactiveNotificationService.shared.scheduleEngineB()
        }

        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// M-08: whitelist-check voor inkomende notificatie-payloads. Alleen payloads
    /// met een `type`-waarde uit onze eigen proactieve coach-flow worden verwerkt:
    ///   - `"goalRisk"` — Engine A / B: een doel staat op rood
    ///   - `"recovery_plan"` — het automatisch gegenereerde herstelplan is klaar
    /// Onbekende payloads worden stil genegeerd — dit voorkomt dat willekeurige
    /// of gemanipuleerde pushes een banner tonen of navigatie triggeren.
    ///
    /// Static pure functie zodat hij los in unit-tests kan worden geverifieerd.
    static func isAllowedNotificationPayload(_ userInfo: [AnyHashable: Any]) -> Bool {
        let allowedTypes: Set<String> = ["goalRisk", "recovery_plan"]
        if let type = userInfo["type"] as? String, allowedTypes.contains(type) {
            return true
        }
        return false
    }

    // Deze methode zorgt ervoor dat notificaties ook getoond worden als de app op de voorgrond (foreground) open is.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        guard Self.isAllowedNotificationPayload(userInfo) else {
            // M-08: onbekende payload — geen banner, geen geluid.
            print("🚫 Notificatie met onbekende payload genegeerd (willPresent): \(userInfo)")
            completionHandler([])
            return
        }
        print("🔔 Notificatie ontvangen in de voorgrond: \(notification.request.content.title)")
        // Toon de notificatie als een banner (en speel geluid af)
        completionHandler([.banner, .sound])
    }

    // Deze methode wordt aangeroepen wanneer de gebruiker DAADWERKELIJK op de notificatie tikt
    // (werkt als de app op de achtergrond zat, in de voorgrond is, of vanuit gesloten toestand is gestart).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        print("📱 Gebruiker heeft op notificatie getikt!")

        // M-08: controleer eerst de whitelist. Bij onbekende payloads doen we
        // niets — geen navigatie, geen neveneffecten.
        guard Self.isAllowedNotificationPayload(userInfo) else {
            print("🚫 Notificatie met onbekende payload genegeerd (didReceive): \(userInfo)")
            completionHandler()
            return
        }

        if let type = userInfo["type"] as? String, type == "goalRisk" || type == "recovery_plan" {
            // SPRINT 13.2 / Epic 23: Proactieve coach-notificatie — open de Doelen tab
            // waar de herstelplan-banner staat.
            print("  ➡️ Proactieve notificatie (\(type)) — Doelen tab openen")
            Task { @MainActor in
                AppNavigationState.shared.selectedTab = .goals
            }
        }

        completionHandler()
    }
}

@main
struct AIFitnessCoachApp: App {
    // AppDelegate is nodig voor: BGTaskScheduler-registratie (Engine B) en de
    // UNUserNotificationCenterDelegate-callbacks die lokale proactieve
    // notificaties afhandelen (Epic 13, Engine A & B).
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// SwiftData-container met `AppMigrationPlan` (V1 → V2). Eenmalig opgebouwd in
    /// de app-init zodat we expliciet controle hebben over schema, migratie-plan en
    /// in-memory mode (UI-tests). De `.modelContainer(_:)`-modifier injecteert hem
    /// in de view-hierarchie.
    private let modelContainer: ModelContainer = {
        let isUITesting: Bool = {
            #if DEBUG
            return ProcessInfo.processInfo.arguments.contains("-UITesting")
            #else
            return false
            #endif
        }()

        do {
            let schema = Schema(SchemaV2.models)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: config
            )
        } catch {
            fatalError("Kon ModelContainer niet initialiseren: \(error)")
        }
    }()

    // Luister naar de app status (foreground/background)
    @Environment(\.scenePhase) private var scenePhase

    // Globale navigatiestatus (voor notificaties & deep links)
    @StateObject private var appState = AppNavigationState.shared

    // Globale shared state voor het trainingsschema (Epic 11)
    @StateObject private var planManager = TrainingPlanManager()

    // Epic 29: Globale theme-engine voor de Serene Visual Overhaul
    @StateObject private var themeManager = ThemeManager()

    // Epic #31 Sprint 1: poortwachter voor de V2.0 onboarding-flow.
    // Wanneer `false` toont de app OnboardingView(); zodra de laatste stap dit op `true` zet
    // schakelt de app over naar de reguliere hoofd-app (ContentView).
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

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

    /// Epic #35: als de XCUITest-suite `-UITestOpenAICoachConfig` meegeeft,
    /// tonen we `AIProviderSettingsView` direct als rootview i.p.v. de
    /// tab-host. Zo kan de model-picker E2E-test worden gedreven zonder
    /// door de custom Settings-ScrollView te hoeven navigeren (wat via
    /// XCUITest niet betrouwbaar blijkt vanwege hit-testing in `SettingsRowV2`).
    private var isDirectAICoachConfigEnvironment: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UITestOpenAICoachConfig")
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

        // C-02: verplaats de user AI API-sleutel eenmalig uit UserDefaults
        // naar de Keychain. Idempotent — na migratie is dit een no-op.
        UserAPIKeyStore.migrateFromUserDefaultsIfNeeded()
    }

    @ViewBuilder
    private var rootView: some View {
        if isDirectAICoachConfigEnvironment {
            // Epic #35: test-only shortcut — render AIProviderSettingsView
            // als rootview zodat de picker-UITest niet afhankelijk is van
            // de Settings-ScrollView-navigatie.
            NavigationStack { AIProviderSettingsView() }
        } else {
            ContentView()
        }
    }

    var body: some Scene {
        WindowGroup {
            // ContentView beheert de onboarding-routing (zie Fase 1 cleanup).
            // Alle env-objects worden hier geïnjecteerd zodat zowel OnboardingView
            // als AppTabHostView ze ter beschikking hebben.
            rootView
                .environmentObject(appState)
                .environmentObject(planManager)
                .environmentObject(themeManager)
                .preferredColorScheme(preferredColorScheme)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && hasCompletedOnboarding {
                        // SPRINT 12.3: Trigger de automatische historische datasync wanneer
                        // de app open is. AppTabHostView luistert op TriggerAutoSync.
                        NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoSync"), object: nil)
                    }
                }
        }
        // Sprint 26.1: gebruik in-memory store tijdens UI-tests zodat elke run
        // met een lege database start en goals van vorige runs niet lekken.
        // Tech-debt audit (mei 2026): container wordt nu manueel opgebouwd met
        // `AppMigrationPlan` (zie `modelContainer`-property hierboven) zodat we
        // V1 → V2 schema-migraties expliciet kunnen sturen.
        .modelContainer(modelContainer)
    }
}
