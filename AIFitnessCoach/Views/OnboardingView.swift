import SwiftUI

/// Epic #31 — Sprint 31.1: V2.0 Onboarding-flow.
///
/// Gebruikt een `TabView` met `.page(indexDisplayMode: .never)` zodat de gebruiker
/// soepel kan swipen tussen 5 stappen. Elke stap wordt gerenderd via
/// `OnboardingTemplateView` — één bron van waarheid voor progress-bar, titel
/// en knoppen-layout. De werkelijke illustraties/content per stap vullen we
/// in latere sprints in; voor nu staan er placeholder-visuals.
///
/// Op de laatste stap wordt `@AppStorage("hasCompletedOnboarding")` op `true`
/// gezet, waarna `AIFitnessCoachApp` automatisch doorschakelt naar de hoofd-app.
struct OnboardingView: View {

    /// Wordt op true gezet zodra de gebruiker de onboarding afrondt (stap 5).
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Huidige stap in de flow — matcht 1-based `stepIndex` van het template.
    @State private var currentStep: Int = 1

    /// Totaal aantal stappen in Sprint 31.1.
    private let totalSteps = 5

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
    }

    // MARK: - Stappen (tijdelijke placeholder-content, Sprint 31.1)

    private var stepOne: some View {
        OnboardingTemplateView(
            stepIndex: 1,
            totalSteps: totalSteps,
            title: "Welkom bij VibeCoach",
            subtitle: "Jouw AI-gestuurde fysiologische coach",
            content: { placeholderVisual(for: 1) },
            primaryButtonTitle: "Volgende",
            primaryAction: advance,
            secondaryButtonTitle: "Overslaan",
            secondaryAction: skipToEnd
        )
    }

    private var stepTwo: some View {
        OnboardingTemplateView(
            stepIndex: 2,
            totalSteps: totalSteps,
            title: "Hoe het werkt",
            subtitle: "Twee lagen van inzicht",
            content: { placeholderVisual(for: 2) },
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
            title: "Jouw Data, Jouw AI",
            subtitle: "Privacy first — alles blijft lokaal",
            content: { placeholderVisual(for: 3) },
            primaryButtonTitle: "Volgende",
            primaryAction: advance,
            secondaryButtonTitle: "Terug",
            secondaryAction: goBack
        )
    }

    private var stepFour: some View {
        OnboardingTemplateView(
            stepIndex: 4,
            totalSteps: totalSteps,
            title: "Permissies",
            subtitle: "Eenmalig toestemming voor Apple Health & notificaties",
            content: { placeholderVisual(for: 4) },
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
            content: { placeholderVisual(for: 5) },
            primaryButtonTitle: "Start met Trainen",
            primaryAction: completeOnboarding,
            secondaryButtonTitle: "Terug",
            secondaryAction: goBack
        )
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

    private func skipToEnd() {
        withAnimation { currentStep = totalSteps }
    }

    /// Sluit de onboarding af — de root van de app schakelt door op basis van deze flag.
    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    // MARK: - Tijdelijke visuals

    /// Placeholder-visual voor Sprint 31.1 — wordt in volgende sprints vervangen door
    /// echte illustraties per stap.
    private func placeholderVisual(for step: Int) -> some View {
        Text("Visual voor stap \(step)")
            .font(.title2)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, minHeight: 240)
            .padding(.horizontal, 24)
    }
}
