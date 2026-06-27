import SwiftUI
import UserNotifications
import SwiftData

/// Management of external API connections and other preferences.
/// This view is accessible via the settings icon and writes data
/// securely to the KeychainService.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager

    // Authentication service for Strava OAuth web flow
    @StateObject private var stravaAuthService = StravaAuthService()
    private let fitnessDataService = FitnessDataService()
    private let profileManager = AthleticProfileManager()

    // UI state variables, read from and written to Keychain
    @State private var feedbackMessage: String?
    @State private var notificationsEnabled: Bool = false
    // Epic 34 Sprint 2: material overlay below the status bar once scrolled.
    @State private var isSettingsScrolled: Bool = false
    @AppStorage("isHealthKitLinked") private var isHealthKitLinked: Bool = false

    @AppStorage("selectedDataSource") private var selectedDataSource: DataSource = .healthKit

    // Historical sync state
    @State private var isSyncingHistory: Bool = false
    @State private var athleticProfile: AthleticProfile?

    // V2.0 extra state
    @AppStorage("vibecoach_userName")        private var userName: String = ""
    // C-02: API key lives in the Keychain, not in AppStorage.
    // `loadTokens()` reloads the value from the Keychain on every onAppear.
    @State                                   private var apiKey: String = ""
    @AppStorage("vibecoach_aiProvider")      private var providerRaw: String = AIProvider.gemini.rawValue
    // Epic 43 Story 43.1: read the user-chosen Gemini model for the
    // dynamic AI Coach card subtitle. The same key that `AIProviderSettingsView`
    // uses — SwiftUI syncs automatically across all @AppStorage bindings.
    @AppStorage(AIModelAppStorageKey.primary)
    private var primaryModelId: String = AIModelAppStorageKey.defaultPrimary
    // Epic 34 Sprint 2: toggles without backend logic removed.
    // Notification switches and background sync return once the
    // `ProactiveNotificationService` can be configured per channel.
    @AppStorage("vibecoach_colorScheme")     private var colorSchemeRaw: String = "auto"
    // Epic #37 story 37.5: app language preference (drives `.environment(\.locale, …)` at the app root).
    @AppStorage(AppLanguage.storageKey)      private var appLanguageRaw: String = AppLanguage.system.rawValue
    // Epic #37 story 37.1: shown after a language change — UI-string switch needs a relaunch.
    @State private var showLanguageRelaunchNote = false
    @State private var physicalProfile: UserPhysicalProfile?

    @State private var weeklyAvgMinutes: Int?
    @State private var vo2Max: Double?

    private let settingsHKManager = HealthKitManager()
    private var settingsProfileService: UserProfileService {
        UserProfileService(healthStore: settingsHKManager.healthStore)
    }

    // Dependency injection (for tests or preview)
    var tokenStore: TokenStore = KeychainService.shared

    // MARK: - Connection card subtitles (Epic 43 Story 43.1)
    //
    // Reflect the actual connection state: connected? source preference or
    // supplementary according to `selectedDataSource`? which AI model? Since Epic #42
    // both sources always sync, so the toggle is a preference — no longer an
    // exclusive "what do I sync" choice.

    // Epic #37 story 37.1c: these subtitles render via SettingsRowV2 -> LocalizedStringKey(sub).
    // Single-word returns ("Voorkeur"/"Aanvullend"/"Niet gekoppeld") resolve through that wrapper
    // directly; the composite "· Live" variant is assembled from already-localized parts here.
    private var healthKitConnectionSubtitle: String {
        guard isHealthKitLinked else { return String(localized: "Niet gekoppeld") }
        let pref = selectedDataSource == .healthKit ? String(localized: "Voorkeur") : String(localized: "Aanvullend")
        return "\(pref) · Live"
    }

    private var stravaConnectionSubtitle: String {
        guard stravaAuthService.isAuthenticated else { return String(localized: "Niet gekoppeld") }
        return selectedDataSource == .strava ? String(localized: "Voorkeur") : String(localized: "Aanvullend")
    }

    /// Epic 44 Story 44.4: brief summary of the configured thresholds for the
    /// "TRAININGSDREMPELS" row. Shows only the thresholds that actually have a
    /// value — empty if nothing has been set yet.
    private var trainingThresholdsSubtitle: String {
        let cached = UserProfileService.cachedProfile()
        var parts: [String] = []
        if let max  = cached.maxHeartRate?.value, max > 0 { parts.append("Max \(Int(max))") }
        if let rest = cached.restingHeartRate?.value, rest > 0 { parts.append("Rust \(Int(rest))") }
        if let lthr = cached.lactateThresholdHR?.value, lthr > 0 { parts.append("LTHR \(Int(lthr))") }
        if let ftp  = cached.ftp?.value, ftp > 0 { parts.append("FTP \(Int(ftp))") }
        return parts.isEmpty ? "Niet ingesteld" : parts.joined(separator: " · ")
    }

    private var aiCoachConnectionSubtitle: String {
        guard !apiKey.isEmpty, let provider = AIProvider(rawValue: providerRaw) else {
            return "Geen sleutel"
        }
        let shortName = provider.shortName
        // For Gemini we also show the chosen model (Epic #35) — e.g. "Gemini · flash-latest".
        // We strip the "gemini-" prefix to keep the card subtitle compact.
        guard provider == .gemini else { return shortName }
        let modelShort = primaryModelId.hasPrefix("gemini-")
            ? String(primaryModelId.dropFirst("gemini-".count))
            : primaryModelId
        return "\(shortName) · \(modelShort)"
    }

    // Loading stored values and permissions
    private func loadTokens() {
        stravaAuthService.checkAuthStatus()
        checkNotificationStatus()
        refreshProfile()
        // C-02: read the user API key from the Keychain. Runs again on every
        // .onAppear so that a change in the AI provider subview is immediately
        // visible in the main SettingsView (connection indicator + last 4 chars).
        // Epic #53: the key of the active provider.
        apiKey = UserAPIKeyStore.read(for: AIProvider(rawValue: providerRaw) ?? .gemini)
        Task {
            await settingsProfileService.requestProfileReadAuthorization()
            let p = await settingsProfileService.fetchProfile()
            async let secsTask = settingsHKManager.fetchAverageWeeklyDurationSeconds()
            async let vo2Task  = settingsHKManager.fetchVO2Max()
            let (secs, vo2) = await (secsTask, vo2Task)
            await MainActor.run {
                physicalProfile  = p
                weeklyAvgMinutes = secs / 60
                vo2Max           = vo2
            }
        }
    }

    // Recalculate the local athletic profile based on SwiftData
    private func refreshProfile() {
        do {
            self.athleticProfile = try profileManager.calculateProfile(context: modelContext)
        } catch {
            AppLoggers.athleticProfileManager.error("Athletic profile calculation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // Triggers fetching historical workouts.
    // Epic #42 Story 42.1: HK + Strava run independently; the dedupe layer from
    // Epic #41 covers cross-source. `selectedDataSource` no longer determines
    // which source we fetch — only which one is labelled as "primary".
    private func syncHistoricalData() {
        guard !isSyncingHistory else { return }
        isSyncingHistory = true
        feedbackMessage = "Synchroniseren gestart..."

        Task {
            async let hk = runHealthKitHistoricalSync()
            async let strava = runStravaHistoricalSync()
            let (hkMessage, stravaMessage) = await (hk, strava)

            await MainActor.run {
                isSyncingHistory = false
                feedbackMessage = "\(hkMessage) · \(stravaMessage)"
                refreshProfile()
            }
        }
    }

    @MainActor
    private func runHealthKitHistoricalSync() async -> String {
        do {
            // Epic #38 Story 38.2: cache count for the Dashboard banner evaluator.
            let count = try await HealthKitSyncService().syncHistoricalWorkouts(to: modelContext)
            UserDefaults.standard.set(count, forKey: "vibecoach_lastHKWorkoutsCount")
            return "HealthKit (1 jaar) gesynchroniseerd — \(count) workouts"
        } catch {
            UserDefaults.standard.set(0, forKey: "vibecoach_lastHKWorkoutsCount")
            return "HealthKit-fout: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func runStravaHistoricalSync() async -> String {
        do {
            // SPRINT 6.1 & 7.4: fetch at most 12 months of Strava history.
            let activities = try await fitnessDataService.fetchHistoricalActivities(monthsBack: 12)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()
            var newRecordsCount = 0

            for activity in activities {
                let date = formatter.date(from: activity.start_date) ?? fallbackFormatter.date(from: activity.start_date) ?? Date()

                // SPRINT 12.4: basic TRIMP fallback during sync.
                let basicTRIMPFallback: Double? = {
                    if let hr = activity.average_heartrate, hr > 100 {
                        let durationMins = Double(activity.moving_time) / 60.0
                        let simulatedDeltaHR = (hr - 60.0) / (190.0 - 60.0)
                        return durationMins * simulatedDeltaHR * 0.64 * exp(1.92 * simulatedDeltaHR)
                    } else {
                        return (Double(activity.moving_time) / 60.0) * 1.5
                    }
                }()

                let record = ActivityRecord(
                    id: String(activity.id),
                    name: activity.name,
                    distance: activity.distance,
                    movingTime: activity.moving_time,
                    averageHeartrate: activity.average_heartrate,
                    sportCategory: SportCategory.from(rawString: activity.type),
                    startDate: date,
                    trimp: basicTRIMPFallback,
                    deviceWatts: activity.device_watts
                )
                // Epic #50: historical weather data via Open-Meteo for Strava-only
                // rides (Garmin/bike computer). Sequential — for 12 months ≈
                // 100 calls, ~10s extra on the "Sync historische data" button. Fault-
                // tolerant: API error = continue without weather.
                await HistoricalWeatherService.enrichRecord(record, from: activity, startDate: date)
                if let result = try? ActivityDeduplicator.smartInsert(record, into: modelContext),
                   result == .inserted || result == .replaced {
                    newRecordsCount += 1
                }
            }
            try? modelContext.save()
            return "Strava: \(newRecordsCount) nieuwe activiteiten"
        } catch FitnessDataError.missingToken {
            return "Strava niet gekoppeld"
        } catch {
            return "Strava-fout: \(error.localizedDescription)"
        }
    }

    // Check the current status of Push Notifications permission
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsEnabled = (settings.authorizationStatus == .authorized)
            }
        }
    }

    // Explicitly request permission from the user for local notifications.
    // The proactive engines (A & B) use only `UNUserNotificationCenter`
    // scheduling — there is no APNs receiver anymore since the Node.js backend disappeared.
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
                if granted {
                    self.feedbackMessage = "Notificaties succesvol ingeschakeld."
                } else if let error = error {
                    self.feedbackMessage = "Fout bij aanvragen notificaties: \(error.localizedDescription)"
                } else {
                    self.feedbackMessage = "Notificatie toestemming geweigerd. Zet dit aan in de iOS Instellingen app."
                }
            }
        }
    }

    // Function to connect Apple Health
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

    // Save entered values to the native Keychain
    private func saveTokens() {
        feedbackMessage = "Instellingen veilig opgeslagen"

        // Simulate a feedback animation, then dismiss (or optional)
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Versie \(Bundle.main.appVersion) (Build \(Bundle.main.buildNumber))")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.secondary).kerning(0.4)
                            .accessibilityIdentifier("SettingsVersionLabel")
                        Text("Instellingen")
                            .font(.largeTitle).fontWeight(.bold)
                    }
                    .padding(.horizontal)
                    .padding(.top, 56)
                    .padding(.bottom, 20)

                    // ── VERBINDINGEN
                    settingsSectionLabel("VERBINDINGEN")
                    HStack(spacing: 10) {
                        SettingsConnectionCard(
                            icon: "applewatch",
                            title: "HealthKit",
                            subtitle: healthKitConnectionSubtitle,
                            isConnected: isHealthKitLinked,
                            accentColor: themeManager.primaryAccentColor
                        )
                        SettingsConnectionCard(
                            icon: "figure.run",
                            title: "Strava",
                            subtitle: stravaConnectionSubtitle,
                            isConnected: stravaAuthService.isAuthenticated,
                            accentColor: themeManager.primaryAccentColor
                        )
                        SettingsConnectionCard(
                            icon: "sparkles",
                            title: "AI Coach",
                            subtitle: aiCoachConnectionSubtitle,
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
                                Text(userName.isEmpty ? String(localized: "Gebruiker") : userName)
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

                    // ── TRAININGSDREMPELS (Epic 44 Story 44.4)
                    settingsSectionLabel("TRAININGSDREMPELS")
                    settingsCard {
                        NavigationLink(destination: TrainingThresholdsSettingsView()) {
                            SettingsRowV2(
                                icon: "speedometer",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Persoonlijke zones",
                                subtitle: trainingThresholdsSubtitle,
                                hasChevron: true
                            )
                        }.buttonStyle(.plain)
                    }
                    Text("Max HR, rust HR, LTHR en FTP. De coach gebruikt deze waarden om jouw zones te berekenen — anders gebruikt hij populatie-gemiddelden.")
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
                        settingsDivider
                        SettingsRowV2(
                            icon: "lungs.fill",
                            iconColor: Color(red: 0.27, green: 0.55, blue: 0.91),
                            title: "VO₂max",
                            subtitle: "Geschatte conditiescore (Apple Watch)",
                            value: vo2Max.map { String(format: "%.0f ml/kg/min", $0) } ?? "--"
                        )
                        settingsDivider
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

                    // ── TAAL (Epic #37 story 37.5 / 37.1)
                    settingsSectionLabel("TAAL")
                    settingsCard {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Taal")
                                    .font(.subheadline)
                                    .padding(.leading, 14)
                                Spacer()
                                Picker("", selection: $appLanguageRaw) {
                                    ForEach(AppLanguage.selectableCases) { language in
                                        Text(language.displayName).tag(language.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding(.trailing, 14)
                                .accessibilityIdentifier("AppLanguagePicker")
                                .onChange(of: appLanguageRaw) { _, newValue in
                                    // Story 37.1: write the AppleLanguages override so the next launch
                                    // loads the chosen language's strings. iOS reads it once at launch,
                                    // so the visible UI-string switch needs a relaunch.
                                    (AppLanguage(rawValue: newValue) ?? .system).applyToBundleOverride()
                                    showLanguageRelaunchNote = true
                                }
                            }
                            .padding(.vertical, 10)

                            if showLanguageRelaunchNote {
                                Text("Herstart de app om de nieuwe taal volledig toe te passen.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 10)
                                    .accessibilityIdentifier("AppLanguageRelaunchNote")
                            }
                        }
                    }
                    .padding(.bottom, 24)

                    // ── BRON-VOORKEUR
                    settingsSectionLabel("BRON-VOORKEUR")
                    settingsCard {
                        Picker("", selection: $selectedDataSource) {
                            ForEach(DataSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(14)
                    }
                    Text("Beide bronnen syncen altijd. Je voorkeur bepaalt welke bron de coach als eerste aanspreekt voor de huidige status.")
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
                    }
                    Text("Sleutels worden lokaal versleuteld in de iOS Keychain opgeslagen.")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal).padding(.top, 6)
                    Spacer(minLength: 24)

                    // Epic 34 Sprint 2: notification toggles removed until the per-channel
                    // backend logic exists. System permissions are accessible below.
                    settingsSectionLabel("NOTIFICATIES")
                    settingsCard {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            SettingsRowV2(
                                icon: "bell.fill",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Systeempermissies",
                                subtitle: "Beheer notificaties in iOS Instellingen",
                                value: "Open",
                                hasChevron: true
                            )
                        }.buttonStyle(.plain)
                    }
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
                            // Clear a previous error so that a retry doesn't immediately
                            // show the old message.
                            stravaAuthService.authError = nil
                            if stravaAuthService.isAuthenticated {
                                stravaAuthService.logout(modelContext: modelContext)
                            } else {
                                stravaAuthService.authenticate()
                            }
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
                        if let stravaError = stravaAuthService.authError {
                            Text(stravaError)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.bottom, 24)

                    // ── Developer Tools (kept for debug)
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
                    }.padding(.bottom, 24)
                    #endif

                    if let msg = feedbackMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(msg.contains("mislukt") ? .red : .green)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    }

                    // Epic #51-H2: app version + build number at the bottom so the
                    // user can immediately see which version they're running when
                    // raising support questions. Non-interactive, not selectable.
                    Text(AppVersionInfo.displayString)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .accessibilityIdentifier("settings.versionLabel")

                    Spacer(minLength: 16)
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 4
            } action: { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSettingsScrolled = newValue
                }
            }
            .background(Color(.secondarySystemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .scrollEdgeMaterial(isActive: isSettingsScrolled)
            .onAppear { loadTokens() }
        }
    }

    // MARK: - V2.0 Helper views

    private var settingsDivider: some View {
        Divider().padding(.leading, 60)
    }

    @ViewBuilder
    // Epic #37 story 37.1: `LocalizedStringKey` (not `String`) so the literal section
    // headers resolve via `Localizable.xcstrings`. `Text(stringVariable)` is verbatim and
    // would NOT localize — this is the pattern for helper-wrapped UI strings.
    private func settingsSectionLabel(_ label: LocalizedStringKey) -> some View {
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
        .shadow(color: Color(.label).opacity(0.05), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
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

    // Epic #37 story 37.1c: rendered as a SettingsRowV2 value (verbatim), so localize here.
    private func physSexLabel(_ sex: BiologicalSex) -> String {
        switch sex {
        case .male:    return String(localized: "Man")
        case .female:  return String(localized: "Vrouw")
        case .other:   return String(localized: "Divers")
        case .unknown: return String(localized: "Onbekend")
        }
    }

    #if targetEnvironment(simulator)
    private func generateDummyData() {
        feedbackMessage = "Genereren van dummy data..."

        Task { @MainActor in
            let calendar = Calendar.current
            let now = Date()

            // 1. Add a dummy FitnessGoal (Marathon)
            let targetDate = calendar.date(byAdding: .day, value: 60, to: now)! // In 2 months
            let createdDate = calendar.date(byAdding: .day, value: -30, to: now)! // Started 1 month ago

            let goal = FitnessGoal(
                title: "Amsterdam Marathon (Test)",
                details: "Gegenereerd via simulator tools",
                targetDate: targetDate,
                createdAt: createdDate,
                sportCategory: .running,
                targetTRIMP: 6500.0
            )
            modelContext.insert(goal)

            // 2. Add 5 realistic activities in the past 45 days
            let workoutDates = [
                calendar.date(byAdding: .day, value: -35, to: now)!, // Time Travel: Before the createdAt!
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
                    distance: Double(durations[index]) * 2.5, // Rough estimate
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

// MARK: - V2.0 Components

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
        .shadow(color: Color(.label).opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

struct SettingsRowV2: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String?
    var value: String?
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
                // Epic #37 story 37.1c: `title`/`subtitle` are `String` (call sites pass literals
                // and computed values), so wrap them in `LocalizedStringKey` to resolve via the
                // String Catalog at runtime. Brand names not in the catalog fall back unchanged.
                // `value` stays verbatim — it's dynamic data (e.g. "76.0 kg").
                Text(LocalizedStringKey(title))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isWarning ? .orange : .primary)
                if let sub = subtitle {
                    Text(LocalizedStringKey(sub))
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

// MARK: - Epic 29 Sprint 2 & 3: Theme Picker Section

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

// MARK: - Epic 24 Sprint 2: Physiological Profile Section

/// Shows and manages the user's physiological profile.
/// Age and sex are read-only (come from the HealthKit Health app).
/// Weight and height are editable and are synchronised with HealthKit.
struct PhysicalProfileSection: View {
    // The manager is held as a property so healthStore is not deallocated immediately.
    private let hkManager = HealthKitManager()
    private var profileService: UserProfileService { UserProfileService(healthStore: hkManager.healthStore) }

    // Currently loaded profile
    @State private var profile: UserPhysicalProfile?

    // Editable fields (as String for TextField)
    @State private var weightInput: String = ""
    @State private var heightInput: String = ""

    // UI state
    @State private var isLoading     = true
    @State private var isSaving      = false
    @State private var saveMessage: String?
    /// .savedToHealthKit → green, .savedLocallyOnly → orange
    @State private var saveResult: UserProfileService.SaveResult?
    /// Timestamp of the last successful HealthKit refresh — for the sync indicator.
    @State private var lastRefreshed: Date?

    /// Coach notice on profile change — set once into the very next AI prompt.
    @AppStorage("vibecoach_profileUpdateNote") private var profileUpdateNote: String = ""

    // Detect whether the user changed anything compared to the loaded profile
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
                // Sync indicator — shows the timestamp of the last HealthKit refresh
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

                // Age — read-only via HealthKit
                profileRow(
                    icon: "person.circle",
                    iconColor: .blue,
                    label: "Leeftijd",
                    value: profile.map { "\($0.ageYears) " + String(localized: "jaar") } ?? String(localized: "Onbekend"),
                    isReadOnly: true
                )

                // Sex — read-only via HealthKit
                profileRow(
                    icon: "figure.stand",
                    iconColor: .indigo,
                    label: "Geslacht",
                    value: profile.map { sexLabel($0.sex) } ?? String(localized: "Onbekend"),
                    isReadOnly: true
                )

                // Weight — editable
                editableRow(
                    icon: "scalemass",
                    iconColor: .orange,
                    label: "Gewicht",
                    unit: "kg",
                    binding: $weightInput,
                    source: profile?.weightSource
                )

                // Height — editable
                editableRow(
                    icon: "ruler",
                    iconColor: .teal,
                    label: "Lengte",
                    unit: "cm",
                    binding: $heightInput,
                    source: profile?.heightSource
                )

                // Save button (only visible when there are changes)
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

                // Feedback after saving
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
        // onAppear guarantees a fresh HealthKit fetch every time the section becomes visible,
        // even when the SettingsView stays in memory (tabs). .task only runs on the first render
        // in static forms — hence the switch to onAppear.
        .onAppear { Task { await loadProfile() } }
    }

    // MARK: - Sub-views

    // Epic #37 story 37.1c: `label` is a `LocalizedStringKey` so the literal row labels
    // (Leeftijd/Geslacht/…) resolve via the String Catalog; `value` stays `String` — it's
    // dynamic data (e.g. "76.0 kg") that must render verbatim.
    /// Row for a read-only value (age, sex — come from HealthKit).
    private func profileRow(icon: String, iconColor: Color, label: LocalizedStringKey, value: String, isReadOnly: Bool) -> some View {
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

    /// Row for an editable value (weight, height).
    private func editableRow(
        icon: String,
        iconColor: Color,
        label: LocalizedStringKey,
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
            // Source badge
            if let src = source {
                sourceBadge(src)
            }
        }
    }

    /// Small badge indicating where the value comes from.
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

    // MARK: - Logic

    private func loadProfile() async {
        isLoading = true

        // First explicitly request read access for the profile types.
        // For users who connected HealthKit before Epic 24, dateOfBirth,
        // biologicalSex, bodyMass and height have never been requested — iOS only shows
        // the popup once we explicitly include them in requestAuthorization here.
        await profileService.requestProfileReadAuthorization()

        let loaded = await profileService.fetchProfile()

        // Detect whether the age has changed compared to the previous fetch.
        // If so, we write a one-time coach notice that gets injected into the
        // very next AI query (via vibecoach_profileUpdateNote).
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
            // Save each changed value and collect the results.
            // UserDefaults is always updated; HealthKit only with permission.
            var results: [UserProfileService.SaveResult] = []
            if newWeight != p.weightKg { results.append(await profileService.saveWeight(kg: newWeight)) }
            if newHeight != p.heightCm { results.append(await profileService.saveHeight(cm: newHeight)) }

            // Reload the profile so the source badges are updated
            await loadProfile()

            // Combine: if at least one value went to HealthKit → green, otherwise → orange
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

// MARK: - Epic 20: AI Coach Configuration (BYOK)

/// Settings screen where the user configures their own AI provider and API key.
/// The key is stored in AppStorage (locally on the device, not shared).
struct AIProviderSettingsView: View {
    @AppStorage("vibecoach_aiProvider")  private var providerRaw: String = AIProvider.gemini.rawValue
    // Epic #35: chosen primary & fallback Gemini models. Read by
    // `ChatViewModel.buildGenerativeModel`. Defaults match the values that were
    // hardcoded before Epic #35 so that an existing installation without an explicit
    // choice keeps using exactly the same models.
    @AppStorage(AIModelAppStorageKey.primary)
    private var primaryModelId: String = AIModelAppStorageKey.defaultPrimary
    @AppStorage(AIModelAppStorageKey.fallback)
    private var fallbackModelId: String = AIModelAppStorageKey.defaultFallback
    // C-02: the API key is read from / written to the Keychain
    // (see `UserAPIKeyStore`). `@State` holds the live binding with the SecureField;
    // `.onAppear` loads, `.onChange` persists.
    @State                               private var apiKey: String = ""
    @EnvironmentObject private var themeManager: ThemeManager

    /// Sprint 31.7: state machine for the minimal validation ping.
    /// The last tested key is tracked so we automatically reset the feedback block
    /// when the user changes their key.
    @State private var testState: APIKeyTestState = .idle
    @State private var testedKey: String = ""

    /// Epic #35 — model catalogue (via Cloudflare Worker) + fetch status.
    /// `hasAttemptedInitialLoad` distinguishes "never attempted" (show
    /// only a ProgressView) from "attempted, now live or fallback" (show
    /// pickers). This prevents the user from seeing a picker filled with
    /// the twelve-entry `builtInFallback` while the real list is still on its way.
    @State private var modelCatalog: AIModelCatalog = .builtInFallback
    @State private var isLoadingCatalog: Bool = false
    @State private var hasAttemptedInitialLoad: Bool = false
    @State private var catalogError: String?
    private let catalogService = AIModelCatalogService()

    /// Epic #53 (53.6): model choice for non-Gemini providers, from the static
    /// `AIModelCatalog.builtIn(for:)`. Gemini uses the dynamic Worker
    /// catalogue above; these two @State fields are loaded/persisted per provider
    /// via the provider-suffixed `AIModelAppStorageKey` keys.
    @State private var customPrimaryModel: String = ""
    @State private var customFallbackModel: String = ""

    /// Epic #54: live model catalogue per non-Gemini provider, fetched directly
    /// with the user key. Starts as the static `builtIn` list and is replaced
    /// once the live `/v1/models` fetch completes (falls back silently on error/empty key).
    @State private var providerModelCatalog: [AIModelDescriptor] = []
    @State private var isLoadingProviderModels: Bool = false
    @State private var providerModelsError: String?
    @State private var keyHelpURL: IdentifiableURL?
    private let providerModelListService = ProviderModelListService()

    /// Epic #62 story 62.2: persists the "key works" verdict per provider so it survives a
    /// provider switch and an app restart (stores only a SHA256 fingerprint of the key).
    private let testStatusStore = APIKeyTestStatusStore()

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: providerRaw) ?? .gemini
    }

    /// The feedback block is only valid for the key that was entered at the moment
    /// of the test. After typing, the verdict expires.
    private var showTestResult: Bool {
        testState != .idle && testedKey == apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            // Provider picker
            Section(header: Text("AI Provider")) {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            // API key input
            Section(
                header: Text("API Sleutel"),
                footer: VStack(alignment: .leading, spacing: 6) {
                    Text("VibeCoach gebruikt jouw eigen API-sleutel om de AI te activeren. De sleutel wordt uitsluitend lokaal op dit apparaat opgeslagen en nooit gedeeld met derden.")
                        .font(.caption)
                    if let url = selectedProvider.getKeyURL {
                        Button("Hoe kom ik aan een sleutel? →") {
                            keyHelpURL = IdentifiableURL(url: url)
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            ) {
                SecureField(selectedProvider.keyPlaceholder, text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("APIKeyField")

                // Epic #62 story 62.2: warn when the pasted key's prefix belongs to a different
                // provider (e.g. an sk-… OpenAI key under Gemini) — a common cause of "invalid key".
                if APIKeyInputValidator.isProviderMismatch(key: apiKey, selected: selectedProvider) {
                    Label("Deze sleutel lijkt van een andere provider. Controleer of je provider en sleutel bij elkaar horen.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("APIKeyProviderMismatchWarning")
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

            // Epic #35 — Model selection. Only for Gemini (dynamic Worker
            // catalogue). The provider-specific model pickers for OpenAI/Claude/
            // Mistral follow in Epic #53 story 53.6; until then those providers use
            // their curated default model (`AIModelCatalog.builtIn(for:)`).
            if selectedProvider == .gemini {
                Section(
                    header: Text("Gemini Modellen"),
                    footer: modelPickerFooter
                ) {
                    if !hasAttemptedInitialLoad {
                        // Initial load: show only a ProgressView so the
                        // user doesn't have to choose from the builtInFallback
                        // while the real list is still on its way.
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Modellen ophalen…")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .accessibilityIdentifier("GeminiModelsLoading")
                    } else {
                        Picker("Primair model", selection: $primaryModelId) {
                            ForEach(modelCatalog.models) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .accessibilityIdentifier("PrimaryGeminiModelPicker")

                        Picker("Fallback model", selection: $fallbackModelId) {
                            ForEach(modelCatalog.models) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .accessibilityIdentifier("FallbackGeminiModelPicker")
                    }
                }
            } else {
                // Epic #54: dynamic model picker per non-Gemini provider. The list
                // is fetched live with the user key (`loadProviderModels`); as long
                // as that runs — or on an error/empty key — it shows the static
                // `AIModelCatalog.builtIn(for:)` as a safety net so the picker is never empty.
                let models = providerModelCatalog.isEmpty
                    ? AIModelCatalog.builtIn(for: selectedProvider).models
                    : providerModelCatalog
                Section(header: Text("\(selectedProvider.displayName) modellen"),
                        footer: providerModelsFooter) {
                    Picker("Primair model", selection: $customPrimaryModel) {
                        ForEach(models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .accessibilityIdentifier("PrimaryProviderModelPicker")

                    Picker("Fallback model", selection: $customFallbackModel) {
                        ForEach(models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .accessibilityIdentifier("FallbackProviderModelPicker")
                }
            }

            // Sprint 31.7: Test ping — validates the key with a minimal
            // auth call against Gemini. The waterfall (primary → fallback on 503/429)
            // lives in `APIKeyValidator` so that a valid key isn't wrongly marked
            // as invalid during a Google overload.
            if !apiKey.isEmpty {
                Section(footer: testFeedbackFooter) {
                    Button {
                        testAPIKey()
                    } label: {
                        HStack {
                            if testState == .testing {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 2)
                                Text("Sleutel testen…")
                            } else {
                                Image(systemName: "bolt.circle")
                                Text("Test deze sleutel")
                            }
                            Spacer()
                        }
                    }
                    .disabled(testState == .testing)
                    .accessibilityIdentifier("TestAPIKeyButton")
                }
            }
        }
        .navigationTitle("AI Coach Configuratie")
        .sheet(item: $keyHelpURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        // C-02: Keychain-linked load/save around the SecureField.
        .onAppear {
            apiKey = UserAPIKeyStore.read(for: selectedProvider)
            // Epic #62 story 62.2: restore a previously persisted "key works" verdict.
            restoreTestVerdict()
            loadCustomModels()
            loadModelCatalog()
            loadProviderModels()
        }
        .onChange(of: apiKey) { _, newValue in
            // Epic #62 story 62.2: auto-trim a pasted key — stray spaces/newlines otherwise
            // cause a silent auth failure. Re-enter once with the clean value, then persist.
            let clean = APIKeyInputValidator.sanitize(newValue)
            if clean != newValue {
                apiKey = clean
                return
            }
            UserAPIKeyStore.write(clean, for: selectedProvider)
            // The verdict is only valid for the exact validated key — re-derive for the current one.
            restoreTestVerdict()
        }
        .onChange(of: providerRaw) { _, _ in
            // Epic #53: on a provider switch, show the key + model choice from the new
            // provider slot. Epic #62 story 62.2: restore the persisted verdict for that
            // provider's key instead of always resetting to idle.
            apiKey = UserAPIKeyStore.read(for: selectedProvider)
            loadCustomModels()
            restoreTestVerdict()
            // Epic #54: fetch the live model list of the new provider.
            loadProviderModels()
        }
        .onChange(of: testState) { _, newState in
            // Epic #54: a just-validated key unlocks the live model list —
            // refresh so the user immediately sees their real models.
            if newState == .valid { loadProviderModels() }
        }
        // Epic #53 (53.6): persist the non-Gemini model choice separated per provider.
        // Gemini runs via the @AppStorage bindings above, so we skip those.
        .onChange(of: customPrimaryModel) { _, newValue in
            guard !newValue.isEmpty, selectedProvider != .gemini else { return }
            UserDefaults.standard.set(newValue, forKey: AIModelAppStorageKey.primaryKey(for: selectedProvider))
        }
        .onChange(of: customFallbackModel) { _, newValue in
            guard !newValue.isEmpty, selectedProvider != .gemini else { return }
            UserDefaults.standard.set(newValue, forKey: AIModelAppStorageKey.fallbackKey(for: selectedProvider))
        }
    }

    /// Loads the stored (or default) model choice for the active non-Gemini
    /// provider into the picker bindings. For Gemini this is a no-op that is ignored
    /// by the `selectedProvider != .gemini` guard in the persist handlers.
    private func loadCustomModels() {
        customPrimaryModel = AIModelAppStorageKey.resolvedPrimary(for: selectedProvider)
        customFallbackModel = AIModelAppStorageKey.resolvedFallback(for: selectedProvider)
    }

    /// Epic #54: fetches the live model list of the active non-Gemini provider
    /// with the user key. Starts with the static list (picker never empty) and
    /// replaces it once the fetch succeeds. Resets the stored choice to a valid
    /// one if it no longer appears in the live list (e.g. deprecated).
    private func loadProviderModels() {
        guard selectedProvider != .gemini else { return }
        let provider = selectedProvider
        providerModelCatalog = AIModelCatalog.builtIn(for: provider).models

        let key = UserAPIKeyStore.read(for: provider)
        guard !key.isEmpty else { return }

        isLoadingProviderModels = true
        providerModelsError = nil
        Task {
            do {
                let models = try await providerModelListService.fetchModels(provider: provider, apiKey: key)
                await MainActor.run {
                    isLoadingProviderModels = false
                    // Provider may have switched during the fetch — ignore stale result.
                    guard selectedProvider == provider, !models.isEmpty else { return }
                    providerModelCatalog = models

                    let ids = Set(models.map(\.id))
                    let builtIn = AIModelCatalog.builtIn(for: provider)
                    if !ids.contains(customPrimaryModel) {
                        customPrimaryModel = ids.contains(builtIn.defaultPrimary) ? builtIn.defaultPrimary : (models.first?.id ?? customPrimaryModel)
                    }
                    if !ids.contains(customFallbackModel) {
                        customFallbackModel = ids.contains(builtIn.defaultFallback) ? builtIn.defaultFallback : (models.last?.id ?? customFallbackModel)
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingProviderModels = false
                    guard selectedProvider == provider else { return }
                    // Epic #54: show the failure reason instead of silently falling back, so a
                    // scope/auth problem (e.g. an OpenAI key without Models read access)
                    // is visible. The picker keeps showing the static fallback.
                    providerModelsError = Self.describeModelListError(error)
                }
            }
        }
    }

    /// Short, user-readable reason why the live model list could not load.
    private static func describeModelListError(_ error: Error) -> String {
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .authenticationFailed:
                return "je sleutel mag de modellijst niet ophalen (controleer of de key 'Models'-leesrecht heeft)"
            case .overloaded:
                return "provider tijdelijk overbelast"
            case .emptyResponse:
                return "geen chat-modellen herkend in de lijst"
            case .decodingFailed:
                return "onverwacht lijstformaat"
            case .http(let status, let message):
                return "HTTP \(status)\(message.map { ": \($0)" } ?? "")"
            case .contentBlocked:
                return "verzoek geblokkeerd"
            }
        }
        if let urlError = error as? URLError {
            return "netwerkprobleem (\(urlError.code.rawValue))"
        }
        return error.localizedDescription
    }

    @ViewBuilder
    private var providerModelsFooter: some View {
        if isLoadingProviderModels {
            Text("Modellen van \(selectedProvider.displayName) ophalen met je sleutel…")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Epic #54: without a key we can't query /v1/models → built-in list.
            Text("Voer je \(selectedProvider.displayName)-sleutel in (en test 'm) om je beschikbare modellen live te laden. Tot dan tonen we een ingebouwde lijst.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if let err = providerModelsError {
            Text("Live lijst niet beschikbaar — \(err). Ingebouwde lijst getoond.")
                .font(.caption)
                .foregroundColor(.orange)
        } else {
            Text("Live opgehaald met je sleutel. Lukt dat niet, dan tonen we een ingebouwde lijst.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Epic #35 — Model catalogue

    /// Fetches the model list from the Cloudflare Worker. Fails silently to the
    /// built-in fallback so the picker is never empty; any error does appear
    /// as a subtle message below the pickers.
    private func loadModelCatalog() {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        catalogError = nil

        Task {
            do {
                let catalog = try await catalogService.fetchCatalog()
                await MainActor.run {
                    self.modelCatalog = catalog
                    self.isLoadingCatalog = false
                    self.hasAttemptedInitialLoad = true
                    // If the stored choice is no longer in the catalogue
                    // — model is deprecated or a typo — silently fall back on the
                    // server-recommended default. Prevents the app from
                    // sending a non-existent model to Gemini.
                    let ids = Set(catalog.models.map(\.id))
                    if !ids.contains(self.primaryModelId) {
                        self.primaryModelId = catalog.defaultPrimary
                    }
                    if !ids.contains(self.fallbackModelId) {
                        self.fallbackModelId = catalog.defaultFallback
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingCatalog = false
                    self.hasAttemptedInitialLoad = true
                    self.catalogError = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private var modelPickerFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("De coach begint bij het primaire model. Bij overbelasting (503/429) schakelt hij automatisch over op het fallback-model.")
                .font(.caption)
            if let err = catalogError {
                Text("Kon live-lijst niet ophalen — fallback op ingebouwde modellen gebruikt. (\(err))")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Test feedback (inline in footer)

    @ViewBuilder
    private var testFeedbackFooter: some View {
        if showTestResult {
            switch testState {
            case .idle, .testing:
                EmptyView()
            case .valid:
                feedbackRow(icon: "checkmark.seal.fill",
                            color: .green,
                            title: "Sleutel werkt",
                            detail: "\(selectedProvider.displayName) heeft de sleutel geaccepteerd.")
            case .invalidKey:
                feedbackRow(icon: "xmark.octagon.fill",
                            color: .red,
                            title: "Sleutel ongeldig",
                            detail: "\(selectedProvider.displayName) weigert deze sleutel. Controleer of je hem volledig hebt geplakt.")
            case .rateLimited:
                feedbackRow(icon: "hourglass.circle.fill",
                            color: .orange,
                            title: "Model overbelast",
                            detail: "De servers van \(selectedProvider.displayName) zijn vol. Je sleutel kán geldig zijn — probeer zo nog eens.")
            case .network:
                feedbackRow(icon: "wifi.exclamationmark",
                            color: .orange,
                            title: "Geen verbinding",
                            detail: "Controleer je internetverbinding en probeer opnieuw.")
            case .unknown(let message):
                feedbackRow(icon: "exclamationmark.triangle.fill",
                            color: .orange,
                            title: "Onverwachte fout",
                            detail: message)
            }
        }
    }

    private func feedbackRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Test action

    func testAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        testState = .testing
        testedKey = trimmed
        let provider = selectedProvider

        Task {
            let result = await APIKeyValidator.validate(trimmed, provider: provider)
            await MainActor.run {
                switch result {
                case .valid:            testState = .valid
                case .invalidKey:       testState = .invalidKey
                case .rateLimited:      testState = .rateLimited
                case .network:          testState = .network
                case .unknown(let msg): testState = .unknown(msg)
                }
                // Epic #62 story 62.2: persist a positive verdict (survives provider switch +
                // app restart); clear it on a definitive rejection. Transient states
                // (rateLimited/network) leave any earlier verdict untouched.
                switch result {
                case .valid:      testStatusStore.markValidated(key: trimmed, for: provider)
                case .invalidKey: testStatusStore.clear(for: provider)
                default:          break
                }
            }
        }
    }

    /// Epic #62 story 62.2: shows a persisted "key works" verdict when the current key matches
    /// the last one validated for this provider; otherwise resets to idle (unless mid-test).
    private func restoreTestVerdict() {
        let clean = APIKeyInputValidator.sanitize(apiKey)
        if testStatusStore.isValidated(key: clean, for: selectedProvider) {
            testedKey = clean
            testState = .valid
        } else if testState != .testing {
            testState = .idle
        }
    }
}

/// Internal UI state for testing the key. Separate from
/// `APIKeyValidationResult` so we can also show `.idle` and `.testing`.
private enum APIKeyTestState: Equatable {
    case idle
    case testing
    case valid
    case invalidKey
    case rateLimited
    case network
    case unknown(String)
}

// MARK: - V2.0 Memory View

struct PreferencesListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("vibecoach_userName") private var userName: String = ""

    @Query(sort: \UserPreference.createdAt, order: .reverse) private var allPreferences: [UserPreference]

    @State private var selectedSegment: MemorySegment = .pins
    @State private var selectedFilter: MemoryTypeFilter = .all
    // Epic 34 Sprint 2: material overlay below the status bar once scrolled.
    @State private var isMemoryScrolled: Bool = false

    enum MemorySegment { case pins, history }
    enum MemoryTypeFilter: CaseIterable {
        case all, injury, preference, context
        // Epic #37: filter-chip labels resolved via the catalog (rendered as Text("\(label) · \(count)")).
        var label: String {
            switch self {
            case .all:        String(localized: "Alles")
            case .injury:     String(localized: "Blessure")
            case .preference: String(localized: "Voorkeur")
            case .context:    String(localized: "Context")
            }
        }
        var icon: String {
            switch self { case .all: "square.grid.2x2"; case .injury: "exclamationmark.triangle"; case .preference: "star"; case .context: "info.circle" }
        }
    }

    private var activePreferences: [UserPreference] {
        allPreferences.filter { $0.isActive && ($0.expirationDate == nil || $0.expirationDate! > Date()) }
    }

    private var historicPreferences: [UserPreference] {
        allPreferences.filter { !$0.isActive || ($0.expirationDate.map { $0 < Date() } ?? false) }
    }

    private var filteredPreferences: [UserPreference] {
        guard selectedFilter != .all else { return activePreferences }
        return activePreferences.filter { memoryType(for: $0.preferenceText) == selectedFilter }
    }

    private func countFor(_ filter: MemoryTypeFilter) -> Int {
        filter == .all ? activePreferences.count : activePreferences.filter { memoryType(for: $0.preferenceText) == filter }.count
    }

    private var userInitials: String {
        userName.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined().uppercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Header (Epic 34 Sprint 2: avatar icon without functionality removed)
                    VStack(alignment: .leading, spacing: 4) {
                        // Epic #37: counts pre-formatted as String → %@ key matches the catalog.
                        Text("WAT IK ONTHOU · \("\(activePreferences.count)") ACTIEVE · \("\(historicPreferences.count)") VERLOPEN")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.secondary).kerning(0.4)
                        Text("Geheugen")
                            .font(.largeTitle).fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 56)
                    .padding(.bottom, 20)

                    // ── Segmented Control
                    HStack(spacing: 0) {
                        ForEach([MemorySegment.pins, .history], id: \.self) { seg in
                            let isSelected = selectedSegment == seg
                            Button { withAnimation(.easeInOut(duration: 0.2)) { selectedSegment = seg } } label: {
                                Text(seg == .pins ? String(localized: "PINS & CONTEXT") : String(localized: "HISTORIE"))
                                    .font(.caption).fontWeight(.semibold).kerning(0.3)
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemBackground))
                                .frame(width: geo.size.width / 2)
                                .offset(x: selectedSegment == .pins ? 0 : geo.size.width / 2)
                                .animation(.easeInOut(duration: 0.2), value: selectedSegment)
                        }
                    )
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.bottom, 16)

                    if selectedSegment == .pins {
                        // ── Filter Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MemoryTypeFilter.allCases, id: \.self) { filter in
                                    let isSelected = selectedFilter == filter
                                    let count = countFor(filter)
                                    Button { withAnimation { selectedFilter = filter } } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: filter.icon).font(.caption2)
                                            Text("\(filter.label) · \(count)")
                                                .font(.caption).fontWeight(.semibold)
                                        }
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(isSelected ? themeManager.primaryAccentColor : Color(.systemBackground))
                                        .clipShape(Capsule())
                                        .shadow(color: Color(.label).opacity(isSelected ? 0 : 0.05), radius: 4, x: 0, y: 1)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 16)

                        // ── Preference Cards
                        if filteredPreferences.isEmpty {
                            ContentUnavailableView {
                                Label("Nog geen herinneringen", systemImage: "brain.head.profile")
                                    .foregroundStyle(themeManager.primaryAccentColor)
                            } description: {
                                Text("Vertel de coach in de chat over je blessures, voorkeuren of doelen.")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredPreferences) { pref in
                                    MemoryPreferenceCard(
                                        preference: pref,
                                        accentColor: themeManager.primaryAccentColor
                                    ) { delete(pref) }
                                }
                            }
                            .padding(.horizontal)
                        }

                    } else {
                        // ── History tab
                        if historicPreferences.isEmpty {
                            Text("Geen verlopen herinneringen.")
                                .font(.subheadline).foregroundColor(.secondary)
                                .padding()
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(historicPreferences) { pref in
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundColor(.secondary).font(.caption)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pref.preferenceText)
                                                .font(.subheadline).lineLimit(2)
                                            Text(pref.createdAt, formatter: memoryDateFormatter)
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemBackground))
                                    if pref.id != historicPreferences.last?.id {
                                        Divider().padding(.leading, 48)
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color(.label).opacity(0.05), radius: 6, x: 0, y: 2)
                            .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 4
            } action: { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isMemoryScrolled = newValue
                }
            }
            .background(Color(.secondarySystemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .scrollEdgeMaterial(isActive: isMemoryScrolled)
        }
    }

    private func delete(_ pref: UserPreference) {
        modelContext.delete(pref)
        try? modelContext.save()
    }
}

// MARK: - Memory type classification (keyword-based)

private enum MemoryType: Equatable { case injury, preference, context }

private func memoryType(for text: String) -> PreferencesListView.MemoryTypeFilter {
    let lower = text.lowercased()
    if lower.contains("blessure") || lower.contains("pijn") || lower.contains("last ") || lower.contains("stijf") || lower.contains("geblesseerd") || lower.contains("klacht") {
        return .injury
    } else if lower.contains("geen ") || lower.contains("nooit") || lower.contains("niet ") || lower.contains("voorkeur") || lower.contains("rustig") {
        return .preference
    }
    return .context
}

// Epic #37: badge labels resolved via the catalog (rendered verbatim on the pin cards).
private func memoryTypeStyle(for text: String) -> (label: String, color: Color, icon: String) {
    switch memoryType(for: text) {
    case .injury:     return (String(localized: "Blessure"), .orange, "exclamationmark.triangle")
    case .preference: return (String(localized: "Voorkeur"), Color(red: 0.3, green: 0.55, blue: 0.3), "star")
    case .context:    return (String(localized: "Context"), Color(red: 0.35, green: 0.55, blue: 0.85), "info.circle")
    case .all:        return (String(localized: "Context"), Color(red: 0.35, green: 0.55, blue: 0.85), "info.circle")
    }
}

// MARK: - MemoryPreferenceCard

struct MemoryPreferenceCard: View {
    let preference: UserPreference
    let accentColor: Color
    let onDelete: () -> Void

    private var typeStyle: (label: String, color: Color, icon: String) { memoryTypeStyle(for: preference.preferenceText) }
    private var isPinned: Bool { preference.expirationDate == nil }

    private var expirationBadgeLabel: String? {
        guard let exp = preference.expirationDate, exp > Date() else { return nil }
        let df = DateFormatter()
        df.locale = AppLanguage.currentLocale
        df.dateFormat = "d MMM"
        return "tot \(df.string(from: exp))"
    }

    private var createdLabel: String {
        let df = DateFormatter()
        df.locale = AppLanguage.currentLocale
        df.dateFormat = "d MMM yyyy"
        return df.string(from: preference.createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Badges + menu
            HStack(spacing: 6) {
                Label(typeStyle.label, systemImage: typeStyle.icon)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(typeStyle.color)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(typeStyle.color.opacity(0.12))
                    .clipShape(Capsule())

                if let expLabel = expirationBadgeLabel {
                    Label(expLabel, systemImage: "calendar")
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.orange.opacity(0.10))
                        .clipShape(Capsule())
                } else if isPinned {
                    Label("Vastgepind", systemImage: "star.fill")
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                Spacer()

                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Verwijder", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
            }

            // Main text
            Text(preference.preferenceText)
                .font(.headline)
                .foregroundColor(.primary)

            // Footer
            HStack {
                Text("Onthouden op \(createdLabel)")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

private let memoryDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = AppLanguage.currentLocale
    f.dateFormat = "d MMM yyyy"
    return f
}()

// MARK: - Bundle helpers

private extension Bundle {
    /// Marketing version from Info.plist (CFBundleShortVersionString).
    /// Fallback stays equal to the current V2.0 release.
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    }
    /// Build number from Info.plist (CFBundleVersion).
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
