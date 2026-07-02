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

    @AppStorage(AppStorageKeys.selectedDataSource) private var selectedDataSource: DataSource = .healthKit

    // Historical sync state
    @State private var isSyncingHistory: Bool = false
    @State private var athleticProfile: AthleticProfile?

    // V2.0 extra state
    @AppStorage(AppStorageKeys.userName)     private var userName: String = ""
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
    @AppStorage(AppStorageKeys.colorScheme)  private var colorSchemeRaw: String = "auto"
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
            UserDefaults.standard.set(count, forKey: AppStorageKeys.lastHKWorkoutsCount)
            return "HealthKit (1 jaar) gesynchroniseerd — \(count) workouts"
        } catch {
            UserDefaults.standard.set(0, forKey: AppStorageKeys.lastHKWorkoutsCount)
            return "HealthKit-fout: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func runStravaHistoricalSync() async -> String {
        do {
            // SPRINT 6.1 & 7.4: fetch at most 12 months of Strava history.
            let activities = try await fitnessDataService.fetchHistoricalActivities(monthsBack: 12)

            var newRecordsCount = 0

            for activity in activities {
                // Epic 65.1: use the cached ISO-8601 formatters (no per-activity allocation).
                let date = AppDateFormatters.iso8601WithFractionalSeconds.date(from: activity.start_date)
                    ?? AppDateFormatters.iso8601.date(from: activity.start_date)
                    ?? Date()

                // SPRINT 12.4: basic TRIMP fallback during sync (Epic 65.1: centralised).
                let basicTRIMPFallback: Double? = PhysiologicalCalculator.basicFallbackTRIMP(
                    durationSec: Double(activity.moving_time),
                    avgHR: activity.average_heartrate
                )

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

    // MARK: - Body

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
                    .padding(.bottom, 12)

                    // Epic #62 stories 62.3 + 62.5: one place to see permission + background-engine status.
                    settingsCard {
                        NavigationLink(destination: PermissionStatusView()) {
                            SettingsRowV2(
                                icon: "checklist",
                                iconColor: themeManager.primaryAccentColor,
                                title: "Toestemmingen & achtergrond",
                                subtitle: "Health, notificaties en de coach-engines",
                                hasChevron: true
                            )
                        }.buttonStyle(.plain)
                    }
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

    // MARK: - Helper views

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

// MARK: - Components

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
