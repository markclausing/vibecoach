import Foundation
import HealthKit

/// Beheert de Apple HealthKit integratie en permissies
final class HealthKitManager: @unchecked Sendable {

    /// Epic #31 Sprint 31.2: Gedeelde singleton zodat de onboarding-flow en
    /// achtergrond-services dezelfde instantie delen. Bestaande call-sites die
    /// `HealthKitManager()` gebruiken blijven werken (de init is nog beschikbaar).
    static let shared = HealthKitManager()

    // Lazy: HKHealthStore wordt pas aangemaakt bij het eerste echte gebruik,
    // niet al bij app-start. Dit verkort de opstarttijd significant.
    lazy var healthStore: HKHealthStore = HKHealthStore()

    /// Epic #31 Sprint 31.2 + Epic #38 Story 38.1: Permissie-aanvraag voor de
    /// onboarding-flow. Vraagt nu de **complete** set HK-types die de coach
    /// gebruikt (zie `HealthKitPermissionTypes.readTypes`) zodat een gebruiker
    /// niet per ongeluk een sub-set vergeet — iOS toont één toestemmings-sheet
    /// met álle categorieën. Voor 38.1 vóór deze wijziging vroeg onboarding
    /// alleen 4 types; de rest werd pas later via `requestAuthorization`
    /// achterhaald, wat tot stille fails leidde wanneer iOS na een reinstall
    /// de toestemmingen gedeeltelijk had gereset.
    ///
    /// - Returns: `true` als de HealthKit-dialog succesvol is gepresenteerd én
    ///   iOS een antwoord heeft geregistreerd. Let op: dit zegt niets over per-type
    ///   toestemming — HealthKit onthult lees-rechten niet.
    /// - Throws: `FitnessDataError.networkError` wanneer HealthKit niet beschikbaar
    ///   is op het apparaat.
    @discardableResult
    func requestOnboardingPermissions() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw FitnessDataError.networkError("HealthKit is niet beschikbaar op dit apparaat.")
        }

        // Epic #38 Story 38.1: complete set in één toestemmings-sheet (single
        // source of truth in `HealthKitPermissionTypes.readTypes`).
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: HealthKitPermissionTypes.writeTypes,
                                             read: HealthKitPermissionTypes.readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    /// Epic #38 Story 38.1: foreground-return-retrigger. Vraagt toestemming
    /// alleen voor de **critical** types waarvan de status `.notDetermined` is.
    /// Bestaande gebruikers met `.sharingAuthorized`/`.sharingDenied` zien geen
    /// onverwachte prompt — iOS toont alleen een dialog wanneer er écht iets
    /// te beslissen valt. Lege set → no-op (geen prompt, geen exception).
    @discardableResult
    func requestPermissionsForCriticalNotDetermined() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let notDetermined = HealthKitPermissionTypes.criticalNotDetermined(in: healthStore)
        guard !notDetermined.isEmpty else { return true }

        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: nil, read: notDetermined) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    /// Vraagt toestemming aan de gebruiker om benodigde gezondheidsdata te lezen.
    /// Epic #38 Story 38.1: types komen nu uit `HealthKitPermissionTypes` zodat
    /// onboarding en deze "expand later"-call dezelfde set vragen — geen drift
    /// meer tussen "wat we vragen" en "wat we checken op `.notDetermined`".
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, FitnessDataError.networkError("HealthKit is niet beschikbaar op dit apparaat."))
            return
        }

        healthStore.requestAuthorization(toShare: HealthKitPermissionTypes.writeTypes,
                                         read: HealthKitPermissionTypes.readTypes) { success, error in
            completion(success, error)
        }
    }

    /// Berekent het gemiddeld wekelijks trainingsvolume (in seconden) direct vanuit HealthKit.
    /// Vraagt geen SwiftData aan — altijd actuele data.
    func fetchAverageWeeklyDurationSeconds(weeks: Int = 4) async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let now = Date()
        guard let startDate = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: now) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let workouts = samples as? [HKWorkout] ?? []
                let totalSeconds = Int(workouts.reduce(0.0) { $0 + $1.duration })
                continuation.resume(returning: totalSeconds / max(1, weeks))
            }
            healthStore.execute(query)
        }
    }

    /// Haalt de meest recente workout op uit HealthKit (ongeacht het type)
    /// Inclusief de duur, hartslagstatistieken en ruwe hartslagsamples.
    func fetchLatestWorkoutDetails() async throws -> WorkoutDetails? {
        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!

        // Geen specifiek predicaat meer, we willen de laatste workout van willekeurig welk type
        let predicate: NSPredicate? = nil

        // Sorteer op einddatum om daadwerkelijk de laatst afrondde activiteit te pakken
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
                guard let self = self else {
                    continuation.resume(throwing: FitnessDataError.networkError("Manager deallocated"))
                    return
                }

                if let error = error {
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HealthKit workout: \(error.localizedDescription)"))
                    return
                }

                guard let workout = samples?.first as? HKWorkout else {
                    continuation.resume(returning: nil)
                    return
                }

                Task {
                    do {
                        // Haal de ruwe hartslagsamples op voor deze workout
                        let hrSamples = try await self.fetchHeartRateSamples(for: workout, quantityType: heartRateType)
                        let heartRateData = hrSamples.map { HeartRateSample(timestamp: $0.startDate, bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }

                        // Bereken gem en max uit de ruwe samples
                        let avgHR = heartRateData.isEmpty ? 0 : heartRateData.reduce(0) { $0 + $1.bpm } / Double(heartRateData.count)
                        let maxHR = heartRateData.max(by: { $0.bpm < $1.bpm })?.bpm ?? 0

                        // Haal laatste rusthartslag op
                        let restingHR = try await self.fetchLatestRestingHeartRate(quantityType: restingHeartRateType)

                        let sport = SportCategory.from(hkType: workout.workoutActivityType.rawValue)
                        let workoutName = sport.workoutName.prefix(1).uppercased() + sport.workoutName.dropFirst()
                        let details = WorkoutDetails(
                            name: String(workoutName),
                            startDate: workout.startDate,
                            duration: workout.duration,
                            averageHeartRate: avgHR,
                            maxHeartRate: maxHR,
                            restingHeartRate: restingHR,
                            heartRateSamples: heartRateData
                        )
                        continuation.resume(returning: details)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            healthStore.execute(query)
        }
    }

    /// Haalt workouts op van de afgelopen specifieke hoeveelheid dagen
    func fetchRecentWorkouts(days: Int) async throws -> [WorkoutDetails] {
        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!

        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
                guard let self = self else {
                    continuation.resume(throwing: FitnessDataError.networkError("Manager deallocated"))
                    return
                }

                if let error = error {
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HealthKit workouts: \(error.localizedDescription)"))
                    return
                }

                guard let workoutSamples = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                Task {
                    do {
                        var recentWorkouts: [WorkoutDetails] = []

                        let restingHR = try await self.fetchLatestRestingHeartRate(quantityType: restingHeartRateType)

                        for workout in workoutSamples {
                            let hrSamples = try await self.fetchHeartRateSamples(for: workout, quantityType: heartRateType)
                            let heartRateData = hrSamples.map { HeartRateSample(timestamp: $0.startDate, bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }

                            let avgHR = heartRateData.isEmpty ? 0 : heartRateData.reduce(0) { $0 + $1.bpm } / Double(heartRateData.count)
                            let maxHR = heartRateData.max(by: { $0.bpm < $1.bpm })?.bpm ?? 0

                            let wSport = SportCategory.from(hkType: workout.workoutActivityType.rawValue)
                            let wName = wSport.workoutName.prefix(1).uppercased() + wSport.workoutName.dropFirst()
                            let details = WorkoutDetails(
                                name: String(wName),
                                startDate: workout.startDate,
                                duration: workout.duration,
                                averageHeartRate: avgHR,
                                maxHeartRate: maxHR,
                                restingHeartRate: restingHR,
                                heartRateSamples: heartRateData
                            )
                            recentWorkouts.append(details)
                        }

                        continuation.resume(returning: recentWorkouts)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            healthStore.execute(query)
        }
    }

    /// Hulpfunctie om ruwe hartslagsamples op te halen behorend bij een specifieke workout.
    private func fetchHeartRateSamples(for workout: HKWorkout, quantityType: HKQuantityType) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HR samples: \(error.localizedDescription)"))
                    return
                }

                let hrSamples = (samples as? [HKQuantitySample]) ?? []
                continuation.resume(returning: hrSamples)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Epic 14: Readiness Score Data

    /// Haalt de gemiddelde HRV (SDNN, in milliseconden) op van de afgelopen nacht.
    /// Wanneer `sleepStart`/`sleepEnd` worden meegegeven, wordt uitsluitend de HRV
    /// binnen die exacte slaapsessie gebruikt — post-workout drops worden zo definitief
    /// uitgesloten. Zonder slaapvenster valt de query terug op het vaste nachtvenster
    /// (gisteren 18:00 → vandaag 14:00).
    /// - Returns: Gemiddelde HRV in ms, of nil als er geen meting beschikbaar is.
    func fetchRecentHRV(sleepStart: Date? = nil, sleepEnd: Date? = nil) async throws -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            AppLoggers.athleticProfileManager.error("[HRV] HKQuantityType voor heartRateVariabilitySDNN niet beschikbaar")
            return nil
        }

        // Gebruik het exacte slaapvenster als dat bekend is; anders het vaste nachtvenster.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let defaultEnd   = calendar.date(byAdding: .hour, value: 14, to: today)!
        let yesterday    = calendar.date(byAdding: .day, value: -1, to: today)!
        let defaultStart = calendar.date(byAdding: .hour, value: 18, to: yesterday)!

        let windowStart = sleepStart ?? defaultStart
        let windowEnd   = sleepEnd   ?? defaultEnd

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        if sleepStart != nil {
            AppLoggers.athleticProfileManager.debug("[HRV] Query gestart — gekoppeld aan slaapvenster")
        } else {
            AppLoggers.athleticProfileManager.debug("[HRV] Query gestart — standaard nachtvenster: gisteren 18:00 → vandaag 14:00")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    AppLoggers.athleticProfileManager.error("[HRV] HealthKit fout: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HRV: \(error.localizedDescription)"))
                    return
                }

                guard let hrvSamples = samples as? [HKQuantitySample], !hrvSamples.isEmpty else {
                    AppLoggers.athleticProfileManager.debug("[HRV] Geen samples gevonden in afgelopen 48 uur — Watch mogelijk niet gedragen")
                    continuation.resume(returning: nil)
                    return
                }

                // Bereken het gemiddelde van alle beschikbare metingen in het tijdvenster
                let unit = HKUnit.secondUnit(with: .milli)
                let totalHRV = hrvSamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
                let averageHRV = totalHRV / Double(hrvSamples.count)

                // HRV-waarde is user-specifieke fysiologische data → private.
                AppLoggers.athleticProfileManager.info("[HRV] Data ontvangen: \(String(format: "%.1f", averageHRV), privacy: .private) ms (\(hrvSamples.count, privacy: .public) meting(en))")
                continuation.resume(returning: averageHRV)
            }
            healthStore.execute(query)
        }
    }

    /// Haalt de gemiddelde HRV op over de afgelopen `days` dagen als persoonlijke baseline.
    /// Wordt gebruikt door ReadinessCalculator om de HRV van vannacht te contextualiseren.
    /// - Returns: Gemiddelde HRV in ms over het opgegeven venster, of nil als er geen data is.
    func fetchHRVBaseline(days: Int = 7) async throws -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            AppLoggers.athleticProfileManager.error("[HRV-Baseline] HKQuantityType niet beschikbaar")
            return nil
        }

        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        AppLoggers.athleticProfileManager.debug("[HRV-Baseline] Query gestart — venster: \(days, privacy: .public) dagen")

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    AppLoggers.athleticProfileManager.error("[HRV-Baseline] HealthKit fout: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HRV baseline: \(error.localizedDescription)"))
                    return
                }

                guard let hrvSamples = samples as? [HKQuantitySample], !hrvSamples.isEmpty else {
                    AppLoggers.athleticProfileManager.debug("[HRV-Baseline] Geen samples gevonden in afgelopen \(days, privacy: .public) dagen")
                    continuation.resume(returning: nil)
                    return
                }

                let unit = HKUnit.secondUnit(with: .milli)
                let total = hrvSamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
                let average = total / Double(hrvSamples.count)

                // HRV-baseline is user-specifieke fysiologische data → private.
                AppLoggers.athleticProfileManager.info("[HRV-Baseline] Data ontvangen: \(String(format: "%.1f", average), privacy: .private) ms (\(days, privacy: .public) dagen, \(hrvSamples.count, privacy: .public) meting(en))")
                continuation.resume(returning: average)
            }
            healthStore.execute(query)
        }
    }

    /// Berekent het aantal daadwerkelijk geslapen uren van de afgelopen nacht.
    /// Telt uitsluitend `.asleepCore`, `.asleepDeep` en `.asleepREM` op (iOS 16+ / watchOS 9+).
    /// Dit voorkomt dubbeltelling: op moderne hardware schrijft Apple Watch de stage-specifieke
    /// samples, maar sommige third-party bronnen schrijven ook een generiek `.asleep`-aggregate.
    /// Door alleen de drie fases te tellen sluiten we zowel inBed als dubbeltellingen uit.
    /// Fallback naar `.asleep` (legacy) als er geen stage-data aanwezig is.
    /// - Returns: Totale slaaptijd in uren (bijv. 7.5), of nil als geen data beschikbaar.
    func fetchLastNightSleep() async throws -> Double? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            AppLoggers.athleticProfileManager.error("[Slaap] HKCategoryType voor sleepAnalysis niet beschikbaar")
            return nil
        }

        // Vast nachtvenster: gisteren 18:00 tot vandaag 14:00.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let windowEnd = calendar.date(byAdding: .hour, value: 14, to: today)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let windowStart = calendar.date(byAdding: .hour, value: 18, to: yesterday)!

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        AppLoggers.athleticProfileManager.debug("[Slaap] Query gestart — venster: gisteren 18:00 → vandaag 14:00")

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    AppLoggers.athleticProfileManager.error("[Slaap] HealthKit fout: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen slaapdata: \(error.localizedDescription)"))
                    return
                }

                guard let sleepSamples = samples as? [HKCategorySample], !sleepSamples.isEmpty else {
                    AppLoggers.athleticProfileManager.debug("[Slaap] Geen samples gevonden in nachtvenster")
                    continuation.resume(returning: nil)
                    return
                }

                // Fase 1: probeer stage-specifieke waarden (watchOS 9+ / iOS 16+).
                // Door ALLEEN deze drie te tellen vermijden we dubbeltelling met legacy .asleep.
                let stageValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let stageSamples = sleepSamples.filter { stageValues.contains($0.value) }

                let totalSleepSeconds: Double
                if stageSamples.isEmpty {
                    // Fase 2 (fallback): ouder Apple Watch-model — gebruik generieke .asleep waarde.
                    let asleepValue: Int
                    if #available(iOS 16.0, *) {
                        asleepValue = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                    } else {
                        asleepValue = HKCategoryValueSleepAnalysis.asleep.rawValue
                    }
                    totalSleepSeconds = sleepSamples
                        .filter { $0.value == asleepValue }
                        .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                    AppLoggers.athleticProfileManager.debug("[Slaap] Geen stage-data — fallback naar generieke slaapwaarde")
                } else {
                    // Moderne Apple Watch: som Core + Deep + REM
                    totalSleepSeconds = stageSamples
                        .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                }

                guard totalSleepSeconds > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let totalSleepHours = totalSleepSeconds / 3600.0
                let hours = Int(totalSleepHours)
                let minutes = Int((totalSleepHours - Double(hours)) * 60)

                // Slaapuren zijn user-specifieke data → private.
                AppLoggers.athleticProfileManager.info("[Slaap] Afgelopen nacht: \(hours, privacy: .private)u \(minutes, privacy: .private)m (Core+Deep+REM = \(String(format: "%.2f", totalSleepHours), privacy: .private) uur)")
                continuation.resume(returning: totalSleepHours)
            }
            healthStore.execute(query)
        }
    }

    /// Epic 21 Sprint 2: Haalt de slaapfases op van de afgelopen nacht.
    /// Retourneert nil als HealthKit niet beschikbaar is of als er geen stage-specifieke data is
    /// (bijv. ouder Apple Watch-model dat alleen de generieke `.asleep` waarde registreert).
    /// De teruggegeven `SleepStages` bevat ook `sessionStart`/`sessionEnd` — de exacte grenzen
    /// van de slaapsessie — zodat de HRV-query daar naadloos op kan aansluiten.
    func fetchSleepStages() async throws -> SleepStages? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            AppLoggers.athleticProfileManager.error("[Slaapfases] HKCategoryType niet beschikbaar")
            return nil
        }

        // Zelfde vaste nachtvenster als fetchLastNightSleep(): gisteren 18:00 → vandaag 14:00.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let windowEnd = calendar.date(byAdding: .hour, value: 14, to: today)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let windowStart = calendar.date(byAdding: .hour, value: 18, to: yesterday)!

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        AppLoggers.athleticProfileManager.debug("[Slaapfases] Query gestart — venster: gisteren 18:00 → vandaag 14:00")

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    AppLoggers.athleticProfileManager.error("[Slaapfases] HealthKit fout: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let sleepSamples = samples as? [HKCategorySample], !sleepSamples.isEmpty else {
                    AppLoggers.athleticProfileManager.debug("[Slaapfases] Geen samples gevonden")
                    continuation.resume(returning: nil)
                    return
                }

                // Filter op de drie stage-specifieke waarden (watchOS 9+ / iOS 16+).
                let deepSamples = sleepSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
                let remSamples  = sleepSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue  }
                let coreSamples = sleepSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue }

                let deepSec = deepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let remSec  = remSamples.reduce(0.0)  { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let coreSec = coreSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

                // Als alle stage-specifieke waarden nul zijn is dit een ouder apparaat.
                guard deepSec + remSec + coreSec > 0 else {
                    AppLoggers.athleticProfileManager.debug("[Slaapfases] Geen stage-specifieke data — ouder device")
                    continuation.resume(returning: nil)
                    return
                }

                // Slaapvenster: vroegste start en laatste eind van de echte slaapfases.
                // Dit venster wordt doorgegeven aan fetchRecentHRV() om post-workout HRV uit te sluiten.
                let allStageSamples = deepSamples + remSamples + coreSamples
                let sessionStart = allStageSamples.map { $0.startDate }.min()
                let sessionEnd   = allStageSamples.map { $0.endDate   }.max()

                let totalSec = deepSec + remSec + coreSec
                let stages = SleepStages(
                    deepMinutes:  Int(deepSec  / 60),
                    remMinutes:   Int(remSec   / 60),
                    coreMinutes:  Int(coreSec  / 60),
                    totalMinutes: Int(totalSec / 60),
                    sessionStart: sessionStart,
                    sessionEnd:   sessionEnd
                )

                // Slaapminuten zijn user-specifieke fysiologische data → private.
                AppLoggers.athleticProfileManager.info("[Slaapfases] Diep: \(stages.deepMinutes, privacy: .private)m · REM: \(stages.remMinutes, privacy: .private)m · Kern: \(stages.coreMinutes, privacy: .private)m · Ratio diep: \(String(format: "%.0f%%", stages.deepRatio * 100), privacy: .private)")
                continuation.resume(returning: stages)
            }
            healthStore.execute(query)
        }
    }

    /// Haalt de meest recente VO2max schatting op uit HealthKit (ml/kg/min). Geeft nil als geen data.
    func fetchVO2Max() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return nil }
        let now = Date()
        let pastDate = Calendar.current.date(byAdding: .month, value: -6, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: pastDate, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let vo2 = sample.quantity.doubleValue(for: HKUnit(from: "ml/kg·min"))
                continuation.resume(returning: vo2)
            }
            healthStore.execute(query)
        }
    }

    /// Haalt de meest recente rusthartslag op uit HealthKit. Geeft nil terug als er geen meting is.
    func fetchRestingHeartRate() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        let now = Date()
        let pastDate = Calendar.current.date(byAdding: .month, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: pastDate, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: bpm)
            }
            healthStore.execute(query)
        }
    }

    /// Hulpfunctie om de meest recente rusthartslag op te halen.
    private func fetchLatestRestingHeartRate(quantityType: HKQuantityType) async throws -> Double {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let now = Date()
        let pastDate = Calendar.current.date(byAdding: .month, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: pastDate, end: now, options: .strictEndDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen RHR: \(error.localizedDescription)"))
                    return
                }

                guard let latestSample = samples?.first as? HKQuantitySample else {
                    // Fallback naar een standaardwaarde als er geen is gemeten in de afgelopen maand
                    continuation.resume(returning: 60.0)
                    return
                }

                let restingBpm = latestSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: restingBpm)
            }
            healthStore.execute(query)
        }
    }
}
