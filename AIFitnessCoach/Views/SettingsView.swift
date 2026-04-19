import SwiftUI
import UserNotifications
import SwiftData

/// Beheer van externe API koppelingen en andere voorkeuren.
/// Deze view is toegankelijk via het instellingen-icoon en schrijft gegevens
/// veilig weg naar de KeychainService.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager

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

    // V2.0 extra state
    @AppStorage("vibecoach_userName")        private var userName: String = ""
    @AppStorage("vibecoach_userAPIKey")      private var apiKey: String = ""
    @AppStorage("vibecoach_aiProvider")      private var providerRaw: String = AIProvider.gemini.rawValue
    @AppStorage("vibecoach_notifPost")       private var notifPostWorkout: Bool = true
    @AppStorage("vibecoach_notifInactive")   private var notifInactivity: Bool = true
    @AppStorage("vibecoach_notifGoals")      private var notifGoalUpdates: Bool = true
    @AppStorage("vibecoach_notifWeekly")     private var notifWeeklyReport: Bool = false
    @AppStorage("vibecoach_bgSync")          private var backgroundSyncEnabled: Bool = true
    @AppStorage("vibecoach_colorScheme")     private var colorSchemeRaw: String = "auto"
    @State private var physicalProfile: UserPhysicalProfile?

    @State private var weeklyAvgMinutes: Int?

    private let settingsHKManager = HealthKitManager()
    private var settingsProfileService: UserProfileService {
        UserProfileService(healthStore: settingsHKManager.healthStore)
    }

    // Dependency injection (voor tests of preview)
    var tokenStore: TokenStore = KeychainService.shared

    // Laden van opgeslagen waarden en rechten
    private func loadTokens() {
        stravaAuthService.checkAuthStatus()
        checkNotificationStatus()
        refreshProfile()
        Task {
            await settingsProfileService.requestProfileReadAuthorization()
            let p = await settingsProfileService.fetchProfile()
            let secs = await settingsHKManager.fetchAverageWeeklyDurationSeconds()
            await MainActor.run {
                physicalProfile = p
                weeklyAvgMinutes = secs / 60
            }
        }
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

                                // SPRINT 12.4: Voeg basic TRIMP fallback toe bij sync
                                let basicTRIMPFallback: Double? = {
                                    if let hr = activity.average_heartrate, hr > 100 {
                                        // Super simpele Banister fallback als HR bekend is
                                        let durationMins = Double(activity.moving_time) / 60.0
                                        let simulatedDeltaHR = (hr - 60.0) / (190.0 - 60.0)
                                        return durationMins * simulatedDeltaHR * 0.64 * exp(1.92 * simulatedDeltaHR)
                                    } else {
                                        // Als niks bekend is, gebruik 1 minuut = 1.5 TRIMP als grove gok
                                        return (Double(activity.moving_time) / 60.0) * 1.5
                                    }
                                }()

                                let record = ActivityRecord(
                                    id: currentId,
                                    name: activity.name,
                                    distance: activity.distance,
                                    movingTime: activity.moving_time,
                                    averageHeartrate: activity.average_heartrate,
                                    sportCategory: SportCategory.from(rawString: activity.type),
                                    startDate: date,
                                    trimp: basicTRIMPFallback
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

    /// Verwijdert dubbele ActivityRecords uit SwiftData.
    /// Detecteert duplicaten op twee manieren:
    /// 1. Zelfde `id` (UUID) — normale race-condition duplicaten
    /// 2. Zelfde `startDate` + `sportCategory` — HealthKit-level duplicaten (zelfde workout, twee UUIDs)
    /// Behoudt altijd de eerste record (gesorteerd op startDate), verwijdert de rest.
    private func removeDuplicateRecords() {
        let descriptor = FetchDescriptor<ActivityRecord>(sortBy: [SortDescriptor(\.startDate, order: .forward)])
        guard let allRecords = try? modelContext.fetch(descriptor) else { return }

        var seenIds = Set<String>()
        // Composite key: "startDate_sportCategory" voor HealthKit-level duplicaten
        var seenCompositeKeys = Set<String>()
        var duplicatesRemoved = 0

        for record in allRecords {
            let compositeKey = "\(record.startDate.timeIntervalSince1970)_\(record.sportCategory.rawValue)"

            if seenIds.contains(record.id) || seenCompositeKeys.contains(compositeKey) {
                modelContext.delete(record)
                duplicatesRemoved += 1
            } else {
                seenIds.insert(record.id)
                seenCompositeKeys.insert(compositeKey)
            }
        }

        try? modelContext.save()
        feedbackMessage = duplicatesRemoved > 0
            ? "\(duplicatesRemoved) dubbele activiteit(en) verwijderd."
            : "Geen duplicaten gevonden — database is schoon."
    }

    // Opslaan van ingevoerde waarden naar native Keychain
    private func saveTokens() {
        feedbackMessage = "Instellingen veilig opgeslagen"

        // Simuleer een feedback animatie, sluit daarna (of optioneel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }

    // MARK: - V2.0 Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Header
                    VStack(alignment: .leading, spacing: 2) {
                        Text("V1.0.2 · BUILD 42")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.secondary).kerning(0.5)
                        Text("Instellingen")
                            .font(.largeTitle).fontWeight(.bold)
                    }
                    .padding(.horizontal)
                    .padding(.top, 56)
                    .padding(.bottom, 24)

                    // ── VERBINDINGEN
                    settingsSectionLabel("VERBINDINGEN")
                    HStack(spacing: 10) {
                        SettingsConnectionCard(
                            icon: "applewatch",
                            title: "HealthKit",
                            subtitle: isHealthKitLinked ? "Primair · Live" : "Niet gekoppeld",
                            isConnected: isHealthKitLinked,
                            accentColor: themeManager.primaryAccentColor
                        )
                        SettingsConnectionCard(
                            icon: "figure.run",
                            title: "Strava",
                            subtitle: stravaAuthService.isAuthenticated ? "Backup" : "Niet gekoppeld",
                            isConnected: stravaAuthService.isAuthenticated,
                            accentColor: themeManager.primaryAccentColor
                        )
                        SettingsConnectionCard(
                            icon: "sparkles",
                            title: "AI Coach",
                            subtitle: AIProvider(rawValue: providerRaw)?.displayName.components(separatedBy: " ").first ?? "Gemini",
                            isConnected: !apiKey.isEmpty,
                            accentColor: themeManager.primaryAccentColor
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)

                    // ── JOUW PROFIEL
                    settingsSectionLabel("JOUW PROFIEL")
                    settingsCard {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(themeManager.primaryAccentColor.opacity(0.18))
                                    .frame(width: 54, height: 54)
                                Text(userInitials)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(themeManager.primaryAccentColor)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(userName.isEmpty ? "Gebruiker" : userName)
                                    .font(.headline)
                                Text(demographicsLine)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(16)
                    }
                    .padding(.bottom, 24)

                    // ── FYSIOLOGISCH PROFIEL
                    settingsSectionLabel("FYSIOLOGISCH PROFIEL")
                    settingsCard {
                        NavigationLink(destination: PhysicalProfileEditView()) {
                            SettingsRowV2(
                                icon: "person.fill",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Leeftijd",
                                value: physicalProfile.map { "\($0.ageYears) j" },
                                isLocked: true
                            )
                        }.buttonStyle(.plain)
                        settingsDivider
                        NavigationLink(destination: PhysicalProfileEditView()) {
                            SettingsRowV2(
                                icon: "figure.stand",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Geslacht",
                                value: physicalProfile.map { physSexLabel($0.sex) },
                                isLocked: true
                            )
                        }.buttonStyle(.plain)
                        settingsDivider
                        NavigationLink(destination: PhysicalProfileEditView()) {
                            SettingsRowV2(
                                icon: "scalemass.fill",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Gewicht",
                                value: physicalProfile.map { String(format: "%.1f kg", $0.weightKg) },
                                hasChevron: true,
                                showHealthKitBadge: physicalProfile?.weightSource == .healthKit
                            )
                        }.buttonStyle(.plain)
                        settingsDivider
                        NavigationLink(destination: PhysicalProfileEditView()) {
                            SettingsRowV2(
                                icon: "ruler.fill",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Lengte",
                                value: physicalProfile.map { String(format: "%.0f cm", $0.heightCm) },
                                hasChevron: true,
                                showHealthKitBadge: physicalProfile?.heightSource == .healthKit
                            )
                        }.buttonStyle(.plain)
                    }
                    Text("Leeftijd en geslacht worden gelezen uit Apple Gezondheid en zijn hier niet te bewerken. Gewicht en lengte schrijven we terug naar HealthKit.")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal).padding(.top, 6)
                    Spacer(minLength: 24)

                    // ── ATLETISCH PROFIEL
                    settingsSectionLabel("ATLETISCH PROFIEL")
                    settingsCard {
                        if let profile = athleticProfile {
                            SettingsRowV2(
                                icon: "trophy.fill",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Piekprestatie",
                                subtitle: "Langste activiteit in 365 dagen",
                                value: "\(String(format: "%.1f", profile.peakDistanceInMeters/1000)) km / \(profile.peakDurationInSeconds/60) min"
                            )
                            settingsDivider
                            SettingsRowV2(
                                icon: "chart.bar.fill",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Wekelijks volume",
                                subtitle: "Gem. laatste 4 weken (HealthKit)",
                                value: weeklyAvgMinutes.map { "\($0) min" } ?? "\(profile.averageWeeklyVolumeInSeconds/60) min"
                            )
                            settingsDivider
                            SettingsRowV2(
                                icon: "calendar",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Dagen sinds laatste training",
                                subtitle: "Herstel-indicator",
                                value: "\(profile.daysSinceLastTraining) dagen"
                            )
                            if profile.isRecoveryNeeded {
                                settingsDivider
                                SettingsRowV2(
                                    icon: "exclamationmark.triangle.fill",
                                    iconColor: .orange,
                                    title: "Overtrainingsrisico",
                                    subtitle: profile.recoveryReason ?? "Rust wordt aanbevolen.",
                                    isWarning: true
                                )
                            }
                            settingsDivider
                        }
                        Button { syncHistoricalData() } label: {
                            SettingsRowV2(
                                icon: "arrow.triangle.2.circlepath",
                                iconColor: themeManager.primaryAccentColor,
                                title: isSyncingHistory ? "Bezig..." : "Synchroniseer historie",
                                subtitle: "Haal 1 jaar (365 dagen) op",
                                value: isSyncingHistory ? nil : "1 jaar",
                                hasChevron: !isSyncingHistory
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSyncingHistory)
                    }
                    Text("Afgeleid uit je trainingsgeschiedenis. Sync 1 jaar aan historie om de coach context te geven over je fitnessniveau.")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal).padding(.top, 6)
                    Spacer(minLength: 24)

                    // ── UITERLIJK
                    settingsSectionLabel("UITERLIJK")
                    settingsCard {
                        HStack {
                            Text("Thema")
                                .font(.subheadline)
                                .padding(.leading, 14)
                            Spacer()
                            HStack(spacing: 10) {
                                ForEach(Theme.allCases.prefix(3), id: \.id) { theme in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            themeManager.currentTheme = theme
                                        }
                                    } label: {
                                        Circle()
                                            .fill(theme.previewColor)
                                            .frame(width: 30, height: 30)
                                            .overlay(
                                                Circle().strokeBorder(
                                                    themeManager.currentTheme == theme
                                                        ? Color.primary.opacity(0.8) : Color.clear,
                                                    lineWidth: 2.5
                                                )
                                            )
                                    }
                                }
                            }
                            .padding(.trailing, 14)
                        }
                        .padding(.vertical, 14)
                        settingsDivider
                        HStack {
                            Text("Modus")
                                .font(.subheadline)
                                .padding(.leading, 14)
                            Spacer()
                            Picker("", selection: $colorSchemeRaw) {
                                Text("Licht").tag("light")
                                Text("Donker").tag("dark")
                                Text("Auto").tag("auto")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                            .padding(.trailing, 14)
                        }
                        .padding(.vertical, 10)
                    }
                    .padding(.bottom, 24)

                    // ── PRIMAIRE DATABRON
                    settingsSectionLabel("PRIMAIRE DATABRON")
                    settingsCard {
                        Picker("", selection: $selectedDataSource) {
                            ForEach(DataSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(14)
                    }
                    Text("Welke bron wordt als eerste aangesproken voor analyses en historie.")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal).padding(.top, 6)
                    Spacer(minLength: 24)

                    // ── AI COACH
                    settingsSectionLabel("AI COACH")
                    settingsCard {
                        NavigationLink(destination: AIProviderSettingsView()) {
                            SettingsRowV2(
                                icon: "sparkles",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Provider",
                                value: AIProvider(rawValue: providerRaw)?.displayName ?? "Gemini",
                                hasChevron: true
                            )
                        }.buttonStyle(.plain)
                        settingsDivider
                        NavigationLink(destination: AIProviderSettingsView()) {
                            SettingsRowV2(
                                icon: "key.fill",
                                iconColor: themeManager.primaryAccentColor,
                                title: "API-sleutel",
                                value: apiKey.isEmpty ? "Niet ingesteld" : "···· \(String(apiKey.suffix(4)))",
                                hasChevron: true
                            )
                        }.buttonStyle(.plain)
                        settingsDivider
                        HStack {
                            Text("Achtergrond-sync")
                                .font(.subheadline)
                                .padding(.leading, 14)
                            Spacer()
                            Toggle("", isOn: $backgroundSyncEnabled)
                                .labelsHidden()
                                .tint(themeManager.primaryAccentColor)
                                .padding(.trailing, 14)
                        }
                        .padding(.vertical, 12)
                    }
                    Text("Sleutels worden lokaal versleuteld in de iOS Keychain opgeslagen.")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal).padding(.top, 6)
                    Spacer(minLength: 24)

                    // ── NOTIFICATIES
                    settingsSectionLabel("NOTIFICATIES")
                    settingsCard {
                        notifRow(icon: "bell.fill",     title: "Analyse na activiteit",
                                 subtitle: "Coach-bericht na upload van een nieuwe workout",
                                 binding: $notifPostWorkout)
                        settingsDivider
                        notifRow(icon: "moon.fill",     title: "Inactiviteitscheck",
                                 subtitle: "Herinnering na 48 uur zonder beweging",
                                 binding: $notifInactivity)
                        settingsDivider
                        notifRow(icon: "flag.fill",     title: "Doel-updates",
                                 subtitle: "Voortgang richting weekdoel",
                                 binding: $notifGoalUpdates)
                        settingsDivider
                        notifRow(icon: "chart.bar.fill", title: "Wekelijks rapport",
                                 subtitle: "Elke zondag 20:00",
                                 binding: $notifWeeklyReport)
                    }
                    Text("Gedetailleerde permissies beheer je in iOS Instellingen › VibeCoach.")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal).padding(.top, 6)
                    Spacer(minLength: 24)

                    // ── VERBINDINGSDETAILS
                    settingsSectionLabel("VERBINDINGSDETAILS")
                    settingsCard {
                        Button {
                            if isHealthKitLinked {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } else { koppelAppleHealth() }
                        } label: {
                            SettingsRowV2(
                                icon: "applewatch",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Apple HealthKit",
                                subtitle: isHealthKitLinked ? "Laatste sync bekijken" : "Koppel Apple Health",
                                value: "Beheer",
                                hasChevron: true
                            )
                        }.buttonStyle(.plain)
                        settingsDivider
                        Button {
                            stravaAuthService.isAuthenticated
                                ? stravaAuthService.logout()
                                : stravaAuthService.authenticate()
                        } label: {
                            SettingsRowV2(
                                icon: "figure.run",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Strava",
                                subtitle: stravaAuthService.isAuthenticated ? "Gekoppeld" : "Niet gekoppeld",
                                value: "Beheer",
                                hasChevron: true
                            )
                        }.buttonStyle(.plain)
                    }
                    .padding(.bottom, 24)

                    // ── Developer Tools (behouden voor debug)
                    #if targetEnvironment(simulator)
                    settingsSectionLabel("DEVELOPER (SIMULATOR)")
                    settingsCard {
                        Button { generateDummyData() } label: {
                            SettingsRowV2(icon: "hammer.fill", iconColor: .purple,
                                          title: "Genereer Test Data")
                        }.buttonStyle(.plain)
                    }.padding(.bottom, 24)
                    #endif

                    #if DEBUG
                    settingsSectionLabel("DEVELOPER (DEBUG)")
                    settingsCard {
                        Button {
                            feedbackMessage = "Engines worden afgevuurd..."
                            Task {
                                await ProactiveNotificationService.shared.debugTriggerEngines()
                                await MainActor.run { feedbackMessage = "Klaar! Controleer je notificaties." }
                            }
                        } label: {
                            SettingsRowV2(icon: "bolt.fill", iconColor: .orange,
                                          title: "Forceer Achtergrond Sync")
                        }.buttonStyle(.plain)
                        settingsDivider
                        Button { removeDuplicateRecords() } label: {
                            SettingsRowV2(icon: "trash.slash.fill", iconColor: .red,
                                          title: "Verwijder Dubbele Activiteiten")
                        }.buttonStyle(.plain)
                    }.padding(.bottom, 24)
                    #endif

                    if let msg = feedbackMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(msg.contains("mislukt") ? .red : .green)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color(.secondarySystemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { loadTokens() }
        }
    }

    // MARK: - V2.0 Helper views

    private var settingsDivider: some View {
        Divider().padding(.leading, 60)
    }

    @ViewBuilder
    private func settingsSectionLabel(_ label: String) -> some View {
        Text(label)
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(.secondary).kerning(0.5)
            .padding(.horizontal)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
    }

    private func notifRow(icon: String, title: String, subtitle: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(themeManager.primaryAccentColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.primaryAccentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(themeManager.primaryAccentColor)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }

    // MARK: - Helpers

    private var userInitials: String {
        let parts = userName.split(separator: " ")
        return parts.compactMap { $0.first }.prefix(2).map(String.init).joined().uppercased()
    }

    private var demographicsLine: String {
        guard let p = physicalProfile else { return "Profiel laden…" }
        return "\(p.ageYears) j · \(physSexLabel(p.sex)) · \(String(format: "%.0f", p.weightKg)) kg · \(String(format: "%.0f", p.heightCm)) cm"
    }

    private func physSexLabel(_ sex: BiologicalSex) -> String {
        switch sex {
        case .male:    return "Man"
        case .female:  return "Vrouw"
        case .other:   return "Divers"
        case .unknown: return "Onbekend"
        }
    }

    #if targetEnvironment(simulator)
    private func generateDummyData() {
        feedbackMessage = "Genereren van dummy data..."

        Task { @MainActor in
            let calendar = Calendar.current
            let now = Date()

            // 1. Voeg een dummy FitnessGoal toe (Marathon)
            let targetDate = calendar.date(byAdding: .day, value: 60, to: now)! // Over 2 maanden
            let createdDate = calendar.date(byAdding: .day, value: -30, to: now)! // 1 maand geleden gestart

            let goal = FitnessGoal(
                title: "Amsterdam Marathon (Test)",
                details: "Gegenereerd via simulator tools",
                targetDate: targetDate,
                createdAt: createdDate,
                sportCategory: .running,
                targetTRIMP: 6500.0
            )
            modelContext.insert(goal)

            // 2. Voeg 5 realistische activiteiten toe in de afgelopen 45 dagen
            let workoutDates = [
                calendar.date(byAdding: .day, value: -35, to: now)!, // Time Travel: Voor de createdAt!
                calendar.date(byAdding: .day, value: -20, to: now)!,
                calendar.date(byAdding: .day, value: -12, to: now)!,
                calendar.date(byAdding: .day, value: -7, to: now)!,
                calendar.date(byAdding: .day, value: -2, to: now)!
            ]

            let trimps = [150.0, 210.0, 180.0, 320.0, 140.0]
            let durations = [2700, 3600, 3200, 5400, 2400]
            let names = ["Recovery Run", "Tempo Run", "Endurance", "Long Run", "Shakeout"]

            for (index, date) in workoutDates.enumerated() {
                let record = ActivityRecord(
                    id: "dummy_\(index)_\(Int(date.timeIntervalSince1970))",
                    name: names[index],
                    distance: Double(durations[index]) * 2.5, // Ruwe schatting
                    movingTime: durations[index],
                    averageHeartrate: 145.0 + Double(index * 2),
                    sportCategory: .running,
                    startDate: date,
                    trimp: trimps[index]
                )
                modelContext.insert(record)
            }

            try? modelContext.save()
            feedbackMessage = "Dummy data gegenereerd! Ga naar het Dashboard."
            refreshProfile()
        }
    }
    #endif
}

// MARK: - V2.0 Componenten

struct SettingsConnectionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isConnected: Bool
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(accentColor)
                }
                Spacer()
                Circle()
                    .fill(isConnected ? Color.green : Color(.systemGray4))
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

struct SettingsRowV2: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var hasChevron: Bool = false
    var isLocked: Bool = false
    var isWarning: Bool = false
    var showHealthKitBadge: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isWarning ? Color.orange.opacity(0.12) : iconColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isWarning ? .orange : iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isWarning ? .orange : .primary)
                if let sub = subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if let val = value {
                Text(val)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if showHealthKitBadge {
                Image(systemName: "applewatch")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(Color(.systemGray3))
            } else if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(.systemGray3))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(isWarning ? Color.orange.opacity(0.05) : Color.clear)
    }
}

struct PhysicalProfileEditView: View {
    var body: some View {
        Form {
            PhysicalProfileSection()
        }
        .navigationTitle("Fysiologisch Profiel")
    }
}

// MARK: - Epic 29 Sprint 2 & 3: Thema Picker Sectie

struct ThemePickerSection: View {
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
        Section(header: Text("Uiterlijk")) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Thema")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(Theme.allCases, id: \.id) { theme in
                            ThemeCircleButton(
                                theme: theme,
                                isSelected: themeManager.currentTheme == theme
                            ) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    themeManager.currentTheme = theme
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("Kleurintensiteit")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.gray.opacity(0.4))
                        .font(.caption)
                    Slider(value: $themeManager.themeSaturation, in: 0.3...1.0, step: 0.05)
                        .tint(themeManager.primaryAccentColor)
                    Image(systemName: "circle.fill")
                        .foregroundStyle(themeManager.primaryAccentColor)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ThemeCircleButton: View {
    let theme: Theme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(theme.previewColor)
                        .frame(width: 44, height: 44)

                    if isSelected {
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.8), lineWidth: 2.5)
                            .frame(width: 52, height: 52)
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .shadow(radius: 1)
                    }

                    Image(systemName: theme.defaultIcon)
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
                }

                Text(theme.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Epic 24 Sprint 2: Fysiologisch Profiel Sectie

/// Toont en beheert het fysiologische profiel van de gebruiker.
/// Leeftijd en geslacht zijn read-only (komen uit HealthKit Gezondheid-app).
/// Gewicht en lengte zijn bewerkbaar en worden gesynchroniseerd met HealthKit.
struct PhysicalProfileSection: View {
    // De manager wordt als property gehouden zodat healthStore niet direct-deallocated wordt.
    private let hkManager = HealthKitManager()
    private var profileService: UserProfileService { UserProfileService(healthStore: hkManager.healthStore) }

    // Huidig geladen profiel
    @State private var profile: UserPhysicalProfile?

    // Bewerkbare velden (als String voor TextField)
    @State private var weightInput: String = ""
    @State private var heightInput: String = ""

    // UI state
    @State private var isLoading     = true
    @State private var isSaving      = false
    @State private var saveMessage: String?
    /// .savedToHealthKit → groen, .savedLocallyOnly → oranje
    @State private var saveResult: UserProfileService.SaveResult?
    /// Tijdstip van de laatste succesvolle HealthKit-refresh — voor de sync-indicator.
    @State private var lastRefreshed: Date?

    /// Coach-melding bij profielwijziging — wordt éénmalig in de eerstvolgende AI-prompt gezet.
    @AppStorage("vibecoach_profileUpdateNote") private var profileUpdateNote: String = ""

    // Detecteer of de gebruiker iets heeft gewijzigd ten opzichte van het geladen profiel
    private var hasChanges: Bool {
        guard let p = profile else { return false }
        return weightInput != String(format: "%.1f", p.weightKg)
            || heightInput != String(format: "%.0f", p.heightCm)
    }

    var body: some View {
        Section(
            header: Text("Fysiologisch Profiel"),
            footer: profileFooter
        ) {
            if isLoading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 6)
                    Text("Profiel ophalen via HealthKit…")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } else {
                // Sync-indicator — toont tijdstip van laatste HealthKit-refresh
                if let ts = lastRefreshed {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Gesynchroniseerd om \(ts, format: .dateTime.hour().minute())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await loadProfile() }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                Text("Ververs")
                            }
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Leeftijd — read-only via HealthKit
                profileRow(
                    icon: "person.circle",
                    iconColor: .blue,
                    label: "Leeftijd",
                    value: profile.map { "\($0.ageYears) jaar" } ?? "Onbekend",
                    isReadOnly: true
                )

                // Geslacht — read-only via HealthKit
                profileRow(
                    icon: "figure.stand",
                    iconColor: .indigo,
                    label: "Geslacht",
                    value: profile.map { sexLabel($0.sex) } ?? "Onbekend",
                    isReadOnly: true
                )

                // Gewicht — bewerkbaar
                editableRow(
                    icon: "scalemass",
                    iconColor: .orange,
                    label: "Gewicht",
                    unit: "kg",
                    binding: $weightInput,
                    source: profile?.weightSource
                )

                // Lengte — bewerkbaar
                editableRow(
                    icon: "ruler",
                    iconColor: .teal,
                    label: "Lengte",
                    unit: "cm",
                    binding: $heightInput,
                    source: profile?.heightSource
                )

                // Opslaan-knop (alleen zichtbaar bij wijzigingen)
                if hasChanges {
                    Button {
                        saveProfile()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().padding(.trailing, 4)
                                Text("Opslaan…")
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Opslaan & Sync met HealthKit")
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .disabled(isSaving)
                }

                // Feedback na opslaan
                if let msg = saveMessage {
                    let (icon, color): (String, Color) = {
                        switch saveResult {
                        case .savedToHealthKit:   return ("checkmark.circle.fill", .green)
                        case .savedLocallyOnly:   return ("exclamationmark.circle.fill", .orange)
                        case nil:                 return ("xmark.circle.fill", .red)
                        }
                    }()
                    Label(msg, systemImage: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                }
            }
        }
        // onAppear garandeert een verse HealthKit-fetch bij elke keer dat de sectie zichtbaar wordt,
        // ook als de SettingsView in memory blijft (tabs). .task wordt enkel bij de eerste render
        // uitgevoerd in statische forms — vandaar de overstap naar onAppear.
        .onAppear { Task { await loadProfile() } }
    }

    // MARK: - Sub-views

    /// Rij voor een read-only waarde (leeftijd, geslacht — komen uit HealthKit).
    private func profileRow(icon: String, iconColor: Color, label: String, value: String, isReadOnly: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 26)
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            if isReadOnly {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Rij voor een bewerkbare waarde (gewicht, lengte).
    private func editableRow(
        icon: String,
        iconColor: Color,
        label: String,
        unit: String,
        binding: Binding<String>,
        source: UserPhysicalProfile.DataSource?
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 26)
            Text(label)
            Spacer()
            TextField("0", text: binding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            // Bronbadge
            if let src = source {
                sourceBadge(src)
            }
        }
    }

    /// Klein badge dat aangeeft waar de waarde vandaan komt.
    @ViewBuilder
    private func sourceBadge(_ source: UserPhysicalProfile.DataSource) -> some View {
        switch source {
        case .healthKit:
            Image(systemName: "heart.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .local:
            Image(systemName: "iphone")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .defaultValue:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    private var profileFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Leeftijd en geslacht worden gelezen uit de iOS Gezondheid-app en zijn hier niet te bewerken.")
            Text("Gewicht en lengte worden gesynchroniseerd naar HealthKit zodat het hele iOS-ecosysteem up-to-date blijft.")
        }
        .font(.caption)
    }

    // MARK: - Logica

    private func loadProfile() async {
        isLoading = true

        // Vraag eerst expliciet leesrechten voor de profieltypen.
        // Voor gebruikers die HealthKit koppelden vóór Epic 24 zijn dateOfBirth,
        // biologicalSex, bodyMass en height nog nooit gevraagd — iOS toont de popup
        // pas als we ze hier uitdrukkelijk opnemen in requestAuthorization.
        await profileService.requestProfileReadAuthorization()

        let loaded = await profileService.fetchProfile()

        // Detecteer of de leeftijd is gewijzigd ten opzichte van de vorige fetch.
        // Als dat zo is, schrijven we een eenmalige coach-melding die bij de
        // eerstvolgende AI-vraag wordt geïnjecteerd (via vibecoach_profileUpdateNote).
        let ageChanged = profileService.checkAndUpdateAgeCache(newAge: loaded.ageYears)
        if ageChanged {
            let bmr = Int(NutritionService.calculateBMR(profile: loaded).rounded())
            profileUpdateNote = """
            [PROFIEL BIJGEWERKT — VERPLICHTE VERMELDING]:
            De leeftijd van de gebruiker is bijgewerkt naar \(loaded.ageYears) jaar (eerder opgeslagen waarde was anders). \
            Het basaal metabolisme (BMR) is herberekend naar ~\(bmr) kcal/dag op basis van het nieuwe profiel (\(loaded.coachSummary)). \
            Vernoem dit expliciet aan het begin van je eerstvolgende Insight of antwoord: \
            "Ik heb je profiel bijgewerkt naar \(loaded.ageYears) jaar; je dagelijkse energiebehoefte (BMR) is nu ~\(bmr) kcal/dag." \
            Pas voedings- en trainingsadviezen hierop aan.
            """
            print("📣 [ProfileSection] Profielwijziging gedetecteerd — coach-note geschreven voor leeftijd \(loaded.ageYears)j, BMR ~\(bmr) kcal")
        }

        await MainActor.run {
            profile       = loaded
            weightInput   = String(format: "%.1f", loaded.weightKg)
            heightInput   = String(format: "%.0f", loaded.heightCm)
            isLoading     = false
            lastRefreshed = Date()
        }
    }

    private func saveProfile() {
        guard let p = profile else { return }
        let newWeight = Double(weightInput.replacingOccurrences(of: ",", with: ".")) ?? p.weightKg
        let newHeight = Double(heightInput.replacingOccurrences(of: ",", with: ".")) ?? p.heightCm

        isSaving    = true
        saveMessage = nil
        saveResult  = nil

        Task {
            // Sla elke gewijzigde waarde op en verzamel de resultaten.
            // UserDefaults wordt altijd bijgewerkt; HealthKit alleen bij toestemming.
            var results: [UserProfileService.SaveResult] = []
            if newWeight != p.weightKg { results.append(await profileService.saveWeight(kg: newWeight)) }
            if newHeight != p.heightCm { results.append(await profileService.saveHeight(cm: newHeight)) }

            // Herlaad het profiel zodat bronbadges bijgewerkt worden
            await loadProfile()

            // Samenvoegen: als minstens één waarde naar HealthKit ging → groen, anders → oranje
            let combinedResult: UserProfileService.SaveResult
            let allHealthKit = results.allSatisfy {
                if case .savedToHealthKit = $0 { return true }
                return false
            }
            let firstLocalReason: String? = results.compactMap {
                if case .savedLocallyOnly(let reason) = $0 { return reason }
                return nil
            }.first

            if allHealthKit {
                combinedResult = .savedToHealthKit
            } else {
                combinedResult = .savedLocallyOnly(firstLocalReason ?? "Lokaal opgeslagen.")
            }

            await MainActor.run {
                isSaving   = false
                saveResult = combinedResult
                switch combinedResult {
                case .savedToHealthKit:
                    saveMessage = "Opgeslagen en gesynchroniseerd met HealthKit."
                case .savedLocallyOnly(let reason):
                    saveMessage = "Lokaal opgeslagen. \(reason)"
                }
            }
        }
    }

    private func sexLabel(_ sex: BiologicalSex) -> String {
        switch sex {
        case .male:    return "Man"
        case .female:  return "Vrouw"
        case .other:   return "Divers"
        case .unknown: return "Onbekend"
        }
    }
}

// MARK: - Epic 20: AI Coach Configuratie (BYOK)

/// Instellingenscherm waar de gebruiker zijn eigen AI-provider en API-sleutel configureert.
/// De sleutel wordt opgeslagen in AppStorage (lokaal op het apparaat, niet gedeeld).
struct AIProviderSettingsView: View {
    @AppStorage("vibecoach_aiProvider")  private var providerRaw: String = AIProvider.gemini.rawValue
    @AppStorage("vibecoach_userAPIKey") private var apiKey: String = ""
    @EnvironmentObject private var themeManager: ThemeManager

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: providerRaw) ?? .gemini
    }

    var body: some View {
        Form {
            // Provider picker
            Section(header: Text("AI Provider")) {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(AIProvider.allCases) { provider in
                        HStack {
                            Text(provider.displayName)
                            if !provider.isSupported {
                                Spacer()
                                Text("Binnenkort")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(provider.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            // API sleutel invoer
            Section(
                header: Text("API Sleutel"),
                footer: VStack(alignment: .leading, spacing: 6) {
                    Text("VibeCoach gebruikt jouw eigen API-sleutel om de AI te activeren. De sleutel wordt uitsluitend lokaal op dit apparaat opgeslagen en nooit gedeeld met derden.")
                        .font(.caption)
                    if let url = selectedProvider.getKeyURL {
                        Link("Hoe kom ik aan een sleutel? →", destination: url)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            ) {
                SecureField(selectedProvider.keyPlaceholder, text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("APIKeyField")

                if !selectedProvider.isSupported {
                    HStack {
                        Image(systemName: "info.circle").foregroundColor(.orange)
                        Text("\(selectedProvider.displayName) wordt binnenkort ondersteund. Selecteer Gemini voor directe AI-coaching.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Status indicator
            if !apiKey.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(themeManager.primaryAccentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sleutel geconfigureerd")
                                .fontWeight(.medium)
                            Text("Je AI Coach is actief en klaar voor gebruik.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("AI Coach Configuratie")
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
