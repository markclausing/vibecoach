import SwiftUI

/// Epic #31 — Sprint 31.1: Herbruikbaar layout-wrapper voor de V2.0 onboarding-flow.
///
/// Elke stap (1 t/m 5) rendert via dit template zodat we één bron van waarheid
/// hebben voor de voortgangsbalk, typografie en knoppen-layout. De wisselende
/// visual/illustratie wordt via `@ViewBuilder content` meegegeven.
struct OnboardingTemplateView<Content: View>: View {

    // MARK: - Configuratie

    /// Huidige stap (1 t/m `totalSteps`). Gebruikt om de voortgangsbalk te renderen.
    let stepIndex: Int

    /// Totaal aantal stappen in de flow. Standaard 5 voor Epic #31.
    var totalSteps: Int = 5

    /// Grote koptitel bovenaan het scherm.
    let title: String

    /// Optionele subtitel direct onder de titel.
    var subtitle: String? = nil

    /// De wisselende visual in het midden van het scherm.
    @ViewBuilder let content: () -> Content

    /// Label voor de primaire (gevulde, groene) knop.
    let primaryButtonTitle: String
    let primaryAction: () -> Void

    /// Label voor de secundaire (plain/outlined) knop. Optioneel — laat leeg om te verbergen.
    var secondaryButtonTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    // MARK: - Environment

    @EnvironmentObject private var themeManager: ThemeManager

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 1. Voortgangsbalk bovenaan
            progressBar
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)

            // 2. Titel + subtitel
            VStack(spacing: 8) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            // 3. Wisselende content
            Spacer(minLength: 16)
            content()
                .frame(maxWidth: .infinity)
            Spacer(minLength: 16)

            // 4. Knoppen onderin
            VStack(spacing: 12) {
                Button(action: primaryAction) {
                    Text(primaryButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(themeManager.primaryAccentColor)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .accessibilityIdentifier("OnboardingPrimaryButton")

                if let secondaryButtonTitle, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryButtonTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityIdentifier("OnboardingSecondaryButton")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
    }

    // MARK: - Voortgangsbalk

    /// Horizontale voortgangsbalk met één segment per stap.
    /// Actieve segmenten gebruiken de primaire themakleur; inactieve zijn een zachte grijze tint.
    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(1...totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= stepIndex ? themeManager.primaryAccentColor : Color(.tertiarySystemFill))
                    .frame(height: 6)
                    .animation(.easeInOut(duration: 0.25), value: stepIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stap \(stepIndex) van \(totalSteps)")
        .accessibilityIdentifier("OnboardingProgressBar")
    }
}
