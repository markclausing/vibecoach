import Foundation
import HealthKit
import BackgroundTasks
import UserNotifications

/// Sprint 13.2: Dual Engine notificatie-architectuur voor proactieve coaching.
///
/// Engine A (Action Trigger): Reageert op nieuwe workouts via HKObserverQuery +
/// enableBackgroundDelivery. iOS wekt de app zodra een workout wordt opgeslagen.
///
/// Engine B (Inaction Trigger): Dagelijkse stille achtergrondcheck via BGAppRefreshTask.
/// Stuurt een waarschuwing als de gebruiker 2+ dagen inactief is én een doel op rood staat.
final class ProactiveNotificationService {

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
                print("⚠️ Engine A observer fout: \(error!.localizedDescription)")
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
                print("✅ Engine A: HealthKit achtergrondlevering actief")
            } else if let error = error {
                print("⚠️ Engine A: Achtergrondlevering mislukt — \(error.localizedDescription)")
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
            print("✅ Engine A: Geen doelen op rood — geen notificatie nodig")
            return
        }

        // Haal de TRIMP van de meest recente workout op om de toon te bepalen
        let recentTRIMP = await fetchMostRecentWorkoutTRIMP()
        print("ℹ️ Engine A: Meest recente workout TRIMP = \(recentTRIMP.map { String(format: "%.0f", $0) } ?? "onbekend")")

        let title: String
        let body: String

        if let trimp = recentTRIMP, trimp >= 50 {
            // Flinke workout (≥ 50 TRIMP) — eerst de inzet prijzen, dan pas de context geven
            let trimpInt = Int(trimp)
            title = "Lekker getraind! 💪"
            if atRiskTitles.count == 1 {
                body = "\(trimpInt) TRIMP binnengehaald — goede stap richting '\(atRiskTitles[0])'. Je loopt nog iets achter, maar de coach heeft een vervolgstap klaar."
            } else {
                body = "\(trimpInt) TRIMP binnengehaald. Je loopt nog achter op \(atRiskTitles.count) doelen, maar je bent op de goede weg. Open de coach."
            }
        } else if let trimp = recentTRIMP, trimp > 0 {
            // Lichte workout (< 50 TRIMP) — neutraal
            let trimpInt = Int(trimp)
            title = "Workout geregistreerd (\(trimpInt) TRIMP)"
            body = atRiskTitles.count == 1
                ? "Je loopt nog achter op '\(atRiskTitles[0])'. Overweeg een zwaardere sessie — de coach helpt je plannen."
                : "Je loopt achter op \(atRiskTitles.count) doelen. Open de coach voor een bijgestuurd plan."
        } else {
            // Geen TRIMP-data beschikbaar — neutrale fallback
            title = "Workout geregistreerd"
            body = atRiskTitles.count == 1
                ? "Je loopt nog achter op '\(atRiskTitles[0])'. Open de coach voor de volgende stap."
                : "Je loopt achter op \(atRiskTitles.count) doelen. Open de coach voor een bijgestuurd plan."
        }

        await sendNotification(
            title: title,
            body: body,
            identifier: "engine_a_\(Int(Date().timeIntervalSince1970))"
        )
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
                        print("⚠️ Engine A: HealthKit TRIMP-query fout — \(error.localizedDescription)")
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

                let trimp: Double
                if let hr = avgHR, hr > 60 {
                    // Banister TRIMP berekening
                    let deltaHR = max(0.01, (hr - 60.0) / (190.0 - 60.0))
                    trimp = durationMins * deltaHR * 0.64 * exp(1.92 * deltaHR)
                } else {
                    // Geen HR-data: conservatieve schatting op basis van duur (Zone 2 aanname)
                    trimp = durationMins * 1.5
                }

                continuation.resume(returning: trimp)
            }
            self.healthStore.execute(query)
        }
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
            print("✅ Engine B: Dagelijkse achtergrondcheck ingepland")
        } catch {
            print("⚠️ Engine B: Inplannen mislukt — \(error.localizedDescription)")
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
        guard !atRiskTitles.isEmpty else {
            print("✅ Engine B: Geen doelen op rood — geen actie nodig")
            return
        }

        // Bereken dagen zonder workout
        let daysSinceWorkout: Double
        if let lastWorkout = UserDefaults.standard.object(forKey: lastWorkoutDateKey) as? Date {
            daysSinceWorkout = Date().timeIntervalSince(lastWorkout) / 86400
        } else {
            daysSinceWorkout = 3 // Geen data beschikbaar = aanname van inactiviteit
        }

        guard daysSinceWorkout >= 2 else {
            print("ℹ️ Engine B: Laatste workout \(String(format: "%.1f", daysSinceWorkout)) dagen geleden — geen actie nodig")
            return
        }

        let daysInt = Int(daysSinceWorkout)
        let daysText = daysInt >= 3 ? "\(daysInt) dagen" : "2 dagen"

        // Engine B gebruikt een directere, dringendere toon — de gebruiker zit stil terwijl een doel op rood staat
        let title: String
        let body: String

        if daysInt >= 4 {
            // Lang inactief — schop onder de kont
            title = "Tijd voor actie! ⚠️"
            body = "Je hebt \(daysText) niet getraind en '\(atRiskTitles[0])' loopt gevaarlijk achter. Elke dag telt nu. Open de coach voor een herstelplan."
        } else {
            // 2-3 dagen inactief — vriendelijk maar duidelijk
            title = "Je doel heeft je nodig 👟"
            body = "Je hebt \(daysText) niet getraind en '\(atRiskTitles[0])' loopt achter. Zelfs een korte sessie helpt. Open de coach voor de volgende stap."
        }

        await sendNotification(
            title: title,
            body: body,
            identifier: "engine_b_\(Int(Date().timeIntervalSince1970))"
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

    /// Verstuurt een lokale push notificatie met een 24-uurs cooldown tegen spam.
    private func sendNotification(title: String, body: String, identifier: String) async {
        // Controleer of de gebruiker notificaties heeft toegestaan
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            print("ℹ️ Notificaties niet toegestaan (status: \(settings.authorizationStatus.rawValue)) — overgeslagen")
            return
        }

        // Cooldown: maximaal 1 proactieve notificatie per 24 uur
        if let lastDate = UserDefaults.standard.object(forKey: lastNotificationKey) as? Date,
           Date().timeIntervalSince(lastDate) < 86400 {
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
            print("🔔 Proactieve notificatie verstuurd: \(title)")
        } catch {
            print("⚠️ Notificatie versturen mislukt: \(error.localizedDescription)")
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
