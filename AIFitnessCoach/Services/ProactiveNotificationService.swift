import Foundation
import HealthKit
import BackgroundTasks
import UserNotifications
import os

/// Sprint 13.2: Dual Engine notification architecture for proactive coaching.
///
/// Engine A (Action Trigger): Reacts to new workouts via HKObserverQuery +
/// enableBackgroundDelivery. iOS wakes the app as soon as a workout is saved.
///
/// Engine B (Inaction Trigger): Daily silent background check via BGAppRefreshTask.
/// Sends a warning if the user has been inactive 2+ days and a goal is in the red.
final class ProactiveNotificationService {

    /// The logger lives centrally in `AppLoggers.proactiveNotification`. Use `.public`
    /// for status strings and `.private` for PII (goal titles, per-user TRIMP values)
    /// so sysdiagnose logs in release builds don't leak anything identifying.

    static let shared = ProactiveNotificationService()

    private let healthStore = HKHealthStore()

    /// Unique identifier for the daily BGAppRefreshTask (must also be in Info.plist).
    static let bgTaskIdentifier = "com.markclausing.aifitnesscoach.dailygoalcheck"

    // UserDefaults keys for sharing state between foreground and background
    private let atRiskTitlesKey      = "vibecoach_atRiskGoalTitles"
    private let lastNotificationKey  = "vibecoach_lastProactiveNotificationDate"
    private let lastWorkoutDateKey   = "vibecoach_lastWorkoutDate"

    // Epic #62 story 62.5: persisted engine state so the Settings overview can show whether
    // each background engine actually armed (or why it didn't) instead of a silent failure.
    static let engineAActiveKey  = "vibecoach_engineABackgroundActive"
    static let engineAErrorKey   = "vibecoach_engineALastError"
    static let engineBScheduledKey = "vibecoach_engineBScheduled"
    static let engineBErrorKey   = "vibecoach_engineBLastError"

    /// Read-only accessors for the Settings overview (Epic #62 story 62.5).
    static var engineABackgroundActive: Bool { UserDefaults.standard.bool(forKey: engineAActiveKey) }
    static var engineALastError: String? { UserDefaults.standard.string(forKey: engineAErrorKey) }
    static var engineBScheduled: Bool { UserDefaults.standard.bool(forKey: engineBScheduledKey) }
    static var engineBLastError: String? { UserDefaults.standard.string(forKey: engineBErrorKey) }

    private init() {}

    // MARK: - Engine A: Action Trigger (HKObserverQuery + enableBackgroundDelivery)

    /// Registers an HKObserverQuery for workouts and enables background delivery.
    /// iOS wakes the app in the background as soon as a new workout appears in Apple Health.
    ///
    /// Requires entitlement: com.apple.developer.healthkit.background-delivery = true
    func setupEngineA() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let workoutType = HKObjectType.workoutType()

        // Observer query: fires on every new or changed workout
        let observerQuery = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                // swiftlint:disable:next force_unwrapping
                AppLoggers.proactiveNotification.error("Engine A observer fout: \(error!.localizedDescription, privacy: .public)") // guarded by `error == nil` above → non-nil here
                completionHandler() // Always call — otherwise background delivery stops
                return
            }

            Task {
                await self?.handleNewWorkoutDetected()
                completionHandler() // Mandatory signal to HealthKit that we're done
            }
        }

        healthStore.execute(observerQuery)

        // Enable background delivery: iOS wakes the app on every new workout
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { success, error in
            // Epic #62 story 62.5: persist the outcome so the Settings overview reflects the
            // real arming state instead of assuming Engine A runs just because we called setup.
            if success {
                UserDefaults.standard.set(true, forKey: Self.engineAActiveKey)
                UserDefaults.standard.removeObject(forKey: Self.engineAErrorKey)
                AppLoggers.proactiveNotification.info("Engine A: HealthKit achtergrondlevering actief")
            } else {
                UserDefaults.standard.set(false, forKey: Self.engineAActiveKey)
                if let error = error {
                    UserDefaults.standard.set(error.localizedDescription, forKey: Self.engineAErrorKey)
                    AppLoggers.proactiveNotification.error("Engine A: Achtergrondlevering mislukt — \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Handles a new workout signal from Engine A.
    /// Checks the TRIMP of the just-completed workout and adapts the notification
    /// text to it: praises substantial effort, neutral on light sessions.
    private func handleNewWorkoutDetected() async {
        // Store the date of the most recent workout (used by Engine B)
        UserDefaults.standard.set(Date(), forKey: lastWorkoutDateKey)

        // Wait a moment so HealthKit can fully store the workout data
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        let atRiskTitles = UserDefaults.standard.stringArray(forKey: atRiskTitlesKey) ?? []
        guard !atRiskTitles.isEmpty else {
            AppLoggers.proactiveNotification.debug("Engine A: Geen doelen op rood — geen notificatie nodig")
            return
        }

        // Fetch the TRIMP of the most recent workout to determine the tone
        let recentTRIMP = await fetchMostRecentWorkoutTRIMP()
        // TRIMP is user-specific physiological data → private.
        AppLoggers.proactiveNotification.debug("Engine A: Meest recente workout TRIMP = \(recentTRIMP.map { String(format: "%.0f", $0) } ?? "onbekend", privacy: .private)")

        let content = Self.composeEngineAContent(recentTRIMP: recentTRIMP, atRiskTitles: atRiskTitles)
        await sendNotification(
            title: content.title,
            body: content.body,
            identifier: "engine_a_\(Int(Date().timeIntervalSince1970))"
        )
    }

    /// Pure helper for Engine A notification text. Extracted so all string paths
    /// can be tested in `ProactiveNotificationServiceTests` without touching
    /// HealthKit / UserDefaults.
    static func composeEngineAContent(
        recentTRIMP: Double?,
        atRiskTitles: [String]
    ) -> (title: String, body: String) {
        // Epic #37 / i18n follow-up: these are delivered as notifications → localised. Numbers
        // are pre-formatted to String so each catalog key uses %@ (not %lld) — §13.
        if let trimp = recentTRIMP, trimp >= 50 {
            // Substantial workout (≥ 50 TRIMP) — praise the effort first, then give context
            let trimpStr = "\(Int(trimp))"
            let title = String(localized: "Lekker getraind! 💪")
            let body: String
            if atRiskTitles.count == 1 {
                let goal = atRiskTitles[0]
                body = String(localized: "\(trimpStr) TRIMP binnengehaald — goede stap richting '\(goal)'. Je loopt nog iets achter, maar de coach heeft een vervolgstap klaar.")
            } else {
                let countStr = "\(atRiskTitles.count)"
                body = String(localized: "\(trimpStr) TRIMP binnengehaald. Je loopt nog achter op \(countStr) doelen, maar je bent op de goede weg. Open de coach.")
            }
            return (title, body)
        }

        if let trimp = recentTRIMP, trimp > 0 {
            // Light workout (< 50 TRIMP) — neutral
            let trimpStr = "\(Int(trimp))"
            let title = String(localized: "Workout geregistreerd (\(trimpStr) TRIMP)")
            let body: String
            if atRiskTitles.count == 1 {
                let goal = atRiskTitles[0]
                body = String(localized: "Je loopt nog achter op '\(goal)'. Overweeg een zwaardere sessie — de coach helpt je plannen.")
            } else {
                let countStr = "\(atRiskTitles.count)"
                body = String(localized: "Je loopt achter op \(countStr) doelen. Open de coach voor een bijgestuurd plan.")
            }
            return (title, body)
        }

        // No TRIMP data available — neutral fallback
        let title = String(localized: "Workout geregistreerd")
        let body: String
        if atRiskTitles.count == 1 {
            let goal = atRiskTitles[0]
            body = String(localized: "Je loopt nog achter op '\(goal)'. Open de coach voor de volgende stap.")
        } else {
            let countStr = "\(atRiskTitles.count)"
            body = String(localized: "Je loopt achter op \(countStr) doelen. Open de coach voor een bijgestuurd plan.")
        }
        return (title, body)
    }

    /// Fetches the TRIMP of the most recent workout from HealthKit (max 6 hours ago).
    /// Uses the Banister formula based on duration and average heart rate.
    /// Returns `nil` if no recent workout is found or HealthKit isn't available.
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
                        AppLoggers.proactiveNotification.error("Engine A: HealthKit TRIMP-query fout — \(error.localizedDescription, privacy: .public)")
                    }
                    continuation.resume(returning: nil)
                    return
                }

                let durationMins = workout.duration / 60.0
                guard durationMins > 1 else {
                    continuation.resume(returning: nil)
                    return
                }

                // Try to fetch the average heart rate from the workout statistics
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

    /// Banister TRIMP calculation based on duration and average heart rate.
    /// Without HR data: conservative Zone 2 estimate (1.5 TRIMP/min).
    /// With HR > 60 bpm: full Banister formula with resting HR 60 and max 190.
    /// Pure function — extracted for unit-test coverage of the math.
    static func banisterTRIMP(
        durationMinutes: Double,
        averageHeartRate: Double?,
        restingHR: Double = 60,
        maxHR: Double = 190
    ) -> Double {
        if let hr = averageHeartRate, hr > restingHR {
            let deltaHR = max(0.01, (hr - restingHR) / (maxHR - restingHR))
            // Epic 65.1: routed through the centralised Banister kernel.
            return PhysiologicalCalculator.banisterTRIMP(durationMinutes: durationMinutes, normalizedDelta: deltaHR)
        }
        return durationMinutes * 1.5
    }

    // MARK: - Engine B: Inaction Trigger (BGAppRefreshTask)

    /// Schedules the next daily background check via BGTaskScheduler.
    /// Call at app launch and at the end of every BGTask run.
    func scheduleEngineB() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        // iOS picks the exact time — this is the earliest moment
        request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 20, to: Date())

        do {
            try BGTaskScheduler.shared.submit(request)
            // Epic #62 story 62.5: record success so Settings can show Engine B as scheduled.
            UserDefaults.standard.set(true, forKey: Self.engineBScheduledKey)
            UserDefaults.standard.removeObject(forKey: Self.engineBErrorKey)
            AppLoggers.proactiveNotification.info("Engine B: Dagelijkse achtergrondcheck ingepland")
        } catch {
            // Make the registration failure visible instead of swallowing it (L/§12).
            UserDefaults.standard.set(false, forKey: Self.engineBScheduledKey)
            UserDefaults.standard.set(error.localizedDescription, forKey: Self.engineBErrorKey)
            AppLoggers.proactiveNotification.error("Engine B: Inplannen mislukt — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Handles a BGAppRefreshTask from Engine B.
    /// Immediately schedules the next run and checks inactivity + goal deviation.
    func handleEngineBTask(_ task: BGAppRefreshTask) {
        scheduleEngineB() // Reschedule the next daily check

        let taskWork = Task {
            await checkInactionAndNotify()
            task.setTaskCompleted(success: true)
        }

        // iOS gives a limited time window — cancel cleanly if time runs out
        task.expirationHandler = {
            taskWork.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Checks whether the user has been inactive 2+ days and a goal is in the red.
    /// Sends a motivational notification to get the user moving again.
    private func checkInactionAndNotify() async {
        let atRiskTitles = UserDefaults.standard.stringArray(forKey: atRiskTitlesKey) ?? []
        let lastWorkout = UserDefaults.standard.object(forKey: lastWorkoutDateKey) as? Date

        guard let content = Self.composeEngineBContent(
            atRiskTitles: atRiskTitles,
            lastWorkoutDate: lastWorkout,
            now: Date()
        ) else {
            AppLoggers.proactiveNotification.debug("Engine B: Geen actie nodig (geen risico-doelen of voldoende activiteit)")
            return
        }

        await sendNotification(
            title: content.title,
            body: content.body,
            identifier: "engine_b_\(Int(Date().timeIntervalSince1970))"
        )
    }

    /// Inactivity threshold in days at which Engine B may trigger.
    static let engineBInactivityThresholdDays: Double = 2

    /// Builds the Engine B notification content or returns `nil` when the engine
    /// shouldn't fire. Pure function — all iOS state comes via parameters so
    /// unit tests can drive all branches deterministically.
    ///
    /// Decision logic:
    ///  - No goals in the red → `nil` (engine does nothing).
    ///  - `lastWorkoutDate == nil` → treat as 3 days ago (worst-case assumption:
    ///    the user has no activity history and goals are in the red, so send a signal).
    ///  - daysSinceWorkout < threshold (2 days) → `nil`.
    ///  - daysSinceWorkout ≥ 4 → more urgent tone ("Tijd voor actie!").
    ///  - 2-3 days → friendly tone ("Je doel heeft je nodig").
    static func composeEngineBContent(
        atRiskTitles: [String],
        lastWorkoutDate: Date?,
        now: Date = Date()
    ) -> (title: String, body: String)? {
        guard let primaryTitle = atRiskTitles.first else { return nil }

        let daysSinceWorkout: Double
        if let lastWorkout = lastWorkoutDate {
            // CLAUDE.md §3: calendar-based; avoids 1h drift around DST.
            daysSinceWorkout = Calendar.current.fractionalDays(from: lastWorkout, to: now)
        } else {
            // No data available = assumption of inactivity (3 days)
            daysSinceWorkout = 3
        }

        guard daysSinceWorkout >= engineBInactivityThresholdDays else { return nil }

        // Epic #37 / i18n follow-up: localised notification text (numbers pre-formatted → %@, §13).
        let daysInt = Int(daysSinceWorkout)
        let daysCount = daysInt >= 3 ? daysInt : 2
        let daysText = String(localized: "\("\(daysCount)") dagen")

        if daysInt >= 4 {
            // Long inactive — a kick in the pants
            return (
                title: String(localized: "Tijd voor actie! ⚠️"),
                body: String(localized: "Je hebt \(daysText) niet getraind en '\(primaryTitle)' loopt gevaarlijk achter. Elke dag telt nu. Open de coach voor een herstelplan.")
            )
        }

        // 2-3 days inactive — friendly but clear
        return (
            title: String(localized: "Je doel heeft je nodig 👟"),
            body: String(localized: "Je hebt \(daysText) niet getraind en '\(primaryTitle)' loopt achter. Zelfs een korte sessie helpt. Open de coach voor de volgende stap.")
        )
    }

    // MARK: - Requesting permission

    /// Requests permission for local notifications.
    /// Call at app start (didFinishLaunching or DashboardView.onAppear).
    /// If the status is already determined (.authorized or .denied) this function does nothing.
    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                AppLoggers.proactiveNotification.info("Notificatiestatus al bepaald: \(settings.authorizationStatus.rawValue, privacy: .public)")
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if granted {
                    AppLoggers.proactiveNotification.info("Notificatietoestemming verleend door gebruiker")
                } else if let error = error {
                    AppLoggers.proactiveNotification.error("Notificatietoestemming mislukt: \(error.localizedDescription, privacy: .public)")
                } else {
                    AppLoggers.proactiveNotification.info("Notificatietoestemming geweigerd door gebruiker")
                }
            }
        }
    }

    // MARK: - Shared notification logic

    /// Cooldown window: at most one proactive notification per `cooldownSeconds`.
    static let proactiveCooldownSeconds: TimeInterval = 86400

    /// Pure cooldown check. Exposed separately for unit tests — `sendNotification`
    /// calls it with the current date + the value from `UserDefaults`.
    static func isCooldownActive(
        lastNotificationDate: Date?,
        now: Date = Date(),
        cooldownSeconds: TimeInterval = proactiveCooldownSeconds
    ) -> Bool {
        guard let last = lastNotificationDate else { return false }
        return now.timeIntervalSince(last) < cooldownSeconds
    }

    /// Sends a local push notification with a 24-hour cooldown against spam.
    private func sendNotification(title: String, body: String, identifier: String) async {
        // Check whether the user has allowed notifications
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            AppLoggers.proactiveNotification.info("Notificaties niet toegestaan (status: \(settings.authorizationStatus.rawValue, privacy: .public)) — overgeslagen")
            return
        }

        // Cooldown: at most 1 proactive notification per 24 hours
        let lastDate = UserDefaults.standard.object(forKey: lastNotificationKey) as? Date
        if Self.isCooldownActive(lastNotificationDate: lastDate) {
            AppLoggers.proactiveNotification.debug("Proactieve notificatie overgeslagen: cooldown actief")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Recognizable type for the tap handler in AppDelegate
        content.userInfo = ["type": "goalRisk"]

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await UNUserNotificationCenter.current().add(request)
            UserDefaults.standard.set(Date(), forKey: lastNotificationKey)
            // Notification title can contain a goal name (PII) → private.
            AppLoggers.proactiveNotification.info("Proactieve notificatie verstuurd: \(title, privacy: .private)")
        } catch {
            AppLoggers.proactiveNotification.error("Notificatie versturen mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Updating the cache from the UI

    /// Called by DashboardView (onAppear + after refresh) to update the cached
    /// risk data so the background engines have current information.
    func updateRiskCache(atRiskGoalTitles: [String]) {
        UserDefaults.standard.set(atRiskGoalTitles, forKey: atRiskTitlesKey)
        // Goal titles are user content (PII).
        AppLoggers.proactiveNotification.debug("Risicocache bijgewerkt: \(atRiskGoalTitles.isEmpty ? "geen doelen op rood" : atRiskGoalTitles.joined(separator: ", "), privacy: .private)")
    }

    // MARK: - Debug Tools

    /// Debug trigger: simulates exactly the logic that Engine A and Engine B would fire.
    /// The 24-hour cooldown is temporarily reset so the notification is actually sent.
    /// If permission hasn't been requested yet, this function requests it before the engines run.
    ///
    /// M-06: the full body is inside an `#if DEBUG` guard. In release builds this is
    /// a no-op. That prevents an unintended call site (e.g. a leftover debug button
    /// or a later-added test hook) from firing engines in production and resetting
    /// the notification cooldown.
    func debugTriggerEngines() async {
        #if DEBUG
        AppLoggers.proactiveNotification.debug("DEBUG: Handmatige trigger van beide proactieve engines")

        // Check the permission status — request if not yet determined
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            AppLoggers.proactiveNotification.debug("DEBUG: Toestemming nog niet bepaald — aanvraag starten")
            // requestAuthorization is a throwing async function
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            // Give iOS a moment to process the choice
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        guard settings.authorizationStatus != .denied else {
            AppLoggers.proactiveNotification.debug("DEBUG: Notificaties zijn geweigerd in Systeeminstellingen — stop hier")
            return
        }

        // Reset the cooldown so the notification isn't suppressed
        UserDefaults.standard.removeObject(forKey: lastNotificationKey)
        // Engine A: set that there was just a workout (to bypass the 3-second sleep)
        UserDefaults.standard.set(Date().addingTimeInterval(-10), forKey: lastWorkoutDateKey)
        // Run Engine A logic — the TRIMP is fetched from the most recent HealthKit workout
        // (In the simulator that's likely nil, so the neutral text appears)
        await handleNewWorkoutDetected()
        // Reset the cooldown again so Engine B can also send a notification
        UserDefaults.standard.removeObject(forKey: lastNotificationKey)
        // Run Engine B logic (inactivity check)
        await checkInactionAndNotify()
        AppLoggers.proactiveNotification.debug("DEBUG: Beide engines afgevuurd")
        #endif
    }
}
