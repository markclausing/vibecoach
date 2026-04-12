import SwiftUI
import UserNotifications

/// Epic 20 — Sprint 20.2: Onboarding Flow voor nieuwe gebruikers.
///
/// Toont een 4-pagina carousel die het concept uitlegt, de gebruiker voorbereidt
/// op BYOK, en de Apple Health / Notificatie permissies netjes uitvraagt.
/// Nadat de gebruiker op "Start met Trainen" drukt, wordt `hasSeenOnboarding`
/// op true gezet en laadt de app de normale TabView.
struct OnboardingView: View {

    /// Wordt op true gezet zodra de gebruiker de onboarding afrondt.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    /// Huidige pagina in de carousel (0-3).
    @State private var currentPage = 0

    /// Status van de permissie-knoppen op pagina 4.
    @State private var healthKitGranted = false
    @State private var notificationsGranted = false

    private let healthKitManager = HealthKitManager()

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                // Pagina 1: Welkom
                OnboardingPage(
                    icon: "figure.run.circle.fill",
                    iconColor: .blue,
                    title: "Welkom bij VibeCoach",
                    subtitle: "Jouw AI-gestuurde fysiologische coach",
                    description: "VibeCoach combineert je Apple Health data met kunstmatige intelligentie om je trainingsbelasting te bewaken, je herstel te meten en je schema's slim bij te sturen."
                )
                .tag(0)

                // Pagina 2: Hoe het werkt
                OnboardingPage(
                    icon: "waveform.path.ecg.rectangle.fill",
                    iconColor: .green,
                    title: "Hoe het werkt",
                    subtitle: "Twee lagen van inzicht",
                    description: "**TRIMP (Training Impulse)** meet hoe zwaar een training was — hartslag × duur × intensiteit.\n\n**Vibe Score** is jouw lichaamsbatterij (0–100), berekend uit jouw HRV en slaap. Deze twee samen vertellen de coach of je kunt pushen of moet herstellen."
                )
                .tag(1)

                // Pagina 3: Jouw Data, Jouw AI — inclusief BYOK API-sleutel invoer
                APIKeyOnboardingPage()
                    .tag(2)

                // Pagina 4: Permissies
                permissionsPage
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .ignoresSafeArea(edges: .top)

            // Navigatieknop (verschijnt pas op de laatste pagina als 'Start met Trainen')
            bottomButton
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Pagina 4: Permissies

    private var permissionsPage: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 48)

                // Icoon + titels
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.orange)
                        .symbolRenderingMode(.hierarchical)

                    Text("Één keer toestemming")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("VibeCoach heeft twee permissies nodig om goed te werken")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                // Permissie-kaartjes
                VStack(spacing: 16) {
                    PermissionCard(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: "Apple Health",
                        description: "Om trainingen, HRV en slaapdata te lezen voor TRIMP en je Vibe Score.",
                        isGranted: healthKitGranted,
                        buttonLabel: "Koppel Apple Health",
                        buttonIdentifier: "OnboardingHealthKitButton"
                    ) {
                        requestHealthKit()
                    }

                    PermissionCard(
                        icon: "bell.badge.fill",
                        iconColor: .orange,
                        title: "Notificaties",
                        description: "Voor proactieve coaching-alerts als je doel op rood staat of je te lang inactief bent.",
                        isGranted: notificationsGranted,
                        buttonLabel: "Sta Notificaties toe",
                        buttonIdentifier: "OnboardingNotificationsButton"
                    ) {
                        requestNotifications()
                    }
                }
                .padding(.horizontal, 24)

                // Ruimte voor de floating knop
                Spacer(minLength: 120)
            }
        }
    }

    // MARK: - Onderste knop

    private var bottomButton: some View {
        Group {
            if currentPage < 3 {
                Button(action: {
                    withAnimation { currentPage += 1 }
                }) {
                    Text("Volgende")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .accessibilityIdentifier("OnboardingVolgendeButton")
            } else {
                Button(action: {
                    hasSeenOnboarding = true
                }) {
                    Text("Start met Trainen")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .accessibilityIdentifier("OnboardingStartButton")
            }
        }
    }

    // MARK: - Permissie aanvragen

    // MARK: - Permissie aanvragen
    // Sprint 20.3: Permissies worden UITSLUITEND via knoppen op pagina 4 aangevraagd.
    // Er zijn geen automatische requests bij onAppear of bij het laden van de OnboardingView.

    private func requestHealthKit() {
        // Sprint 26.1: Bypass HealthKit popup in UI-testmodus — simuleer direct succes.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            Task { @MainActor in healthKitGranted = true }
            return
        }
        #endif
        healthKitManager.requestAuthorization { success, _ in
            Task { @MainActor in
                healthKitGranted = success
            }
        }
    }

    private func requestNotifications() {
        // Sprint 26.1: Bypass notificatie-popup in UI-testmodus — simuleer direct succes.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            Task { @MainActor in notificationsGranted = true }
            return
        }
        #endif
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                notificationsGranted = granted
            }
        }
    }
}

// MARK: - Herbruikbare subviews

/// Pagina 3: Privacy & AI — met inline BYOK API-sleutelinvoer.
/// De sleutel wordt opgeslagen in dezelfde AppStorage-sleutels als AIProviderSettingsView,
/// zodat de ChatViewModel hem direct ophaalt zonder extra stap.
private struct APIKeyOnboardingPage: View {
    @AppStorage("vibecoach_aiProvider")  private var providerRaw: String = AIProvider.gemini.rawValue
    @AppStorage("vibecoach_userAPIKey") private var apiKey: String = ""

    @FocusState private var fieldFocused: Bool

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: providerRaw) ?? .gemini
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 60)

                // Icoon + titels
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(.purple)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("Jouw Data, Jouw AI")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("Privacy first — geen dataverzameling")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("Al jouw Apple Health data blijft **100% lokaal** op jouw iPhone. Er wordt niets naar onze servers gestuurd.")
                    .font(.body)
                    .foregroundColor(.primary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                // BYOK invoerkaart
                VStack(alignment: .leading, spacing: 16) {

                    // Provider picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI Provider")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        Picker("Provider", selection: $providerRaw) {
                            ForEach(AIProvider.allCases) { provider in
                                HStack {
                                    Text(provider.displayName)
                                    if !provider.isSupported {
                                        Text("· Binnenkort")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                }
                                .tag(provider.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // API-sleutel invoerveld
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Sleutel")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        HStack {
                            SecureField(selectedProvider.keyPlaceholder, text: $apiKey)
                                .focused($fieldFocused)
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
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(apiKey.isEmpty ? Color(.separator) : Color.green.opacity(0.6), lineWidth: 1)
                        )
                    }

                    // 'Hoe kom ik aan een sleutel?' link
                    if let url = selectedProvider.getKeyURL {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Hoe kom ik aan een sleutel voor \(selectedProvider.displayName)?")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }

                    // Skip-tekst — geen harde verplichting
                    Text("Geen sleutel? Geen probleem — je kunt dit later instellen via Instellingen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)

                // Ruimte voor de floating knop
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 28)
        }
        .onTapGesture { fieldFocused = false }
    }
}

/// Één informatieve pagina in de carousel (pagina's 1–2).
private struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 60)

                Image(systemName: icon)
                    .font(.system(size: 90))
                    .foregroundStyle(iconColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text(LocalizedStringKey(description))
                    .font(.body)
                    .foregroundColor(.primary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 32)
        }
    }
}

/// Kaartje voor één permissie-verzoek op pagina 4.
private struct PermissionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let buttonLabel: String
    /// Sprint 26.1: Accessibility identifier voor de actieknop — zodat XCUITest hem feilloos vindt.
    var buttonIdentifier: String = ""
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isGranted {
                Label("Toegekend", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(10)
                    .accessibilityIdentifier("\(buttonIdentifier)_Granted")
            } else {
                Button(action: action) {
                    Text(buttonLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(iconColor.opacity(0.12))
                        .foregroundColor(iconColor)
                        .cornerRadius(10)
                }
                .accessibilityIdentifier(buttonIdentifier)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}
