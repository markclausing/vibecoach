import SwiftUI
import SwiftData

/// Epic #31 — Sprint 31.4: V2.0 Onboarding-flow met persistente opslag.
///
/// Gebruikt een `TabView` met `.page(indexDisplayMode: .never)` zodat de gebruiker
/// soepel kan swipen tussen 5 stappen. Elke stap wordt gerenderd via
/// `OnboardingTemplateView` — één bron van waarheid voor progress-bar, titel
/// en knoppen-layout.
///
/// Stap-content:
/// - Stap 1: Welkom in 'Mos'-stijl
/// - Stap 2: Doelkeuze op basis van `UserGoal`
/// - Stap 3: HealthKit-permissies (stappen, hartslag, slaap) + start Engine A
/// - Stap 4: AI-coach setup (provider + BYOK API-sleutel)
/// - Stap 5: Afronding — persisteert data en zet `hasCompletedOnboarding` op `true`.
struct OnboardingView: View {

    // MARK: - Persistente state

    /// Wordt op true gezet zodra de gebruiker de onboarding afrondt (stap 5).
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Sprint 31.2: persisteer het gekozen doel zodat latere features het snel
    /// kunnen ophalen. De canonieke bron wordt via SwiftData `UserConfiguration`
    /// opgeslagen op stap 5 (zie `completeOnboarding()`).
    @AppStorage("vibecoach_selectedUserGoal") private var selectedGoalRaw: String = UserGoal.generalFitness.rawValue

    /// Sprint 31.4: gekozen AI-provider — gedeelde sleutel met `AIProviderSettingsView`
    /// zodat `ChatViewModel` hem direct oppakt zonder extra stap.
    @AppStorage("vibecoach_aiProvider") private var providerRaw: String = AIProvider.gemini.rawValue

    /// Sprint 31.4: de API-sleutel wordt ALLEEN in-memory via `@State` gehouden
    /// tijdens de onboarding en bij afronding naar de Keychain geschreven —
    /// nooit naar `UserDefaults` (productie-veiligheid).
    @State private var apiKey: String = ""

    // MARK: - Transient UI-state

    @State private var currentStep: Int = 1
    @State private var healthKitState: HealthKitState = .idle
    /// Aparte state voor het dedicated Bio-data koppel-scherm (stap 4) zodat de
    /// knop onafhankelijk van stap 3 terugvalt op "Koppel Apple Health" of
    /// doorschakelt nadat iOS de popup heeft afgehandeld.
    @State private var bioDataState: HealthKitState = .idle
    @FocusState private var apiKeyFieldFocused: Bool

    private let totalSteps = 6

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext

    // MARK: - Body

    var body: some View {
        TabView(selection: $currentStep) {
            stepOne.tag(1)
            stepTwo.tag(2)
            stepThree.tag(3)
            stepFourBioData.tag(4)
            stepFiveAICoach.tag(5)
            stepSixCompletion.tag(6)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
        // Sprint 31.2: animeer de voortgangsbalk bij zowel swipen als klikken.
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }

    // MARK: - Stappen

    private var stepOne: some View {
        OnboardingTemplateView(
            stepIndex: 1,
            totalSteps: totalSteps,
            title: "Welkom bij VibeCoach",
            subtitle: "Jouw rustige, slimme trainingspartner",
            content: { WelcomeMossVisual() },
            primaryButtonTitle: "Laten we beginnen",
            primaryAction: advance,
            secondaryButtonTitle: nil,
            secondaryAction: nil
        )
    }

    private var stepTwo: some View {
        OnboardingTemplateView(
            stepIndex: 2,
            totalSteps: totalSteps,
            title: "Wat wil je bereiken?",
            subtitle: "Kies het doel dat vandaag het best past",
            content: {
                GoalSelectionList(selection: Binding(
                    get: { UserGoal(rawValue: selectedGoalRaw) ?? .generalFitness },
                    set: { selectedGoalRaw = $0.rawValue }
                ))
            },
            primaryButtonTitle: "Volgende",
            primaryAction: advance,
            secondaryButtonTitle: "Terug",
            secondaryAction: goBack
        )
    }

    private var stepThree: some View {
        OnboardingTemplateView(
            stepIndex: 3,
            totalSteps: totalSteps,
            title: "Koppel Apple Health",
            subtitle: "Stappen, hartslag en slaap — alles blijft op jouw iPhone",
            content: { HealthKitPermissionVisual(state: healthKitState) },
            primaryButtonTitle: primaryTitleForStepThree,
            primaryAction: handleHealthKitAction,
            secondaryButtonTitle: "Overslaan",
            secondaryAction: advance
        )
    }

    /// Stap 4 — dedicated Bio-data sync scherm (HRV + Slaap) dat specifiek matcht
    /// met het V2.0 design: twee horizontale kaarten in plaats van een generieke
    /// permissie-visual. Roept opnieuw `requestOnboardingPermissions()` aan — iOS
    /// dedupeert stil wanneer de gebruiker al in stap 3 akkoord gaf.
    private var stepFourBioData: some View {
        OnboardingTemplateView(
            stepIndex: 4,
            totalSteps: totalSteps,
            title: "Synchroniseer je bio-data",
            subtitle: "VibeCoach leest je HRV en slaapgegevens om je dagelijkse Vibe Score te berekenen.",
            content: { BioDataSyncCards(state: bioDataState) },
            primaryButtonTitle: primaryTitleForBioData,
            primaryAction: handleBioDataAction,
            secondaryButtonTitle: "Terug",
            secondaryAction: goBack
        )
    }

    private var stepFiveAICoach: some View {
        OnboardingTemplateView(
            stepIndex: 5,
            totalSteps: totalSteps,
            title: "Jouw AI-coach",
            subtitle: "Kies je provider en plak je API-sleutel",
            content: {
                AIProviderSetupForm(
                    providerRaw: $providerRaw,
                    apiKey: $apiKey,
                    isFocused: $apiKeyFieldFocused
                )
            },
            primaryButtonTitle: "Volgende",
            primaryAction: {
                apiKeyFieldFocused = false
                advance()
            },
            secondaryButtonTitle: "Terug",
            secondaryAction: goBack
        )
    }

    private var stepSixCompletion: some View {
        OnboardingTemplateView(
            stepIndex: 6,
            totalSteps: totalSteps,
            title: "Klaar om te beginnen",
            subtitle: "Je eerste Vibe Score is een tap verderop",
            content: { CompletionVisual() },
            primaryButtonTitle: "Start Coaching",
            primaryAction: completeOnboarding,
            secondaryButtonTitle: "Terug",
            secondaryAction: goBack
        )
    }

    // MARK: - Bio-data logica (stap 4)

    private var primaryTitleForBioData: String {
        switch bioDataState {
        case .idle:       return "Koppel Apple Health"
        case .requesting: return "Even geduld…"
        case .granted:    return "Volgende"
        case .failed:     return "Probeer opnieuw"
        }
    }

    private func handleBioDataAction() {
        switch bioDataState {
        case .granted:
            advance()
        case .requesting:
            return
        case .idle, .failed:
            requestBioDataPermissions()
        }
    }

    private func requestBioDataPermissions() {
        bioDataState = .requesting

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            bioDataState = .granted
            startEngineA()
            return
        }
        #endif

        Task {
            do {
                _ = try await HealthKitManager.shared.requestOnboardingPermissions()
                await MainActor.run {
                    bioDataState = .granted
                    // Start Engine A ook hier, voor het geval de gebruiker stap 3 heeft overgeslagen.
                    startEngineA()
                }
            } catch {
                await MainActor.run {
                    bioDataState = .failed
                }
            }
        }
    }

    // MARK: - HealthKit logica (stap 3)

    private var primaryTitleForStepThree: String {
        switch healthKitState {
        case .idle:      return "Geef Toegang"
        case .requesting: return "Even geduld…"
        case .granted:   return "Volgende"
        case .failed:    return "Probeer opnieuw"
        }
    }

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

        // Sprint 26.1: bypass HealthKit-popup in UI-testmodus — simuleer direct succes.
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
                    // Start Engine A: HKObserverQuery reageert vanaf nu op nieuwe workouts.
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
    /// Doet tegelijk een eerste kalenderschoon-check op basis van `Calendar.current`
    /// (Rule §3) zodat we direct weten of er vandaag al activiteit is geregistreerd.
    private func startEngineA() {
        ProactiveNotificationService.shared.setupEngineA()

        // Calendar-gebaseerde initiële check: noteer "vandaag" als startdatum voor de
        // eerstvolgende observer-cyclus — voorkomt TimeInterval-wiskunde (Rule §3).
        let startOfToday = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(startOfToday, forKey: "vibecoach_engineAStartedAt")
    }

    // MARK: - Navigatie

    private func advance() {
        guard currentStep < totalSteps else { return }
        withAnimation { currentStep += 1 }
    }

    private func goBack() {
        guard currentStep > 1 else { return }
        withAnimation { currentStep -= 1 }
    }

    /// Sprint 31.4: Persisteer onboarding-keuzes en schakel de app door.
    ///
    /// Volgorde:
    /// 1. SwiftData: schrijf (of update) een enkele `UserConfiguration` record
    ///    met het gekozen doel en de huidige datum (via `Calendar.current`).
    /// 2. Keychain: sla de API-sleutel veilig op — alleen als de gebruiker er
    ///    daadwerkelijk één heeft ingevuld.
    /// 3. AppStorage: `hasCompletedOnboarding = true` — dit triggert in
    ///    `AIFitnessCoachApp` automatisch de overgang naar de hoofd-app.
    private func completeOnboarding() {
        let goal = UserGoal(rawValue: selectedGoalRaw) ?? .generalFitness
        persistUserConfiguration(goal: goal)
        persistAPIKeyIfPresent()
        hasCompletedOnboarding = true
    }

    private func persistUserConfiguration(goal: UserGoal) {
        // Vervang een eventuele bestaande configuratie — we onboarden altijd maar één profiel.
        let descriptor = FetchDescriptor<UserConfiguration>()
        if let existing = try? modelContext.fetch(descriptor) {
            for record in existing {
                modelContext.delete(record)
            }
        }

        let config = UserConfiguration(primaryGoal: goal, date: Date())
        modelContext.insert(config)

        do {
            try modelContext.save()
        } catch {
            // Log alleen — een falende save mag de onboarding niet blokkeren.
            print("⚠️ UserConfiguration save mislukt: \(error.localizedDescription)")
        }
    }

    private func persistAPIKeyIfPresent() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            // WAARSCHUWING: Productie-sleutels horen UITSLUITEND in de Keychain.
            // Bewust geen UserDefaults-fallback hier — bij een Keychain-fout tonen we
            // de gebruiker later (Sprint 31.5) een retry-scherm in Instellingen.
            try KeychainService.shared.saveToken(trimmed, forService: "vibecoach_userAPIKey")
        } catch {
            print("⚠️ API-sleutel opslaan in Keychain mislukt: \(error.localizedDescription)")
        }
    }
}

// MARK: - HealthKit state

private enum HealthKitState {
    case idle, requesting, granted, failed
}

// MARK: - Visuals per stap

/// Stap 1 — rustige 'Mos'-welkom: zachte groene cirkel met icoon en begeleidende tekst.
private struct WelcomeMossVisual: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(themeManager.primaryAccentColor.opacity(0.15))
                        .frame(width: 180, height: 180)

                    Image(systemName: "leaf.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(themeManager.primaryAccentColor)
                        .symbolRenderingMode(.hierarchical)
                }

                Text("Rustig, consistent en op jouw tempo — VibeCoach waarschuwt alleen wanneer het ertoe doet.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Stap 2 — lijst met doelen op basis van de `UserGoal` enum.
private struct GoalSelectionList: View {
    @Binding var selection: UserGoal
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(UserGoal.allCases) { goal in
                    Button {
                        selection = goal
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: goal.iconName)
                                .font(.title2)
                                .foregroundStyle(themeManager.primaryAccentColor)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(goal.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            Image(systemName: selection == goal ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selection == goal ? themeManager.primaryAccentColor : Color(.tertiaryLabel))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selection == goal ? themeManager.primaryAccentColor : Color(.separator), lineWidth: selection == goal ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("OnboardingGoal_\(goal.rawValue)")
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

/// Stap 3 — permissie-kaart die zichtbaar status-reactie geeft.
private struct HealthKitPermissionVisual: View {
    let state: HealthKitState
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(colorForState.opacity(0.15))
                        .frame(width: 160, height: 160)

                    Image(systemName: iconForState)
                        .font(.system(size: 70))
                        .foregroundStyle(colorForState)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(spacing: 10) {
                    DataRow(icon: "figure.walk", label: "Stappen")
                    DataRow(icon: "heart.fill", label: "Hartslag")
                    DataRow(icon: "bed.double.fill", label: "Slaap")
                }
                .padding(.horizontal, 36)

                if case .failed = state {
                    Text("Permissie mislukt — open Instellingen om toegang te verlenen.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }

    private var iconForState: String {
        switch state {
        case .idle:       return "heart.text.square.fill"
        case .requesting: return "ellipsis.circle.fill"
        case .granted:    return "checkmark.seal.fill"
        case .failed:     return "exclamationmark.triangle.fill"
        }
    }

    private var colorForState: Color {
        switch state {
        case .idle:       return themeManager.primaryAccentColor
        case .requesting: return .orange
        case .granted:    return .green
        case .failed:     return .red
        }
    }
}

/// Compacte regel met icoon + label voor HealthKit-permissievisual.
private struct DataRow: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

/// Stap 4 — twee dedicated kaarten voor HRV en slaapanalyse, met lichte schaduw.
/// Matcht het V2.0 design: rustige RoundedRectangles, zachte iconografie en
/// statusbadge rechts wanneer de gebruiker de popup heeft afgehandeld.
private struct BioDataSyncCards: View {
    let state: HealthKitState
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                BioDataCard(
                    icon: "waveform.path.ecg.rectangle.fill",
                    iconTint: themeManager.primaryAccentColor,
                    title: "Hartslagvariabiliteit (HRV)",
                    subtitle: "Meet je autonome herstel — de hoeksteen van je Vibe Score.",
                    isGranted: state == .granted
                )

                BioDataCard(
                    icon: "moon.stars.fill",
                    iconTint: themeManager.primaryAccentColor,
                    title: "Slaapanalyse & Herstel",
                    subtitle: "Fase-opdeling (REM/diep/licht) uit Apple Health voor betere trainingsadviezen.",
                    isGranted: state == .granted
                )

                if case .failed = state {
                    Text("Toestemming mislukt — je kunt het nu opnieuw proberen of later via Instellingen koppelen.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Eén horizontale kaart met icoon links, titel + subtitel rechts, en een
/// groene checkmark-badge zodra de permissie is verleend.
private struct BioDataCard: View {
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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .shadow(color: Color(.label).opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

/// Stap 5 — AI-provider picker + API-sleutel invoerveld (BYOK).
private struct AIProviderSetupForm: View {
    @Binding var providerRaw: String
    @Binding var apiKey: String
    var isFocused: FocusState<Bool>.Binding

    @EnvironmentObject private var themeManager: ThemeManager

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: providerRaw) ?? .gemini
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                // Uitleg — kort en rustig.
                Text("Je sleutel blijft in de iPhone Keychain. VibeCoach stuurt je data niet naar ons.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)

                // Provider-picker.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Picker("Provider", selection: $providerRaw) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("OnboardingProviderPicker")
                }

                // API-sleutel veld.
                VStack(alignment: .leading, spacing: 6) {
                    Text("API-sleutel")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        SecureField(selectedProvider.keyPlaceholder, text: $apiKey)
                            .focused(isFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityIdentifier("OnboardingAPIKeyField")

                        if !apiKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding(12)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(apiKey.isEmpty ? Color(.separator) : themeManager.primaryAccentColor.opacity(0.8), lineWidth: 1)
                    )
                }

                // Link naar provider-portal.
                if let url = selectedProvider.getKeyURL {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Gratis sleutel halen voor \(selectedProvider.displayName)")
                        }
                        .font(.caption)
                        .foregroundStyle(themeManager.primaryAccentColor)
                    }
                }

                // Skip-uitleg.
                Text("Geen sleutel? Geen probleem — je kunt dit later instellen via Instellingen.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Stap 5 — afronding.
private struct CompletionVisual: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(themeManager.primaryAccentColor.opacity(0.15))
                        .frame(width: 180, height: 180)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 90))
                        .foregroundStyle(themeManager.primaryAccentColor)
                        .symbolRenderingMode(.hierarchical)
                }

                Text("Alles staat klaar. Open het dashboard om je Vibe Score en trainingsplan te zien.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }
}
