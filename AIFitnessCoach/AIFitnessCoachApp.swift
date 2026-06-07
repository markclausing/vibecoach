import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import Combine

/// Global navigation state of the app.
/// This is used to switch tabs programmatically and to handle deep links
/// or notifications.
@MainActor
class AppNavigationState: ObservableObject {
    /// The available tabs in the application.
    enum Tab {
        case dashboard
        case goals
        case coach
        case memory
        case settings
    }

    /// The currently selected tab.
    @Published var selectedTab: Tab = .dashboard

    /// Determines whether the AI coach bottom sheet is visible, regardless of which tab is active.
    @Published var showingChatSheet: Bool = false

    /// Optional static shared instance for access outside SwiftUI views (e.g. AppDelegate).
    /// Note: This requires that we update the properties on the main thread.
    static let shared = AppNavigationState()

    // Init is public so that Previews can create their own instance.
    init() {}
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Make sure we are the delegate of the notification center to handle in-app (foreground) notifications
        UNUserNotificationCenter.current().delegate = self

        // SPRINT 13.2 — Engine B: Register the BGAppRefreshTask handler.
        // This MUST happen before the end of didFinishLaunching.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: ProactiveNotificationService.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            ProactiveNotificationService.shared.handleEngineBTask(refreshTask)
        }

        // Sprint 19: Skip all permission popups and background engines during UI tests.
        // The simulator has no real HealthKit data and OS alerts would otherwise block the tests.
        guard !ProcessInfo.processInfo.arguments.contains("-isRunningUITests") else {
            return true
        }

        // Sprint 20.2: Permissions are NO longer requested here.
        // The onboarding flow asks for HealthKit and Notifications at the right moment.
        // The background engines only start after the user has completed onboarding
        // (see ContentView.onAppear guard on hasSeenOnboarding).

        // SPRINT 13.2 — Engine A & B: Only start if the user has already completed onboarding.
        // This prevents the engines from being active before the user has even granted permission.
        // Epic #31 Sprint 1: gatekeeper key migrated to `hasCompletedOnboarding` (V2.0 flow).
        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if hasOnboarded {
            ProactiveNotificationService.shared.setupEngineA()
            ProactiveNotificationService.shared.scheduleEngineB()
        }

        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// M-08: whitelist check for incoming notification payloads. Only payloads
    /// with a `type` value from our own proactive coach flow are processed:
    ///   - `"goalRisk"` — Engine A / B: a goal is in the red
    ///   - `"recovery_plan"` — the automatically generated recovery plan is ready
    /// Unknown payloads are silently ignored — this prevents arbitrary
    /// or manipulated pushes from showing a banner or triggering navigation.
    ///
    /// Static pure function so it can be verified standalone in unit tests.
    static func isAllowedNotificationPayload(_ userInfo: [AnyHashable: Any]) -> Bool {
        let allowedTypes: Set<String> = ["goalRisk", "recovery_plan"]
        if let type = userInfo["type"] as? String, allowedTypes.contains(type) {
            return true
        }
        return false
    }

    // This method ensures that notifications are also shown when the app is open in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        guard Self.isAllowedNotificationPayload(userInfo) else {
            // M-08: unknown payload — no banner, no sound.
            print("🚫 Notificatie met onbekende payload genegeerd (willPresent): \(userInfo)")
            completionHandler([])
            return
        }
        print("🔔 Notificatie ontvangen in de voorgrond: \(notification.request.content.title)")
        // Show the notification as a banner (and play a sound)
        completionHandler([.banner, .sound])
    }

    // This method is called when the user ACTUALLY taps on the notification
    // (works when the app was in the background, in the foreground, or was launched from a closed state).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        print("📱 Gebruiker heeft op notificatie getikt!")

        // M-08: check the whitelist first. For unknown payloads we do
        // nothing — no navigation, no side effects.
        guard Self.isAllowedNotificationPayload(userInfo) else {
            print("🚫 Notificatie met onbekende payload genegeerd (didReceive): \(userInfo)")
            completionHandler()
            return
        }

        if let type = userInfo["type"] as? String, type == "goalRisk" || type == "recovery_plan" {
            // SPRINT 13.2 / Epic 23: Proactive coach notification — open the Goals tab
            // where the recovery plan banner is shown.
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
    // AppDelegate is needed for: BGTaskScheduler registration (Engine B) and the
    // UNUserNotificationCenterDelegate callbacks that handle local proactive
    // notifications (Epic 13, Engine A & B).
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// SwiftData container with `AppMigrationPlan` (V1 → V2). Built once in
    /// the app init so we have explicit control over schema, migration plan and
    /// in-memory mode (UI tests). The `.modelContainer(_:)` modifier injects it
    /// into the view hierarchy. On migration failure the init defensively falls back to
    /// a fresh-DB path — see `Self.makeModelContainer()`.
    private let modelContainer: ModelContainer = AIFitnessCoachApp.makeModelContainer()

    /// UserDefaults key that is written as soon as the migration failed and we had to fall back
    /// to a fresh DB. Contains a `Date()`. Views (e.g. Dashboard)
    /// poll via `MigrationFallbackStore` (Epic #51-H) and show a banner.
    static let migrationFallbackKey = MigrationFallbackStore.key

    private static func makeModelContainer() -> ModelContainer {
        let isUITesting: Bool = {
            #if DEBUG
            return ProcessInfo.processInfo.arguments.contains("-UITesting")
            #else
            return false
            #endif
        }()

        let schema = Schema(SchemaV5.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)

        // First attempt: load existing store and run the migration chain (V1 → V2 → V3 → V4 → V5).
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: config
            )
        } catch {
            AppLoggers.fitnessDataService.error("""
                ModelContainer-init met migratieplan faalde: \
                \(error.localizedDescription, privacy: .public). \
                Val terug op fresh DB — FitnessGoal, UserPreference en Symptom \
                records zijn verloren, HK + Strava activities re-syncen vanzelf \
                zodra de app opent.
                """)
        }

        // Fallback: remove the corrupt store and build an empty V4 container.
        // During UI tests we run in-memory (`isStoredInMemoryOnly`), so no
        // file cleanup is needed — skip that step in that case.
        if !isUITesting {
            deleteCorruptStore(at: config.url)
            MigrationFallbackStore().recordFallback()
        }

        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // Unrecoverable: even a fresh DB fails. Crashing is correct behaviour then —
            // something is fundamentally wrong with the Application Support directory or the schema.
            fatalError("ModelContainer-init faalde ook ná fresh-DB-fallback: \(error)")
        }
    }

    /// Removes the SQLite store and the associated WAL/SHM sidecar files so that
    /// SwiftData can create a clean V2 store in the same place on a second init.
    private static func deleteCorruptStore(at url: URL) {
        let basePath = url.path
        for suffix in ["", "-wal", "-shm"] {
            let candidate = URL(fileURLWithPath: basePath + suffix)
            if FileManager.default.fileExists(atPath: candidate.path) {
                try? FileManager.default.removeItem(at: candidate)
            }
        }
    }

    // Listen to the app state (foreground/background)
    @Environment(\.scenePhase) private var scenePhase

    // Global navigation state (for notifications & deep links)
    @StateObject private var appState = AppNavigationState.shared

    // Global shared state for the training plan (Epic 11)
    @StateObject private var planManager = TrainingPlanManager()

    // Epic 29: Global theme engine for the Serene Visual Overhaul
    @StateObject private var themeManager = ThemeManager()

    // Epic #31 Sprint 1: gatekeeper for the V2.0 onboarding flow.
    // When `false` the app shows OnboardingView(); as soon as the last step sets this to `true`
    // the app switches over to the regular main app (ContentView).
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // Epic 30: Color mode setting (light / dark / auto)
    @AppStorage("vibecoach_colorScheme") private var colorSchemeRaw: String = "auto"

    // Epic #37 story 37.5: app language preference. `.system` follows the device locale,
    // so existing users see no forced switch. Drives `.environment(\.locale, …)` below;
    // services read the same key via `AppLanguage.currentLocale`.
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw: String = AppLanguage.system.rawValue

    private var resolvedLocale: Locale {
        (AppLanguage(rawValue: appLanguageRaw) ?? .system).resolvedLocale
    }

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    /// True only in DEBUG builds with the -UITesting launch argument.
    private var isUITestingEnvironment: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UITesting")
        #else
        return false
        #endif
    }

    /// Epic #35: if the XCUITest suite passes `-UITestOpenAICoachConfig`,
    /// we show `AIProviderSettingsView` directly as the root view instead of the
    /// tab host. This way the model-picker E2E test can be driven without
    /// having to navigate through the custom Settings ScrollView (which via
    /// XCUITest turns out to be unreliable because of hit-testing in `SettingsRowV2`).
    private var isDirectAICoachConfigEnvironment: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UITestOpenAICoachConfig")
        #else
        return false
        #endif
    }

    init() {
        // Sprint 26.1: Activate the mock environment if the app was launched via XCUITest.
        // This injects reproducible test data and bypasses live API calls.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            UITestMockEnvironment.setup()
        }
        #endif

        // C-02: move the user AI API key out of UserDefaults
        // to the Keychain once. Idempotent — after migration this is a no-op.
        UserAPIKeyStore.migrateFromUserDefaultsIfNeeded()
        // Epic #53: move the legacy single key to the per-provider Gemini slot.
        // Idempotent — runs after the UserDefaults→Keychain migration above.
        UserAPIKeyStore.migrateToPerProviderKeysIfNeeded()

        // Epic #51-F5: start the NWPathMonitor so that `SyncStatusBanner` immediately
        // has the correct online/offline state at launch. Idempotent.
        Task { @MainActor in
            NetworkReachabilityMonitor.shared.start()
        }
    }

    @ViewBuilder
    private var rootView: some View {
        if isDirectAICoachConfigEnvironment {
            // Epic #35: test-only shortcut — render AIProviderSettingsView
            // as the root view so the picker UITest does not depend on
            // the Settings ScrollView navigation.
            NavigationStack { AIProviderSettingsView() }
        } else {
            ContentView()
        }
    }

    var body: some Scene {
        WindowGroup {
            // ContentView manages the onboarding routing (see Phase 1 cleanup).
            // All env-objects are injected here so that both OnboardingView
            // and AppTabHostView have them available.
            rootView
                .environmentObject(appState)
                .environmentObject(planManager)
                .environmentObject(themeManager)
                .environment(\.locale, resolvedLocale)
                .preferredColorScheme(preferredColorScheme)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && hasCompletedOnboarding {
                        // SPRINT 12.3: Trigger the automatic historical data sync when
                        // the app is open. AppTabHostView listens on TriggerAutoSync.
                        NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoSync"), object: nil)
                    }
                }
        }
        // Sprint 26.1: use an in-memory store during UI tests so that each run
        // starts with an empty database and goals from previous runs do not leak.
        // Tech-debt audit (May 2026): the container is now built manually with
        // `AppMigrationPlan` (see the `modelContainer` property above) so we
        // can explicitly drive V1 → V2 schema migrations.
        .modelContainer(modelContainer)
    }
}
