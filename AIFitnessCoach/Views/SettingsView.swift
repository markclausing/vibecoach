import SwiftUI
import UserNotifications
import SwiftData

/// Beheer van externe API koppelingen en andere voorkeuren.
/// Deze view is toegankelijk via het instellingen-icoon en schrijft gegevens
/// veilig weg naar de KeychainService.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Authenticatie service voor Strava OAuth web flow
    @StateObject private var stravaAuthService = StravaAuthService()
    private let fitnessDataService = FitnessDataService()
    private let profileManager = AthleticProfileManager()

    // UI State variabelen, gehaald uit en geschreven naar Keychain
    @State private var feedbackMessage: String?
    @State private var notificationsEnabled: Bool = false
    @AppStorage("isHealthKitLinked") private var isHealthKitLinked: Bool = false

    @AppStorage("selectedDataSource") private var selectedDataSource: DataSource = .healthKit

    // Historische sync state
    @State private var isSyncingHistory: Bool = false
    @State private var athleticProfile: AthleticProfile?

    // Dependency injection (voor tests of preview)
    var tokenStore: TokenStore = KeychainService.shared

    // Laden van opgeslagen waarden en rechten
    private func loadTokens() {
        stravaAuthService.checkAuthStatus()

        checkNotificationStatus()
        refreshProfile()
    }

    // Herbereken het lokale atletisch profiel op basis van SwiftData
    private func refreshProfile() {
        do {
            self.athleticProfile = try profileManager.calculateProfile(context: modelContext)
        } catch {
            print("Fout bij berekenen atletisch profiel: \(error)")
        }
    }

    // Activeert het ophalen van historische workouts via gekozen databron.
    private func syncHistoricalData() {
        guard !isSyncingHistory else { return }
        isSyncingHistory = true
        feedbackMessage = "Synchroniseren gestart..."

        Task {
            do {
                if selectedDataSource == .healthKit {
                    // SPRINT 7.4: Gebruik de lokale HealthKit bron (1 jaar aan data)
                    let syncService = HealthKitSyncService()
                    // Start asynchroon de HealthKit queries en verwerk in SwiftData
                    try await syncService.syncHistoricalWorkouts(to: modelContext)

                    await MainActor.run {
                        isSyncingHistory = false
                        feedbackMessage = "HealthKit historie (1 jaar) succesvol gesynchroniseerd."
                        refreshProfile() // Bereken het profiel direct opnieuw na de sync
                    }
                } else {
                    // SPRINT 6.1 & 7.4: Vraag maximaal 12 maanden (1 jaar) aan Strava activiteiten op
                    let activities = try await fitnessDataService.fetchHistoricalActivities(monthsBack: 12)

                    await MainActor.run {
                        // Zet de StravaActivity DTO's om naar ActivityRecord SwiftData models
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        let fallbackFormatter = ISO8601DateFormatter()

                        var newRecordsCount = 0

                        for activity in activities {
                            let currentId = String(activity.id)
                            let fetchDescriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.id == currentId })
                            let existing = try? modelContext.fetch(fetchDescriptor)

                            if existing?.isEmpty ?? true {
                                let date = formatter.date(from: activity.start_date) ?? fallbackFormatter.date(from: activity.start_date) ?? Date()

                                let record = ActivityRecord(
                                    id: currentId,
                                    name: activity.name,
                                    distance: activity.distance,
                                    movingTime: activity.moving_time,
                                    averageHeartrate: activity.average_heartrate,
                                    type: activity.type,
                                    startDate: date,
                                    trimp: nil
                                )
                                modelContext.insert(record)
                                newRecordsCount += 1
                            }
                        }

                        try? modelContext.save()
                        isSyncingHistory = false
                        feedbackMessage = "Strava synchronisatie voltooid (\(newRecordsCount) nieuwe trainingen over afgelopen jaar)."
                        refreshProfile() // Bereken het profiel direct opnieuw na de sync
                    }
                }
            } catch {
                await MainActor.run {
                    isSyncingHistory = false
                    feedbackMessage = "Synchronisatie mislukt: \(error.localizedDescription)"
                }
            }
        }
    }

    // Controleer de huidige status van Push Notifications toestemming
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsEnabled = (settings.authorizationStatus == .authorized)
            }
        }
    }

    // Vraag expliciet toestemming aan de gebruiker voor Push Notifications
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
                if granted {
                    // Registreer voor remote notifications nu we toestemming hebben
                    UIApplication.shared.registerForRemoteNotifications()
                    self.feedbackMessage = "Notificaties succesvol ingeschakeld."
                } else if let error = error {
                    self.feedbackMessage = "Fout bij aanvragen notificaties: \(error.localizedDescription)"
                } else {
                    self.feedbackMessage = "Notificatie toestemming geweigerd. Zet dit aan in de iOS Instellingen app."
                }
            }
        }
    }

    // Functie om Apple Health te koppelen
    private func koppelAppleHealth() {
        let healthKitManager = HealthKitManager()
        healthKitManager.requestAuthorization { success, error in
            DispatchQueue.main.async {
                if success {
                    self.isHealthKitLinked = true
                    self.feedbackMessage = "Apple Health succesvol gekoppeld."
                } else {
                    self.feedbackMessage = "Fout bij koppelen Apple Health: \(error?.localizedDescription ?? "Onbekende fout")"
                }
            }
        }
    }

    // Opslaan van ingevoerde waarden naar native Keychain
    private func saveTokens() {
        feedbackMessage = "Instellingen veilig opgeslagen"

        // Simuleer een feedback animatie, sluit daarna (of optioneel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }

    var body: some View {
        Form {
                Section(header: Text("Primaire Databron"), footer: Text("Kies welke bron als eerste aangesproken wordt voor analyses en historie.").font(.caption)) {
                    Picker("Databron", selection: $selectedDataSource) {
                        ForEach(DataSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(
                    header: Text("Strava Connectie"),
                    footer: Text("Koppel veilig met Strava via de officiële OAuth web flow. Tokens worden lokaal versleuteld opgeslagen.").font(.caption)
                ) {
                    if stravaAuthService.isAuthenticated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Gekoppeld aan Strava")
                        }

                        Button(role: .destructive, action: {
                            stravaAuthService.logout()
                        }) {
                            Text("Koppel los (Uitloggen)")
                        }
                    } else {
                        Button(action: {
                            stravaAuthService.authenticate()
                        }) {
                            HStack {
                                Image(systemName: "figure.run.circle.fill")
                                Text("Log in met Strava")
                                    .fontWeight(.bold)
                            }
                        }
                    }

                    if let errorMsg = stravaAuthService.authError {
                        Text(errorMsg)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section(
                    header: Text("Apple Health Integratie"),
                    footer: Text("Koppel lokaal met Apple Health voor fysiologische data. Er gaat geen data naar externe servers.").font(.caption)
                ) {
                    if isHealthKitLinked {
                        Button(action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Gekoppeld aan Apple Health")
                                    .foregroundColor(.primary)
                            }
                        }
                    } else {
                        Button(action: {
                            koppelAppleHealth()
                        }) {
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                                Text("Koppel Apple Health")
                                    .fontWeight(.bold)
                            }
                        }
                    }
                }

                Section(
                    header: Text("Historische Data & Atletisch Profiel"),
                    footer: Text("Haal 1 jaar (365 dagen) aan historie op uit de gekozen databron om de AI-coach context te geven over jouw fitnessniveau. Omdat de berekening asynchroon is, blijft de app gewoon bruikbaar.").font(.caption)
                ) {
                    Button(action: {
                        syncHistoricalData()
                    }) {
                        HStack {
                            if isSyncingHistory {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Bezig met ophalen (1 jaar)...")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Synchroniseer Geschiedenis (1 Jaar)")
                            }
                        }
                    }
                    .disabled(isSyncingHistory || (selectedDataSource == .strava && !stravaAuthService.isAuthenticated))

                    if let profile = athleticProfile {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Atletisch Profiel")
                                .font(.headline)
                                .padding(.bottom, 4)

                            HStack {
                                Image(systemName: "trophy")
                                    .foregroundColor(.yellow)
                                Text("Piekprestatie: \(String(format: "%.1f", profile.peakDistanceInMeters / 1000)) km / \(profile.peakDurationInSeconds / 60) min")
                                    .font(.subheadline)
                            }

                            HStack {
                                Image(systemName: "chart.bar")
                                    .foregroundColor(.blue)
                                Text("Wekelijks Volume: \(profile.averageWeeklyVolumeInSeconds / 60) min (gem. laatste 4 weken)")
                                    .font(.subheadline)
                            }

                            HStack {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(profile.daysSinceLastTraining > 5 ? .red : .green)
                                Text("Dagen sinds laatste training: \(profile.daysSinceLastTraining)")
                                    .font(.subheadline)
                            }

                            if profile.isRecoveryNeeded {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Overtrainingsrisico! Rust wordt aanbevolen.")
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(
                    header: Text("Notificaties"),
                    footer: Text("Ontvang direct een analyse van je AI coach nadat je een nieuwe activiteit hebt geüpload.").font(.caption)
                ) {
                    if notificationsEnabled {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .foregroundColor(.green)
                            Text("Notificaties zijn ingeschakeld")
                        }
                    } else {
                        Button(action: {
                            requestNotificationPermission()
                        }) {
                            HStack {
                                Image(systemName: "bell.badge")
                                Text("Schakel Push Notificaties in")
                            }
                        }
                    }
                }

                if let msg = feedbackMessage {
                    Section {
                        Text(msg)
                            .foregroundColor(msg == "Opslaan mislukt." ? .red : .green)
                    }
                }
        }
        .navigationTitle("Instellingen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Controleer of de view is gepresenteerd als sheet (via onDismiss/dismiss), of als root tab.
            // Aangezien het nu een Tab is, is de "Opslaan" knop (die dismiss() aanroept) overbodig.
            // We verbergen de knop voor een cleanere UI. Instellingen worden in de AppStorage / Keychain
            // toch al opgeslagen bij interactie (behalve tokens, maar dat gaat via webflow).
        }
        .onAppear {
            loadTokens()
        }
    }
}

/// Lijst met actieve voorkeuren en regels van de gebruiker (AI Context).
struct PreferencesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserPreference.createdAt, order: .reverse) private var preferences: [UserPreference]

    var body: some View {
        List {
            if preferences.isEmpty {
                Text("Geen voorkeuren gevonden. Vertel de coach in de chat wat je wensen of blessures zijn, en hij onthoudt het hier!")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(preferences) { preference in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preference.preferenceText)
                                .font(.body)
                                .foregroundColor(.primary)

                            Text("Gedetecteerd op: \(preference.createdAt, formatter: itemFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let expirationDate = preference.expirationDate {
                                let isExpired = expirationDate < Date()
                                Text(isExpired ? "Verlopen" : "Verloopt op: \(expirationDate, formatter: itemFormatter)")
                                    .font(.caption)
                                    .foregroundColor(isExpired ? .red : .orange)
                            }
                        }
                        Spacer()
                    }
                }
                .onDelete(perform: deleteItems)
            }
        }
        .navigationTitle("Coach Geheugen")
        .toolbar {
            EditButton()
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(preferences[index])
            }
            try? modelContext.save()
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()
