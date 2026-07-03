import SwiftUI

// Epic #65 story 65.5: split out of OnboardingView.swift (§5 file-split). Pure move — no
// semantic changes; access relaxed private -> internal only where the split
// requires it (listed in the PR body).

// MARK: - Step 3: AI-provider privacy content

/// Info block with "Waarom je eigen sleutel?" (blue tinted) followed by a
/// segmented picker for the provider. The actual API key comes later
/// in Settings — that matches the prototype.
struct AIProviderPrivacyContent: View {
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

struct AppleHealthPermissionContent: View {
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
struct NotificationPermissionContent: View {
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
