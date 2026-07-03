import SwiftUI

/// Epic #31 — Sprint 31.6: Reusable layout wrapper for the V2.0 onboarding flow.
///
/// The UX prototype prescribes one calm frame for every step: a continuous
/// progress bar with an "X / N" label, an optional uppercase eyebrow (moss or red),
/// large title, copy block and one or two buttons at the bottom. The varying visual
/// is passed in via `@ViewBuilder content`.
struct OnboardingTemplateView<Content: View>: View {

    // MARK: - Configuration

    /// Current step (1 through `totalSteps`). Used for both the progress bar and the "X / N" label.
    let stepIndex: Int

    /// Total number of steps in the flow. Defaults to 5 per Epic #31 V2.0.
    var totalSteps: Int = 5

    /// Optional uppercase label directly above the title (e.g. "PRIVACY EERST").
    /// Color is determined via `eyebrowColor` — defaults to moss (theme color).
    var eyebrow: String?
    var eyebrowColor: Color?

    /// Large heading at the top of the screen.
    let title: String

    /// Optional copy text directly below the title.
    var subtitle: String?

    /// The varying visual in the middle of the screen.
    @ViewBuilder let content: () -> Content

    /// Label for the primary (filled, green) button.
    let primaryButtonTitle: String
    let primaryAction: () -> Void

    /// Label for the secondary (plain) button. Optional — leave empty to hide.
    var secondaryButtonTitle: String?
    var secondaryAction: (() -> Void)?

    // MARK: - Environment

    @EnvironmentObject private var themeManager: ThemeManager

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 1. Continuous progress bar + "X / N" counter
            progressHeader
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)

            // 2. Eyebrow + title + copy (left aligned, Dashboard style)
            // Epic #37 story 37.1c: title/eyebrow/subtitle/button titles are String params (one
            // call site passes a computed String), so resolve via the catalog at render time.
            VStack(alignment: .leading, spacing: 10) {
                if let eyebrow {
                    Text(LocalizedStringKey(eyebrow))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .kerning(1.2)
                        .textCase(.uppercase)
                        .foregroundColor(eyebrowColor ?? themeManager.primaryAccentColor)
                }

                Text(LocalizedStringKey(title))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            // 3. Varying content
            Spacer(minLength: 20)
            content()
                .frame(maxWidth: .infinity)
            Spacer(minLength: 20)

            // 4. Buttons at the bottom
            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    Text(LocalizedStringKey(primaryButtonTitle))
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
                        Text(LocalizedStringKey(secondaryButtonTitle))
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

    // MARK: - Progress bar

    /// Continuous progress bar with an "X / N" counter to its right.
    /// The bar uses one track rectangle with a progress overlay that grows
    /// proportionally with `stepIndex / totalSteps`.
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
