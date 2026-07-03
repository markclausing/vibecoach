import SwiftUI
import SwiftData
import UserNotifications

/// Epic #31 — Sprint 31.6: V2.0 Onboarding flow, aligned with the final
/// UX prototype.
///
/// Five steps, each with its own mood:
/// 1. Welcome — brand + promise
/// 2. How it works — Vibe Score (recovery) + TRIMP (load) preview
/// 3. Your AI — BYOK provider choice (the key comes later in Settings)
/// 4. Apple Health — HRV + Sleep permission (Permission 1 of 2)
/// 5. Notifications — Coach-signals permission (Permission 2 of 2)
///
/// All screens share `OnboardingTemplateView` so that typography, progress bar
/// and button layout stay consistent. The visual style (cards with
/// `cornerRadius 16`, soft shadow) matches the main Dashboard.
struct OnboardingView: View {

    // MARK: - Persistent state

    /// Set to true once the user finishes onboarding (step 5).
    @AppStorage(AppStorageKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    /// Sprint 31.6: chosen AI provider — shared key with `AIProviderSettingsView`
    /// so that `ChatViewModel` picks it up directly. The actual API key
    /// is entered later in Settings (the prototype only shows the provider choice).
    @AppStorage("vibecoach_aiProvider") private var providerRaw: String = AIProvider.gemini.rawValue

    // MARK: - Transient UI state

    @State private var currentStep: Int = 1
    @State private var healthKitState: PermissionState = .idle
    @State private var notificationsState: PermissionState = .idle
    /// Epic #62 story 62.3: skipping HealthKit must be a conscious choice, not a silent tap.
    @State private var showHealthKitSkipConfirm = false

    private let totalSteps = 5

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext

    // MARK: - Body

    var body: some View {
        TabView(selection: $currentStep) {
            stepOne.tag(1)
            stepTwo.tag(2)
            stepThree.tag(3)
            stepFour.tag(4)
            stepFive.tag(5)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: currentStep)
        // Epic #62 story 62.3: HealthKit is the basis for the Vibe Score, so skipping it is an
        // explicit confirmation rather than a silent secondary tap. Notifications stay freely optional.
        .confirmationDialog("Apple Health overslaan?",
                            isPresented: $showHealthKitSkipConfirm,
                            titleVisibility: .visible) {
            Button("Toch overslaan", role: .destructive) { advance() }
            Button("Terug", role: .cancel) { }
        } message: {
            Text("Zonder Apple Health kan VibeCoach je Vibe Score en herstel niet berekenen. Je kunt het later koppelen via Instellingen.")
        }
    }

    // MARK: - Step 1: Welcome

    private var stepOne: some View {
        OnboardingTemplateView(
            stepIndex: 1,
            totalSteps: totalSteps,
            eyebrow: nil,
            title: "Je lichaam stuurt, wij luisteren mee.",
            subtitle: "Je persoonlijke trainingscoach, gestuurd door je eigen Apple Health data.",
            content: { WelcomeBrandMark() },
            primaryButtonTitle: "Aan de slag",
            primaryAction: advance,
            secondaryButtonTitle: nil,
            secondaryAction: nil
        )
    }

    // MARK: - Step 2: How it works

    private var stepTwo: some View {
        OnboardingTemplateView(
            stepIndex: 2,
            totalSteps: totalSteps,
            eyebrow: "TWEE LAGEN",
            eyebrowColor: themeManager.primaryAccentColor,
            title: "Herstel meten, belasting plannen.",
            subtitle: "VibeCoach leest twee signalen: hoe je lichaam herstelt en hoe zwaar je traint. Samen bepalen ze wat vandaag verstandig is.",
            content: { TwoLayersPreview() },
            primaryButtonTitle: "Volgende",
            primaryAction: advance,
            secondaryButtonTitle: nil,
            secondaryAction: nil
        )
    }

    // MARK: - Step 3: Your AI

    private var stepThree: some View {
        OnboardingTemplateView(
            stepIndex: 3,
            totalSteps: totalSteps,
            eyebrow: "PRIVACY EERST",
            eyebrowColor: themeManager.primaryAccentColor,
            title: "Jouw data, jouw AI-sleutel.",
            subtitle: "VibeCoach gebruikt jouw eigen API-sleutel. Zo blijven je gesprekken en trainingsdata van jou — wij zien ze nooit.",
            content: { AIProviderPrivacyContent(providerRaw: $providerRaw) },
            primaryButtonTitle: "Volgende",
            primaryAction: advance,
            secondaryButtonTitle: "Sla over, doe later",
            secondaryAction: advance
        )
    }

    // MARK: - Step 4: Apple Health

    private var stepFour: some View {
        OnboardingTemplateView(
            stepIndex: 4,
            totalSteps: totalSteps,
            eyebrow: "PERMISSIE 1 VAN 2",
            eyebrowColor: .red,
            title: "Koppel met Apple Health.",
            subtitle: "VibeCoach leest HRV en slaap uit Apple Health — die blijven op jouw iPhone. We sturen niets naar externe servers.",
            content: { AppleHealthPermissionContent(state: healthKitState) },
            primaryButtonTitle: primaryTitle(for: healthKitState, grantLabel: "Koppel Apple Health"),
            primaryAction: handleHealthKitAction,
            secondaryButtonTitle: "Nu niet, later in Instellingen",
            secondaryAction: { showHealthKitSkipConfirm = true }
        )
    }

    // MARK: - Step 5: Notifications

    private var stepFive: some View {
        OnboardingTemplateView(
            stepIndex: 5,
            totalSteps: totalSteps,
            eyebrow: "PERMISSIE 2 VAN 2",
            eyebrowColor: .red,
            title: "Coach-signalen, niet meer.",
            subtitle: "We sturen alleen een bericht als je lichaam afwijkt van je plan — gemiddeld één keer per week, nooit meer dan één per doel per dag.",
            content: { NotificationPermissionContent(accentColor: themeManager.primaryAccentColor) },
            primaryButtonTitle: primaryTitle(for: notificationsState, grantLabel: "Sta notificaties toe"),
            primaryAction: handleNotificationAction,
            secondaryButtonTitle: "Overslaan",
            secondaryAction: completeOnboarding
        )
    }

    // MARK: - Button title per permission state

    private func primaryTitle(for state: PermissionState, grantLabel: String) -> String {
        switch state {
        case .idle:       return grantLabel
        case .requesting: return "Even geduld…"
        case .granted:    return "Volgende"
        case .failed:     return "Probeer opnieuw"
        }
    }

    // MARK: - Step 4 logic (HealthKit)

    private func handleHealthKitAction() {
        switch healthKitState {
        case .granted:
            advance()
        case .requesting:
            return
        case .idle, .failed:
            requestHealthKit()
        }
    }

    private func requestHealthKit() {
        healthKitState = .requesting

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            healthKitState = .granted
            startEngineA()
            return
        }
        #endif

        Task {
            do {
                _ = try await HealthKitManager.shared.requestOnboardingPermissions()
                await MainActor.run {
                    healthKitState = .granted
                    startEngineA()
                }
            } catch {
                await MainActor.run {
                    healthKitState = .failed
                }
            }
        }
    }

    /// Sprint 31.2 (§4 Dual Engine): Start Engine A once HealthKit permission is granted.
    /// Calendar-based check on `Calendar.current.startOfDay(for:)` (Rule §3).
    private func startEngineA() {
        ProactiveNotificationService.shared.setupEngineA()
        let startOfToday = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(startOfToday, forKey: "vibecoach_engineAStartedAt")
    }

    // MARK: - Step 5 logic (Notifications)

    private func handleNotificationAction() {
        switch notificationsState {
        case .granted:
            completeOnboarding()
        case .requesting:
            return
        case .idle, .failed:
            requestNotifications()
        }
    }

    private func requestNotifications() {
        notificationsState = .requesting

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            notificationsState = .granted
            completeOnboarding()
            return
        }
        #endif

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            Task { @MainActor in
                notificationsState = granted ? .granted : .failed
                if granted {
                    completeOnboarding()
                }
            }
        }
    }

    // MARK: - Navigation

    private func advance() {
        guard currentStep < totalSteps else {
            completeOnboarding()
            return
        }
        withAnimation { currentStep += 1 }
    }

    /// Sprint 31.6: Persist onboarding choices and move the app forward.
    ///
    /// The V2.0 flow does not store a fitness goal — the API key is set later in
    /// Settings (BYOK). We only write the onboarding date
    /// to SwiftData so other features have an anchor date.
    private func completeOnboarding() {
        persistUserConfiguration()
        Haptics.impact(.medium)
        hasCompletedOnboarding = true
    }

    private func persistUserConfiguration() {
        // Replace any existing configuration — we always onboard a single profile only.
        let descriptor = FetchDescriptor<UserConfiguration>()
        if let existing = try? modelContext.fetch(descriptor) {
            for record in existing {
                modelContext.delete(record)
            }
        }

        modelContext.insert(UserConfiguration(date: Date()))

        do {
            try modelContext.save()
        } catch {
            AppLoggers.userProfile.error("UserConfiguration save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Permission state

enum PermissionState {
    case idle, requesting, granted, failed
}
