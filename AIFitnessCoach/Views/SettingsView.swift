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

    var body: some View {
        Form {
                // Epic 20: BYOK AI Configuratie — bovenaan voor directe vindbaarheid
                Section(header: Text("AI Coach")) {
                    NavigationLink(destination: AIProviderSettingsView()) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Coach Configuratie")
                                    .fontWeight(.medium)
                                Text(UserDefaults.standard.string(forKey: "vibecoach_userAPIKey")?.isEmpty == false
                                     ? "Sleutel geconfigureerd ✓"
                                     : "Geen sleutel ingesteld")
                                    .font(.caption)
                                    .foregroundColor(UserDefaults.standard.string(forKey: "vibecoach_userAPIKey")?.isEmpty == false ? .green : .orange)
                            }
                        }
                    }
                }

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

                // Epic 24 Sprint 2: Fysiologisch profiel — Two-Way Sync met HealthKit
                PhysicalProfileSection()

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

                #if targetEnvironment(simulator)
                Section(header: Text("Developer Tools (Simulator Only)")) {
                    Button("Genereer Test Data (Epic 12)") {
                        generateDummyData()
                    }
                    .foregroundColor(.purple)
                }
                #endif

                Section(
                    header: Text("Data Beheer"),
                    footer: Text("Verwijdert dubbele activiteiten met dezelfde ID die door een race-condition in de sync zijn ontstaan.").font(.caption)
                ) {
                    Button(action: {
                        removeDuplicateRecords()
                    }) {
                        HStack {
                            Image(systemName: "trash.slash")
                                .foregroundColor(.red)
                            Text("Verwijder Dubbele Activiteiten")
                                .foregroundColor(.red)
                        }
                    }
                }

                #if DEBUG
                Section(
                    header: Text("Developer Tools (Debug)"),
                    footer: Text("Simuleert exact de logica van Engine A (workout detectie) én Engine B (inactiviteitscheck). Reset de 24-uurs cooldown zodat de notificatie écht verstuurd wordt.").font(.caption)
                ) {
                    Button(action: {
                        feedbackMessage = "Engines worden afgevuurd..."
                        Task {
                            await ProactiveNotificationService.shared.debugTriggerEngines()
                            await MainActor.run {
                                feedbackMessage = "Klaar! Controleer je notificaties."
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.orange)
                            Text("Forceer Achtergrond Sync (Debug)")
                                .foregroundColor(.orange)
                        }
                    }

                    // Epic 14: Bereken Vibe Score en sla op in SwiftData (upsert voor vandaag)
                    Button(action: {
                        feedbackMessage = "Vibe Score berekenen..."
                        Task {
                            let hkManager = HealthKitManager()

                            // Haal de drie inputs parallel op
                            async let hrvTask = try? hkManager.fetchRecentHRV()
                            async let baselineTask = try? hkManager.fetchHRVBaseline(days: 7)
                            async let sleepTask = try? hkManager.fetchLastNightSleep()
                            let (hrv, baseline, sleep) = await (hrvTask, baselineTask, sleepTask)

                            await MainActor.run {
                                guard let sleepHours = sleep, let currentHRV = hrv, let hrvBaseline = baseline else {
                                    // Geef aan welke data ontbreekt voor duidelijke debugging
                                    var missing: [String] = []
                                    if sleep == nil { missing.append("Slaap") }
                                    if hrv == nil { missing.append("HRV") }
                                    if baseline == nil { missing.append("HRV-baseline") }
                                    feedbackMessage = "Geen data: \(missing.joined(separator: ", ")) ontbreekt."
                                    return
                                }

                                let score = ReadinessCalculator.calculate(
                                    sleepHours: sleepHours,
                                    hrv: currentHRV,
                                    hrvBaseline: hrvBaseline
                                )

                                // Upsert: zoek een bestaand record voor vandaag en overschrijf, anders nieuw aanmaken
                                let todayStart = Calendar.current.startOfDay(for: Date())
                                let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
                                let descriptor = FetchDescriptor<DailyReadiness>(
                                    predicate: #Predicate { $0.date >= todayStart && $0.date < tomorrowStart }
                                )
                                if let existing = try? modelContext.fetch(descriptor), let record = existing.first {
                                    // Record bestaat al voor vandaag — bijwerken
                                    record.sleepHours = sleepHours
                                    record.hrv = currentHRV
                                    record.readinessScore = score
                                } else {
                                    // Nieuw record aanmaken voor vandaag
                                    let record = DailyReadiness(
                                        date: Date(),
                                        sleepHours: sleepHours,
                                        hrv: currentHRV,
                                        readinessScore: score
                                    )
                                    modelContext.insert(record)
                                }
                                try? modelContext.save()

                                let hrs = Int(sleepHours)
                                let mins = Int((sleepHours - Double(hrs)) * 60)
                                let message = "Vibe Score: \(score)/100 (Slaap: \(hrs)u\(mins)m, HRV: \(String(format: "%.1f", currentHRV))ms)"
                                feedbackMessage = message
                                print("✅ [Epic 14] \(message)")
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "heart.text.square")
                                .foregroundColor(.purple)
                            Text("Bereken Vibe Score (Epic 14)")
                                .foregroundColor(.purple)
                        }
                    }
                }
                #endif
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
    @State private var isLoading   = true
    @State private var isSaving    = false
    @State private var saveMessage: String?
    /// .savedToHealthKit → groen, .savedLocallyOnly → oranje
    @State private var saveResult: UserProfileService.SaveResult?

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
        .task { await loadProfile() }
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
        let loaded = await profileService.fetchProfile()
        await MainActor.run {
            profile      = loaded
            weightInput  = String(format: "%.1f", loaded.weightKg)
            heightInput  = String(format: "%.0f", loaded.heightCm)
            isLoading    = false
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
                            .foregroundColor(.green)
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
