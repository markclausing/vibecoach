import Foundation
import HealthKit
import BackgroundTasks
import UserNotifications
import os

/// Sprint 13.2: Dual Engine notificatie-architectuur voor proactieve coaching.
///
/// Engine A (Action Trigger): Reageert op nieuwe workouts via HKObserverQuery +
/// enableBackgroundDelivery. iOS wekt de app zodra een workout wordt opgeslagen.
///
/// Engine B (Inaction Trigger): Dagelijkse stille achtergrondcheck via BGAppRefreshTask.
/// Stuurt een waarschuwing als de gebruiker 2+ dagen inactief is én een doel op rood staat.
final class ProactiveNotificationService {

    /// Unified logger — subsystem matcht de bundle-id, category beschrijft de service.
    /// Gebruik `.public` voor status-strings en `.private` voor PII (doeltitels,
    /// TRIMP-waardes per gebruiker) zodat sysdiagnose-logs in release-builds geen
    /// identificerende data lekken.
    private static let logger = Logger(subsystem: "com.markclausing.aifitnesscoach", category: "ProactiveNotificationService")

    static let shared = ProactiveNotificationService()

    private let healthStore = HKHealthStore()

    /// Unieke identifier voor de dagelijkse BGAppRefreshTask (moet ook in Info.plist staan).
    static let bgTaskIdentifier = "com.markclausing.aifitnesscoach.dailygoalcheck"

    // UserDefaults-sleutels voor het delen van state tussen foreground en achtergrond
    private let atRiskTitlesKey      = "vibecoach_atRiskGoalTitles"
    private let lastNotificationKey  = "vibecoach_lastProactiveNotificationDate"
    private let lastWorkoutDateKey   = "vibecoach_lastWorkoutDate"

    private init() {}

    // MARK: - Engine A: Action Trigger (HKObserverQuery + enableBackgroundDelivery)

    /// Registreert een HKObserverQuery voor workouts en schakelt background delivery in.
    /// iOS wekt de app op de achtergrond zodra een nieuwe workout in Apple Health verschijnt.
    ///
    /// Vereist entitlement: com.apple.developer.healthkit.background-delivery = true
    func setupEngineA() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let workoutType = HKObjectType.workoutType()

        // Observer query: vuurt bij elke nieuwe of gewijzigde workout
        let observerQuery = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                Self.logger.error("Engine A observer fout: \(error!.localizedDescription, privacy: .public)")
                completionHandler() // Altijd aanroepen — anders stopt background delivery
                return
            }

            Task {
                await self?.handleNewWorkoutDetected()
                completionHandler() // Verplicht signaal aan HealthKit dat we klaar zijn
            }
        }

        healthStore.execute(observerQuery)

        // Schakel achtergrondlevering in: iOS wekt de app bij elke nieuwe workout
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { success, error in
            if success {
                Self.logger.info("Engine A: HealthKit achtergrondlevering actief")
            } else if let error = error {
                Self.logger.error("Engine A: Achtergrondlevering mislukt — \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Verwerkt een nieuw workout-signaal van Engine A.
    /// Checkt de TRIMP van de zojuist voltooide workout en past de notificatietekst
    /// daarop aan: prijst flinke inspanning, neutraal bij lichte sessies.
    private func handleNewWorkoutDetected() async {
        // Sla de datum van de meest recente workout op (gebruikt door Engine B)
        UserDefaults.standard.set(Date(), forKey: lastWorkoutDateKey)

        // Wacht even zodat HealthKit de workout-data volledig kan opslaan
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconden

        let atRiskTitles = UserDefaults.standard.stringArray(forKey: atRiskTitlesKey) ?? []
        guard !atRiskTitles.isEmpty else {
            Self.logger.debug("Engine A: Geen doelen op rood — geen notificatie nodig")
            return
        }

        // Haal de TRIMP van de meest recente workout op om de toon te bepalen
        let recentTRIMP = await fetchMostRecentWorkoutTRIMP()
        // TRIMP is user-specifieke fysiologische data → private.
        Self.logger.debug("Engine A: Meest recente workout TRIMP = \(recentTRIMP.map { String(format: "%.0f", $0) } ?? "onbekend", privacy: .private)")

        let content = Self.composeEngineAContent(recentTRIMP: recentTRIMP, atRiskTitles: atRiskTitles)
        await sendNotification(
            title: content.title,
            body: content.body,
            identifier: "engine_a_\(Int(Date().timeIntervalSince1970))"
        )
    }

    /// Pure helper voor Engine A notificatie-tekst. Geëxtraheerd zodat
    /// alle string-paden in `ProactiveNotificationServiceTests` getest kunnen
    /// worden zonder HealthKit / UserDefaults te raken.
    static func composeEngineAContent(
        recentTRIMP: Double?,
        atRiskTitles: [String]
    ) -> (title: String, body: String) {
        if let trimp = recentTRIMP, trimp >= 50 {
            // Flinke workout (≥ 50 TRIMP) — eerst de inzet prijzen, dan pas de context geven
            let trimpInt = Int(trimp)
            let title = "Lekker getraind! 💪"
            let body: String
            if atRiskTitles.count == 1 {
                body = "\(trimpInt) TRIMP binnengehaald — goede stap richting '\(atRiskTitles[0])'. Je loopt nog iets achter, maar de coach heeft een vervolgstap klaar."
            } else {
                body = "\(trimpInt) TRIMP binnengehaald. Je loopt nog achter op \(atRiskTitles.count) doelen, maar je bent op de goede weg. Open de coach."
            }
            return (title, body)
        }

        if let trimp = recentTRIMP, trimp > 0 {
            // Lichte workout (< 50 TRIMP) — neutraal
            let trimpInt = Int(trimp)
            let title = "Workout geregistreerd (\(trimpInt) TRIMP)"
            let body = atRiskTitles.count == 1
                ? "Je loopt nog achter op '\(atRiskTitles[0])'. Overweeg een zwaardere sessie — de coach helpt je plannen."
                : "Je loopt achter op \(atRiskTitles.count) doelen. Open de coach voor een bijgestuurd plan."
            return (title, body)
        }

        // Geen TRIMP-data beschikbaar — neutrale fallback
        let title = "Workout geregistreerd"
        let body = atRiskTitles.count == 1
            ? "Je loopt nog achter op '\(atRiskTitles[0])'. Open de coach voor de volgende stap."
            : "Je loopt achter op \(atRiskTitles.count) doelen. Open de coach voor een bijgestuurd plan."
        return (title, body)
    }

    /// Haalt de TRIMP van de meest recente workout op uit HealthKit (max 6 uur geleden).
    /// Gebruikt de Banister-formule op basis van duur en gemiddelde hartslag.
    /// Geeft `nil` terug als er geen recente workout gevonden is of HealthKit niet beschikbaar is.
    private func fetchMostRecentWorkoutTRIMP() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        let workoutType = HKObjectType.workoutType()
        let sixHoursAgo = Calendar.current.date(byAdding: .hour, value: -6, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: sixHoursAgo, end: Date(), options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard error == nil, let workout = samples?.first as? HKWorkout else {
                    if let error = error {
                        Self.logger.error("Engine A: HealthKit TRIMP-query fout — \(error.localizedDescription, privacy: .public)")
                    }
                    continuation.resume(returning: nil)
                    return
                }

                let durationMins = workout.duration / 60.0
                guard durationMins > 1 else {
                    continuation.resume(returning: nil)
                    return
                }

                // Probeer gemiddelde hartslag op te halen uit de workout-statistieken
                let hrType = HKQuantityType(.heartRate)
                let avgHRQuantity = workout.statistics(for: hrType)?.averageQuantity()
                let avgHR = avgHRQuantity?.doubleValue(for: HKUnit(from: "count/min"))

                let trimp = Self.banisterTRIMP(
                    durationMinutes: durationMins,
                    averageHeartRate: avgHR
                )
                continuation.resume(returning: trimp)
            }
            self.healthStore.execute(query)
        }
    }

    /// Banister TRIMP-berekening op basis van duur en gemiddelde hartslag.
    /// Zonder HR-data: conservatieve Zone 2-schatting (1.5 TRIMP/min).
    /// Met HR > 60 bpm: full Banister formule met rusthartslag 60 en max 190.
    /// Pure functie — geëxtraheerd voor unit-test dekking van de math.
    static func banisterTRIMP(
        durationMinutes: Double,
        averageHeartRate: Double?,
        restingHR: Double = 60,
        maxHR: Double = 190
    ) -> Double {
        if let hr = averageHeartRate, hr > restingHR {
            let deltaHR = max(0.01, (hr - restingHR) / (maxHR - restingHR))
            return durationMinutes * deltaHR * 0.64 * exp(1.92 * deltaHR)
        }
        return durationMinutes * 1.5
    }

    // MARK: - Engine B: Inaction Trigger (BGAppRefreshTask)

    /// Plant de volgende dagelijkse achtergrondcheck via BGTaskScheduler.
    /// Roep aan bij app launch én aan het einde van elke BGTask run.
    func scheduleEngineB() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        // iOS kiest het exacte tijdstip — dit is het vroegste moment
        request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 20, to: Date())

        do {
            try BGTaskScheduler.shared.submit(request)
            Self.logger.info("Engine B: Dagelijkse achtergrondcheck ingepland")
        } catch {
            Self.logger.error("Engine B: Inplannen mislukt — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Verwerkt een BGAppRefreshTask van Engine B.
    /// Plant direct de volgende run en controleert inactiviteit + doelaflwijking.
    func handleEngineBTask(_ task: BGAppRefreshTask) {
        scheduleEngineB() // Herplan de volgende dagelijkse check

        let taskWork = Task {
            await checkInactionAndNotify()
            task.setTaskCompleted(success: true)
        }

        // iOS geeft een beperkte tijdswindow — annuleer netjes als de tijd op is
        task.expirationHandler = {
            taskWork.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Checkt of de gebruiker 2+ dagen inactief is geweest én een doel op rood staat.
    /// Stuurt een motivatienotificatie om de gebruiker weer in beweging te krijgen.
    private func checkInactionAndNotify() async {
        let atRiskTitles = UserDefaults.standard.stringArray(forKey: atRiskTitlesKey) ?? []
        let lastWorkout = UserDefaults.standard.object(forKey: lastWorkoutDateKey) as? Date

        guard let content = Self.composeEngineBContent(
            atRiskTitles: atRiskTitles,
            lastWorkoutDate: lastWorkout,
            now: Date()
        ) else {
            Self.logger.debug("Engine B: Geen actie nodig (geen risico-doelen of voldoende activiteit)")
            return
        }

        await sendNotification(
            title: content.title,
            body: content.body,
            identifier: "engine_b_\(Int(Date().timeIntervalSince1970))"
        )
    }

    /// Inactiviteits-drempel in dagen waarbij Engine B mag triggeren.
    static let engineBInactivityThresholdDays: Double = 2

    /// Bouwt de Engine B notificatie-content of geeft `nil` terug wanneer de
    /// engine niet zou moeten vuren. Pure functie — alle iOS-state komt via
    /// parameters, zodat unit-tests alle branches deterministisch kunnen
    /// driven.
    ///
    /// Beslislogica:
    ///  - Geen doelen op rood → `nil` (engine doet niets).
    ///  - `lastWorkoutDate == nil` → behandelen als 3 dagen geleden (worst-case
    ///    aanname: gebruiker heeft geen activiteit-historie en doelen staan
    ///    op rood, dus signaal sturen).
    ///  - daysSinceWorkout < drempel (2 dagen) → `nil`.
    ///  - daysSinceWorkout ≥ 4 → urgentere toon ("Tijd voor actie!").
    ///  - 2-3 dagen → vriendelijke toon ("Je doel heeft je nodig").
    static func composeEngineBContent(
        atRiskTitles: [String],
        lastWorkoutDate: Date?,
        now: Date = Date()
    ) -> (title: String, body: String)? {
        guard let primaryTitle = atRiskTitles.first else { return nil }

        let daysSinceWorkout: Double
        if let lastWorkout = lastWorkoutDate {
            daysSinceWorkout = now.timeIntervalSince(lastWorkout) / 86400
        } else {
            // Geen data beschikbaar = aanname van inactiviteit (3 dagen)
            daysSinceWorkout = 3
        }

        guard daysSinceWorkout >= engineBInactivityThresholdDays else { return nil }

        let daysInt = Int(daysSinceWorkout)
        let daysText = daysInt >= 3 ? "\(daysInt) dagen" : "2 dagen"

        if daysInt >= 4 {
            // Lang inactief — schop onder de kont
            return (
                title: "Tijd voor actie! ⚠️",
                body: "Je hebt \(daysText) niet getraind en '\(primaryTitle)' loopt gevaarlijk achter. Elke dag telt nu. Open de coach voor een herstelplan."
            )
        }

        // 2-3 dagen inactief — vriendelijk maar duidelijk
        return (
            title: "Je doel heeft je nodig 👟",
            body: "Je hebt \(daysText) niet getraind en '\(primaryTitle)' loopt achter. Zelfs een korte sessie helpt. Open de coach voor de volgende stap."
        )
    }

    // MARK: - Toestemming aanvragen

    /// Vraagt toestemming aan voor lokale notificaties.
    /// Roep aan bij app-start (didFinishLaunching of DashboardView.onAppear).
    /// Als de status al bepaald is (.authorized of .denied) doet deze functie niets.
    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                print("ℹ️ Notificatiestatus al bepaald: \(settings.authorizationStatus.rawValue)")
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if granted {
                    print("✅ Notificatietoestemming verleend door gebruiker")
                } else if let error = error {
                    print("⚠️ Notificatietoestemming mislukt: \(error.localizedDescription)")
                } else {
                    print("ℹ️ Notificatietoestemming geweigerd door gebruiker")
                }
            }
        }
    }

    // MARK: - Gedeelde notificatielogica

    /// Cooldown-window: maximaal één proactieve notificatie per `cooldownSeconds`.
    static let proactiveCooldownSeconds: TimeInterval = 86400

    /// Pure cooldown-check. Apart blootgesteld voor unit-tests — `sendNotification`
    /// roept hem aan op de huidige datum + de waarde uit `UserDefaults`.
    static func isCooldownActive(
        lastNotificationDate: Date?,
        now: Date = Date(),
        cooldownSeconds: TimeInterval = proactiveCooldownSeconds
    ) -> Bool {
        guard let last = lastNotificationDate else { return false }
        return now.timeIntervalSince(last) < cooldownSeconds
    }

    /// Verstuurt een lokale push notificatie met een 24-uurs cooldown tegen spam.
    private func sendNotification(title: String, body: String, identifier: String) async {
        // Controleer of de gebruiker notificaties heeft toegestaan
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            print("ℹ️ Notificaties niet toegestaan (status: \(settings.authorizationStatus.rawValue)) — overgeslagen")
            return
        }

        // Cooldown: maximaal 1 proactieve notificatie per 24 uur
        let lastDate = UserDefaults.standard.object(forKey: lastNotificationKey) as? Date
        if Self.isCooldownActive(lastNotificationDate: lastDate) {
            print("ℹ️ Proactieve notificatie overgeslagen: cooldown actief")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Herkenbaar type voor de tap-handler in AppDelegate
        content.userInfo = ["type": "goalRisk"]

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await UNUserNotificationCenter.current().add(request)
            UserDefaults.standard.set(Date(), forKey: lastNotificationKey)
            // Notificatie-titel kan doelnaam bevatten (PII) → private.
            Self.logger.info("Proactieve notificatie verstuurd: \(title, privacy: .private)")
        } catch {
            Self.logger.error("Notificatie versturen mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Cache bijwerken vanuit de UI

    /// Wordt aangeroepen door DashboardView (onAppear + na refresh) om de gecachede
    /// risicodata bij te werken zodat de achtergrond-engines actuele informatie hebben.
    func updateRiskCache(atRiskGoalTitles: [String]) {
        UserDefaults.standard.set(atRiskGoalTitles, forKey: atRiskTitlesKey)
        print("📦 Risicocache bijgewerkt: \(atRiskGoalTitles.isEmpty ? "geen doelen op rood" : atRiskGoalTitles.joined(separator: ", "))")
    }

    // MARK: - Debug Tools

    /// Debug trigger: simuleert exact de logica die Engine A én Engine B zouden afvuren.
    /// De 24-uurs cooldown wordt tijdelijk gereset zodat de notificatie écht verstuurd wordt.
    /// Als toestemming nog niet is gevraagd, vraagt deze functie dat alsnog vóór de engines draaien.
    ///
    /// M-06: de volledige body staat in een `#if DEBUG`-guard. In release-builds
    /// is dit een no-op. Dat voorkomt dat een onbedoelde call-site (bijv. een
    /// resterende debug-knop of een later toegevoegde test-hook) in productie
    /// engines kan afvuren en de notificatie-cooldown kan resetten.
    func debugTriggerEngines() async {
        #if DEBUG
        print("🔧 DEBUG: Handmatige trigger van beide proactieve engines")

        // Controleer de toestemmingsstatus — vraag alsnog als nog niet bepaald
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            print("🔧 DEBUG: Toestemming nog niet bepaald — aanvraag starten")
            // requestAuthorization is een throwing async functie
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            // Geef iOS even de tijd om de keuze te verwerken
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        guard settings.authorizationStatus != .denied else {
            print("⚠️ DEBUG: Notificaties zijn geweigerd in Systeeminstellingen — stop hier")
            return
        }

        // Reset de cooldown zodat de notificatie niet wordt onderdrukt
        UserDefaults.standard.removeObject(forKey: lastNotificationKey)
        // Engine A: stel in dat er net een workout was (om de 3-seconden sleep te omzeilen)
        UserDefaults.standard.set(Date().addingTimeInterval(-10), forKey: lastWorkoutDateKey)
        // Voer Engine A logica uit — de TRIMP wordt opgehaald uit de meest recente HealthKit-workout
        // (In de simulator is dat waarschijnlijk nil, dus de neutrale tekst verschijnt)
        await handleNewWorkoutDetected()
        // Reset cooldown opnieuw zodat Engine B ook een notificatie kan sturen
        UserDefaults.standard.removeObject(forKey: lastNotificationKey)
        // Voer Engine B logica uit (inactiviteitscheck)
        await checkInactionAndNotify()
        print("🔧 DEBUG: Beide engines afgevuurd")
        #endif
    }
}
