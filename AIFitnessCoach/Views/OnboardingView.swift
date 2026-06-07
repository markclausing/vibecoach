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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Sprint 31.6: chosen AI provider — shared key with `AIProviderSettingsView`
    /// so that `ChatViewModel` picks it up directly. The actual API key
    /// is entered later in Settings (the prototype only shows the provider choice).
    @AppStorage("vibecoach_aiProvider") private var providerRaw: String = AIProvider.gemini.rawValue

    // MARK: - Transient UI state

    @State private var currentStep: Int = 1
    @State private var healthKitState: PermissionState = .idle
    @State private var notificationsState: PermissionState = .idle

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
            secondaryAction: advance
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
            print("⚠️ UserConfiguration save mislukt: \(error.localizedDescription)")
        }
    }
}

// MARK: - Permission state

private enum PermissionState {
    case idle, requesting, granted, failed
}

// MARK: - Step 1: Welcome visual

/// Large rounded 'brand mark' with a waveform icon in moss green, followed
/// by the uppercase brand word "VIBECOACH". Matches the prototype.
private struct WelcomeBrandMark: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(themeManager.primaryAccentColor)
                    .frame(width: 128, height: 128)
                    .shadow(color: themeManager.primaryAccentColor.opacity(0.35), radius: 20, x: 0, y: 10)

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("VIBECOACH")
                .font(.subheadline)
                .fontWeight(.semibold)
                .kerning(3.0)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Step 2: Two layers preview

/// Two preview cards side by side: on the left the Vibe Score (ring), on the right the
/// TRIMP trend (bars). Same card style as the Dashboard.
private struct TwoLayersPreview: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            VibeScorePreviewCard(accent: themeManager.primaryAccentColor)
            TRIMPPreviewCard(accent: themeManager.primaryAccentColor)
        }
        .padding(.horizontal, 24)
    }
}

private struct VibeScorePreviewCard: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VIBE SCORE")
                .font(.caption2)
                .fontWeight(.semibold)
                .kerning(1.0)
                .foregroundColor(.secondary)

            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 8)
                    .frame(width: 86, height: 86)

                Circle()
                    .trim(from: 0, to: 0.76)
                    .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 86, height: 86)

                VStack(spacing: 0) {
                    Text("76")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.primary)
                    Text("vandaag")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Text("Herstel")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(.label).opacity(0.07), radius: 10, x: 0, y: 3)
    }
}

private struct TRIMPPreviewCard: View {
    let accent: Color

    /// Fourteen placeholder data points for the preview bars (normalized 0…1).
    private let bars: [CGFloat] = [0.35, 0.48, 0.30, 0.62, 0.55, 0.70, 0.40,
                                   0.58, 0.72, 0.45, 0.65, 0.80, 0.55, 0.68]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRIMP")
                .font(.caption2)
                .fontWeight(.semibold)
                .kerning(1.0)
                .foregroundColor(.secondary)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(bars.indices, id: \.self) { index in
                    Capsule()
                        .fill(accent.opacity(0.55 + (bars[index] * 0.45)))
                        .frame(width: 6, height: 50 * bars[index])
                }
            }
            .frame(height: 50, alignment: .bottom)
            .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("112")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                Text("/ dag")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Belasting")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(.label).opacity(0.07), radius: 10, x: 0, y: 3)
    }
}

// MARK: - Step 3: AI-provider privacy content

/// Info block with "Waarom je eigen sleutel?" (blue tinted) followed by a
/// segmented picker for the provider. The actual API key comes later
/// in Settings — that matches the prototype.
private struct AIProviderPrivacyContent: View {
    @Binding var providerRaw: String
    @State private var keyHelpURL: IdentifiableURL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Info card, blue tinted.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        Text("Waarom je eigen sleutel?")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    Text("Je gesprekken gaan rechtstreeks naar je gekozen AI-provider — niet via onze servers. Je houdt zelf de controle over kosten, model en privacy.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Provider picker.
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI PROVIDER")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .kerning(1.0)
                        .foregroundColor(.secondary)

                    Picker("Provider", selection: $providerRaw) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.shortName).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("OnboardingProviderPicker")

                    if let provider = AIProvider(rawValue: providerRaw), let url = provider.getKeyURL {
                        Button("Hoe kom ik aan een \(provider.shortName)-sleutel? →") {
                            keyHelpURL = IdentifiableURL(url: url)
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }

                    Text("Je kunt de sleutel zelf later invoeren in Instellingen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
        .sheet(item: $keyHelpURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Step 4: Apple Health permission content

private struct AppleHealthPermissionContent: View {
    let state: PermissionState
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HealthDataCard(
                    icon: "waveform.path.ecg.rectangle.fill",
                    iconTint: themeManager.primaryAccentColor,
                    title: "Hartslagvariabiliteit",
                    subtitle: "Meet je autonome herstel — de hoeksteen van je Vibe Score.",
                    isGranted: state == .granted
                )

                HealthDataCard(
                    icon: "moon.stars.fill",
                    iconTint: themeManager.primaryAccentColor,
                    title: "Slaap",
                    subtitle: "Fase-opdeling (REM / diep / licht) voor betere trainingsadviezen.",
                    isGranted: state == .granted
                )

                // Expectation bubble — matches prototype.
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.footnote)
                    Text("Je ziet zo een Apple-dialoog waarin je per type data toegang geeft.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if case .failed = state {
                    Text("Toestemming mislukt — je kunt het nu opnieuw proberen of later via Instellingen koppelen.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
    }
}

private struct HealthDataCard: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconTint.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconTint)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Epic #37 story 37.1c: title/subtitle are String params (Dutch literals) -> catalog.
                Text(LocalizedStringKey(title))
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(LocalizedStringKey(subtitle))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(.label).opacity(0.07), radius: 10, x: 0, y: 3)
    }
}

// MARK: - Step 5: Notification permission content

/// Preview chat bubble + frequency note. Deliberately no live permission-state
/// visual — the Apple popup gives feedback on that itself.
private struct NotificationPermissionContent: View {
    let accentColor: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Preview of a coach notification.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(accentColor)
                                .frame(width: 28, height: 28)
                            Image(systemName: "waveform.path.ecg")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        Text("VibeCoach")
                            .font(.footnote)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("nu")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text("Je Vibe Score staat op rood")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text("HRV 32 ms, –14 onder baseline. Ik verplaats je interval naar morgen.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color(.label).opacity(0.07), radius: 10, x: 0, y: 3)

                // Frequency note, calm and explanatory.
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                    Text("Maximaal één bericht per doel per dag — alleen bij afwijkingen van je plan.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color(.tertiarySystemFill).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
    }
}
