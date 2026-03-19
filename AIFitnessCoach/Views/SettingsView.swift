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
    @State private var intervalsToken: String = ""
    @AppStorage("intervalsAthleteId") private var intervalsAthleteId: String = ""

    @State private var feedbackMessage: String?
    @State private var notificationsEnabled: Bool = false

    // Historische sync state
    @State private var isSyncingHistory: Bool = false
    @State private var athleticProfile: AthleticProfile?

    // Dependency injection (voor tests of preview)
    var tokenStore: TokenStore = KeychainService.shared

    // Laden van opgeslagen waarden en rechten
    private func loadTokens() {
        stravaAuthService.checkAuthStatus()

        do {
            intervalsToken = try tokenStore.getToken(forService: "IntervalsToken") ?? ""
        } catch {
            print("SettingsView: Kon tokens niet veilig laden (\(error))")
        }

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

    // Synchroniseer historische Strava data naar SwiftData
    private func syncHistoricalData() {
        guard !isSyncingHistory else { return }
        isSyncingHistory = true
        feedbackMessage = "Synchroniseren gestart..."

        Task {
            do {
                let activities = try await fitnessDataService.fetchHistoricalActivities(monthsBack: 6)

                await MainActor.run {
                    // Zet de StravaActivity DTO's om naar ActivityRecord SwiftData models
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let fallbackFormatter = ISO8601DateFormatter()

                    var newRecordsCount = 0

                    for activity in activities {
                        let currentId = activity.id
                        let fetchDescriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.id == currentId })
                        let existing = try? modelContext.fetch(fetchDescriptor)

                        if existing?.isEmpty ?? true {
                            let date = formatter.date(from: activity.start_date) ?? fallbackFormatter.date(from: activity.start_date) ?? Date()

                            let record = ActivityRecord(
                                id: activity.id,
                                name: activity.name,
                                distance: activity.distance,
                                movingTime: activity.moving_time,
                                averageHeartrate: activity.average_heartrate,
                                type: activity.type,
                                startDate: date
                            )
                            modelContext.insert(record)
                            newRecordsCount += 1
                        }
                    }

                    try? modelContext.save()
                    isSyncingHistory = false
                    feedbackMessage = "Synchronisatie voltooid (\(newRecordsCount) nieuwe trainingen)."
                    refreshProfile() // Bereken het profiel direct opnieuw na de sync
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

    // Functie om de API call naar Intervals.icu te testen
    private func testIntervalsApi() {
        guard !intervalsToken.isEmpty && !intervalsAthleteId.isEmpty else {
            feedbackMessage = "Vul zowel Athlete ID als API Key in."
            return
        }

        feedbackMessage = "Testen van Intervals API..."

        Task {
            do {
                // Haal de meest recente activiteit uit SwiftData
                let fetchDescriptor = FetchDescriptor<ActivityRecord>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
                if let recentActivity = try modelContext.fetch(fetchDescriptor).first {

                    let apiService = IntervalsApiService(tokenStore: tokenStore)
                    // Bewaar token tijdelijk als deze nog niet was opgeslagen (want gebruiker klikt direct op testknop)
                    if let _ = try? tokenStore.getToken(forService: "IntervalsToken") {
                        // All good
                    } else {
                        try? tokenStore.saveToken(intervalsToken, forService: "IntervalsToken")
                    }

                    let activityDetails = try await apiService.fetchActivityDetails(athleteId: intervalsAthleteId, activityId: String(recentActivity.id))

                    print("--- Intervals.icu Test Resultaten ---")
                    print("Activiteit ID: \(recentActivity.id)")
                    print("TSS: \(activityDetails.tss ?? 0)")
                    print("Hartslagherstel: \(activityDetails.hrRecovery ?? 0)")
                    print("Cardiac Drift: \(activityDetails.cardiacDrift ?? 0)")
                    print("---------------------------------------")

                    await MainActor.run {
                        feedbackMessage = "Intervals test geslaagd! Zie Xcode console voor resultaten."
                    }
                } else {
                    await MainActor.run {
                        feedbackMessage = "Geen activiteiten gevonden in SwiftData om te testen. Synchroniseer eerst je geschiedenis."
                    }
                }
            } catch {
                await MainActor.run {
                    feedbackMessage = "Intervals test mislukt: \(error.localizedDescription)"
                    print("Intervals Test Error: \(error)")
                }
            }
        }
    }

    // Opslaan van ingevoerde waarden naar native Keychain
    private func saveTokens() {
        do {
            if !intervalsToken.isEmpty {
                try tokenStore.saveToken(intervalsToken, forService: "IntervalsToken")
            } else {
                try tokenStore.deleteToken(forService: "IntervalsToken")
            }

            feedbackMessage = "Instellingen veilig opgeslagen"

            // Simuleer een feedback animatie, sluit daarna (of optioneel)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }

        } catch {
            feedbackMessage = "Opslaan mislukt."
            print("SettingsView: Kon tokens niet veilig opslaan (\(error))")
        }
    }

    var body: some View {
        Form {
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
                    header: Text("Intervals.icu Connectie"),
                    footer: Text("API sleutels worden lokaal bewaard.").font(.caption)
                ) {
                    TextField("Athlete ID (bijv. i12345)", text: $intervalsAthleteId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Intervals.icu API Key", text: $intervalsToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button(action: {
                        testIntervalsApi()
                    }) {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("Test Intervals API")
                        }
                    }
                    .disabled(intervalsToken.isEmpty || intervalsAthleteId.isEmpty)
                }

                Section(
                    header: Text("Historische Data & Atletisch Profiel"),
                    footer: Text("Haal de laatste 6 maanden aan Strava data op om de AI-coach context te geven over jouw fitnessniveau.").font(.caption)
                ) {
                    Button(action: {
                        syncHistoricalData()
                    }) {
                        HStack {
                            if isSyncingHistory {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Bezig met synchroniseren...")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Synchroniseer Geschiedenis (Laatste 6 maanden)")
                            }
                        }
                    }
                    .disabled(isSyncingHistory || !stravaAuthService.isAuthenticated)

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
            ToolbarItem(placement: .confirmationAction) {
                Button("Opslaan") {
                    saveTokens()
                }
            }
        }
        .onAppear {
            loadTokens()
        }
    }
}
