import SwiftUI

/// Epic #31 — Sprint 31.2: V2.0 Onboarding-flow met functionele content.
///
/// Gebruikt een `TabView` met `.page(indexDisplayMode: .never)` zodat de gebruiker
/// soepel kan swipen tussen 5 stappen. Elke stap wordt gerenderd via
/// `OnboardingTemplateView` — één bron van waarheid voor progress-bar, titel
/// en knoppen-layout.
///
/// Sprint 31.2 vervangt de placeholder-teksten door echte stap-content:
/// - Stap 1: Welkom in 'Mos'-stijl
/// - Stap 2: Doelkeuze op basis van `UserGoal`
/// - Stap 3: HealthKit-permissies (stappen, hartslag, slaap) + start Engine A
/// - Stap 4: Introductie van de AI-coach
/// - Stap 5: Afronding — zet `hasCompletedOnboarding` op `true`.
struct OnboardingView: View {

    /// Wordt op true gezet zodra de gebruiker de onboarding afrondt (stap 5).
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Sprint 31.2: persisteer het gekozen doel zodat latere features het kunnen
    /// ophalen zonder extra SwiftData-migratie.
    @AppStorage("vibecoach_selectedUserGoal") private var selectedGoalRaw: String = UserGoal.generalFitness.rawValue

    /// Huidige stap in de flow — matcht 1-based `stepIndex` van het template.
    @State private var currentStep: Int = 1

    /// HealthKit-status voor stap 3.
    @State private var healthKitState: HealthKitState = .idle

    /// Totaal aantal stappen in Sprint 31.2.
    private let totalSteps = 5

    @EnvironmentObject private var themeManager: ThemeManager

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
            content: {
                HealthKitPermissionVisual(state: healthKitState)
            },
            primaryButtonTitle: primaryTitleForStepThree,
            primaryAction: handleHealthKitAction,
            secondaryButtonTitle: "Overslaan",
            secondaryAction: advance
        )
    }

    private var stepFour: some View {
        OnboardingTemplateView(
            stepIndex: 4,
            totalSteps: totalSteps,
            title: "Jouw AI-coach",
            subtitle: "Stel vragen, krijg herstelplannen en uitleg bij je data",
            content: { CoachIntroVisual() },
            primaryButtonTitle: "Volgende",
            primaryAction: advance,
            secondaryButtonTitle: "Terug",
            secondaryAction: goBack
        )
    }

    private var stepFive: some View {
        OnboardingTemplateView(
            stepIndex: 5,
            totalSteps: totalSteps,
            title: "Klaar om te beginnen",
            subtitle: "Je eerste Vibe Score is een tap verderop",
            content: { CompletionVisual() },
            primaryButtonTitle: "Start met Trainen",
            primaryAction: completeOnboarding,
            secondaryButtonTitle: "Terug",
            secondaryAction: goBack
        )
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

    private func completeOnboarding() {
        hasCompletedOnboarding = true
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

/// Stap 4 — introductie van de AI-coach met een chat-preview.
private struct CoachIntroVisual: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 70))
                .foregroundStyle(themeManager.primaryAccentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 10) {
                chatBubble(text: "Hoe voel je je vandaag?", fromCoach: true)
                chatBubble(text: "Wat moet ik doen na een slechte nacht?", fromCoach: false)
                chatBubble(text: "Laten we rustig aan doen — 30 min wandelen.", fromCoach: true)
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func chatBubble(text: String, fromCoach: Bool) -> some View {
        HStack {
            if !fromCoach { Spacer(minLength: 24) }
            Text(text)
                .font(.footnote)
                .foregroundColor(fromCoach ? .primary : .white)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(fromCoach ? Color(.systemBackground) : themeManager.primaryAccentColor)
                )
            if fromCoach { Spacer(minLength: 24) }
        }
    }
}

/// Stap 5 — afronding.
private struct CompletionVisual: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
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
    }
}
