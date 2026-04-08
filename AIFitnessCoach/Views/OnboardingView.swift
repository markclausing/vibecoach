import SwiftUI

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

                // Pagina 3: Privacy & AI
                OnboardingPage(
                    icon: "lock.shield.fill",
                    iconColor: .purple,
                    title: "Jouw Data, Jouw AI",
                    subtitle: "Privacy first — geen dataverzameling",
                    description: "Al jouw Apple Health data blijft **100% lokaal** op jouw iPhone. Er wordt niets naar onze servers gestuurd.\n\nDe AI-coach werkt via jouw eigen API-sleutel (BYOK). Voeg die na de onboarding toe via **Instellingen → AI Coach Configuratie** om de coach te activeren."
                )
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
                        buttonLabel: "Koppel Apple Health"
                    ) {
                        requestHealthKit()
                    }

                    PermissionCard(
                        icon: "bell.badge.fill",
                        iconColor: .orange,
                        title: "Notificaties",
                        description: "Voor proactieve coaching-alerts als je doel op rood staat of je te lang inactief bent.",
                        isGranted: notificationsGranted,
                        buttonLabel: "Sta Notificaties toe"
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
            }
        }
    }

    // MARK: - Permissie aanvragen

    private func requestHealthKit() {
        healthKitManager.requestAuthorization { success, _ in
            Task { @MainActor in
                healthKitGranted = success
            }
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                notificationsGranted = granted
            }
        }
    }
}

// MARK: - Herbruikbare subviews

/// Één informatieve pagina in de carousel (pagina's 1–3).
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
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}
