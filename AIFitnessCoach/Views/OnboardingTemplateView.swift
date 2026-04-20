import SwiftUI

/// Epic #31 — Sprint 31.6: Herbruikbare layout-wrapper voor de V2.0 onboarding-flow.
///
/// Het UX-prototype schrijft één rustig kader voor elke stap: een continue
/// voortgangsbalk met "X / N" label, optionele uppercase eyebrow (moss of rood),
/// grote titel, copy-blok en één of twee knoppen onderin. De wisselende visual
/// wordt via `@ViewBuilder content` meegegeven.
struct OnboardingTemplateView<Content: View>: View {

    // MARK: - Configuratie

    /// Huidige stap (1 t/m `totalSteps`). Gebruikt voor de voortgangsbalk én het "X / N" label.
    let stepIndex: Int

    /// Totaal aantal stappen in de flow. Standaard 5 conform Epic #31 V2.0.
    var totalSteps: Int = 5

    /// Optionele uppercase-label direct boven de titel (bijv. "PRIVACY EERST").
    /// Kleur wordt via `eyebrowColor` bepaald — standaard moss (themakleur).
    var eyebrow: String? = nil
    var eyebrowColor: Color? = nil

    /// Grote koptitel bovenaan het scherm.
    let title: String

    /// Optionele copy-tekst direct onder de titel.
    var subtitle: String? = nil

    /// De wisselende visual in het midden van het scherm.
    @ViewBuilder let content: () -> Content

    /// Label voor de primaire (gevulde, groene) knop.
    let primaryButtonTitle: String
    let primaryAction: () -> Void

    /// Label voor de secundaire (plain) knop. Optioneel — laat leeg om te verbergen.
    var secondaryButtonTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    // MARK: - Environment

    @EnvironmentObject private var themeManager: ThemeManager

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 1. Continue voortgangsbalk + "X / N" teller
            progressHeader
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)

            // 2. Eyebrow + titel + copy (links uitgelijnd, zoals Dashboard-stijl)
            VStack(alignment: .leading, spacing: 10) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .kerning(1.2)
                        .textCase(.uppercase)
                        .foregroundColor(eyebrowColor ?? themeManager.primaryAccentColor)
                }

                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            // 3. Wisselende content
            Spacer(minLength: 20)
            content()
                .frame(maxWidth: .infinity)
            Spacer(minLength: 20)

            // 4. Knoppen onderin
            VStack(spacing: 10) {
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

    /// Continue voortgangsbalk met rechts ervan een "X / N" teller.
    /// De balk gebruikt één track-rechthoek met een voortgangs-overlay die
    /// evenredig meegroeit met `stepIndex / totalSteps`.
    private var progressHeader: some View {
        HStack(spacing: 12) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))

                    Capsule()
                        .fill(themeManager.primaryAccentColor)
                        .frame(width: proxy.size.width * progressFraction)
                        .animation(.easeInOut(duration: 0.25), value: stepIndex)
                }
            }
            .frame(height: 6)

            Text("\(stepIndex) / \(totalSteps)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stap \(stepIndex) van \(totalSteps)")
        .accessibilityIdentifier("OnboardingProgressBar")
    }

    private var progressFraction: CGFloat {
        guard totalSteps > 0 else { return 0 }
        let clamped = min(max(stepIndex, 0), totalSteps)
        return CGFloat(clamped) / CGFloat(totalSteps)
    }
}
