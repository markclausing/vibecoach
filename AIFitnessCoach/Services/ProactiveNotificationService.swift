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

    /// Verwerkt een nieuw workout-signaal van Engine A:
    /// checkt of een doel nog op rood staat en stuurt dan een contextuele notificatie.
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

        let body = atRiskTitles.count == 1
            ? "Je loopt nog achter op '\(atRiskTitles[0])'. Open de coach voor een herstelplan."
            : "Je loopt nog achter op \(atRiskTitles.count) doelen. Open de coach voor een bijgestuurd plan."

        await sendNotification(
            title: "Workout geregistreerd 💪",
            body: body,
            identifier: "engine_a_\(Int(Date().timeIntervalSince1970))"
        )
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

        let daysText = Int(daysSinceWorkout) >= 3 ? "al \(Int(daysSinceWorkout)) dagen" : "2 dagen"

        await sendNotification(
            title: "Je doel loopt achter ⚠️",
            body: "'\(atRiskTitles[0])' heeft aandacht nodig. Je hebt \(daysText) niet getraind — open VibeCoach voor een bijgestuurd plan.",
            identifier: "engine_b_\(Int(Date().timeIntervalSince1970))"
        )
    }

    // MARK: - Gedeelde notificatielogica

    /// Verstuurt een lokale push notificatie met een 24-uurs cooldown tegen spam.
    private func sendNotification(title: String, body: String, identifier: String) async {
        // Controleer of de gebruiker notificaties heeft toegestaan
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            print("ℹ️ Notificaties niet toegestaan — overgeslagen")
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
}
