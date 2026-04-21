import SwiftUI
import SwiftData
import UserNotifications

/// Epic #31 — Sprint 31.6: V2.0 Onboarding-flow, uitgelijnd op het definitieve
/// UX-prototype.
///
/// Vijf stappen met elk hun eigen sfeer:
/// 1. Welkom — merk + belofte
/// 2. Hoe het werkt — Vibe Score (herstel) + TRIMP (belasting) preview
/// 3. Jouw AI — BYOK provider-keuze (sleutel komt later in Instellingen)
/// 4. Apple Health — HRV + Slaap permissie (Permissie 1 van 2)
/// 5. Notificaties — Coach-signalen permissie (Permissie 2 van 2)
///
/// Alle schermen delen `OnboardingTemplateView` zodat typografie, voortgangsbalk
/// en knoppen-layout consistent blijven. De visuele stijl (kaarten met
/// `cornerRadius 16`, zachte schaduw) matcht de hoofd-Dashboard.
struct OnboardingView: View {

    // MARK: - Persistente state

    /// Wordt op true gezet zodra de gebruiker de onboarding afrondt (stap 5).
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Sprint 31.6: gekozen AI-provider — gedeelde sleutel met `AIProviderSettingsView`
    /// zodat `ChatViewModel` hem direct oppakt. De daadwerkelijke API-sleutel
    /// wordt later in Instellingen ingevoerd (prototype toont enkel provider-keuze).
    @AppStorage("vibecoach_aiProvider") private var providerRaw: String = AIProvider.gemini.rawValue

    // MARK: - Transient UI-state

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

    // MARK: - Stap 1: Welkom

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

    // MARK: - Stap 2: Hoe het werkt

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

    // MARK: - Stap 3: Jouw AI

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

    // MARK: - Stap 4: Apple Health

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

    // MARK: - Stap 5: Notificaties

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

    // MARK: - Button-titel per permissie-state

    private func primaryTitle(for state: PermissionState, grantLabel: String) -> String {
        switch state {
        case .idle:       return grantLabel
        case .requesting: return "Even geduld…"
        case .granted:    return "Volgende"
        case .failed:     return "Probeer opnieuw"
        }
    }

    // MARK: - Stap 4 logica (HealthKit)

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

    /// Sprint 31.2 (§4 Dual Engine): Start Engine A zodra HealthKit-toestemming is verleend.
    /// Kalender-gebaseerde check op `Calendar.current.startOfDay(for:)` (Rule §3).
    private func startEngineA() {
        ProactiveNotificationService.shared.setupEngineA()
        let startOfToday = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(startOfToday, forKey: "vibecoach_engineAStartedAt")
    }

    // MARK: - Stap 5 logica (Notificaties)

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

    // MARK: - Navigatie

    private func advance() {
        guard currentStep < totalSteps else {
            completeOnboarding()
            return
        }
        withAnimation { currentStep += 1 }
    }

    /// Sprint 31.6: Persisteer onboarding-keuzes en schakel de app door.
    ///
    /// V2.0-flow bewaart géén fitnessdoel — de API-sleutel wordt later in
    /// Instellingen ingesteld (BYOK). We schrijven enkel de onboarding-datum
    /// naar SwiftData zodat andere features een ankerdatum hebben.
    private func completeOnboarding() {
        persistUserConfiguration()
        Haptics.impact(.medium)
        hasCompletedOnboarding = true
    }

    private func persistUserConfiguration() {
        // Vervang een eventuele bestaande configuratie — we onboarden altijd maar één profiel.
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

// MARK: - Permissie-state

private enum PermissionState {
    case idle, requesting, granted, failed
}

// MARK: - Stap 1: Welkom visual

/// Grote afgeronde 'brand mark' met een waveform-icoon in moss-groen, gevolgd
/// door het uppercase merkwoord "VIBECOACH". Matcht het prototype.
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

// MARK: - Stap 2: Twee lagen preview

/// Twee preview-kaarten naast elkaar: links de Vibe Score (ring), rechts de
/// TRIMP-trend (bars). Dezelfde kaart-stijl als het Dashboard.
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

    /// Veertien placeholder-datapunten voor de preview-bars (genormaliseerd 0…1).
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

// MARK: - Stap 3: AI-provider privacy content

/// Info-blok met "Waarom je eigen sleutel?" (blauw getint) gevolgd door een
/// segmented picker voor de provider. De daadwerkelijke API-sleutel komt later
/// in Instellingen — dat matcht het prototype.
private struct AIProviderPrivacyContent: View {
    @Binding var providerRaw: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Info-kaart, blauw getint.
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

                // Provider-picker.
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI PROVIDER")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .kerning(1.0)
                        .foregroundColor(.secondary)

                    Picker("Provider", selection: $providerRaw) {
                        Text("Gemini").tag(AIProvider.gemini.rawValue)
                        Text("OpenAI").tag(AIProvider.openAI.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("OnboardingProviderPicker")

                    Text("Je kunt de sleutel zelf later invoeren in Instellingen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Stap 4: Apple Health permissie content

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

                // Verwachtings-bubbel — matcht prototype.
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
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
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

// MARK: - Stap 5: Notificatie permissie content

/// Preview-chat bubble + frequentie-note. Bewust géén live permissie-state
/// visual — de Apple-popup geeft daar zelf feedback op.
private struct NotificationPermissionContent: View {
    let accentColor: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Preview van een coach-notificatie.
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

                // Frequentie-note, rustig en uitleggend.
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
