import Foundation
import HealthKit
import SwiftData

/// SPRINT 7.4 - Nieuwe service voor het asynchroon synchroniseren van historische workouts direct uit Apple HealthKit.
actor HealthKitSyncService {
    private let healthKitManager: HealthKitManager
    private let physiologicalCalculator: PhysiologicalCalculatorProtocol

    init(healthKitManager: HealthKitManager = HealthKitManager(),
         physiologicalCalculator: PhysiologicalCalculatorProtocol = PhysiologicalCalculator()) {
        self.healthKitManager = healthKitManager
        self.physiologicalCalculator = physiologicalCalculator
    }

    /// Haalt 1 jaar (365 dagen) aan historische workouts op uit HealthKit, berekent lokaal de TRIMP,
    /// en bewaart deze als `ActivityRecord` in de SwiftData context.
    /// - Parameter context: De context waarin de gesynchroniseerde data opgeslagen moet worden.
    /// - Returns: Aantal HK-workouts dat de query teruggaf in het 365d-window. Epic #38 Story 38.2
    ///   gebruikt deze count om de "stille sync"-banner op het Dashboard te triggeren wanneer
    ///   `count == 0 && workoutAuthStatus != .sharingAuthorized` — voorkomt dat de gebruiker
    ///   dagen rondloopt met een leeg dashboard zonder te weten dat het aan toestemmingen ligt.
    @MainActor
    func syncHistoricalWorkouts(to context: ModelContext) async throws -> Int {
        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!

        // Epic 33 Story 33.1b: maxHR afleiden via Tanaka-formule + dateOfBirth.
        // Eenmalig per sync (niet per workout) — geboortedatum verandert sowieso niet.
        // Bij ontbrekende toestemming/data valt classifier terug op 190 bpm default.
        let birthDate: Date? = {
            do {
                let dob = try healthKitManager.healthStore.dateOfBirthComponents()
                return Calendar.current.date(from: dob)
            } catch {
                return nil
            }
        }()
        let estimatedMaxHR = HeartRateZones.estimatedMaxHeartRate(birthDate: birthDate)
        let sessionClassifier = SessionClassifier(maxHeartRate: estimatedMaxHR)

        let now = Date()
        // Zoek 365 dagen terug
        guard let oneYearAgo = Calendar.current.date(byAdding: .day, value: -365, to: now) else {
            throw FitnessDataError.networkError("Kan datum voor historie niet berekenen.")
        }

        // We filteren niet op type; alle workouts tussen 1 jaar geleden en nu worden opgehaald
        let predicate = HKQuery.predicateForSamples(withStart: oneYearAgo, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        // Gebruik withCheckedThrowingContinuation om de asynchrone HealthKit query veilig te overbruggen
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HealthKit historie: \(error.localizedDescription)"))
                    return
                }

                let results = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: results)
            }
            healthKitManager.healthStore.execute(query)
        }

        // Loop asynchroon door alle gevonden workouts om de hartslag (gemiddeld, max) en rusthartslag op te halen
        // Lokale Set als extra veiligheidsnet: vangt duplicaten op die HealthKit zelf teruggeeft
        // (zelfde batch, zelfde UUID) — `smartInsert` doet de DB-zijde dedupe voor ons.
        var seenWorkoutIds = Set<String>()

        for workout in workouts {
            // Uniek ID gebaseerd op de HealthKit UUID
            let workoutId = workout.uuid.uuidString

            // In-batch UUID-dedupe: HealthKit kan dezelfde workout twee keer teruggeven
            // binnen één query (Watch + iPhone). `smartInsert` ziet niet-gesavede records
            // niet, dus deze laag blijft nodig om binnen één run dubbele inserts te voorkomen.
            guard seenWorkoutIds.insert(workoutId).inserted else {
                AppLoggers.fitnessDataService.debug("Sync: HealthKit UUID \(workoutId, privacy: .private) al verwerkt in deze batch — overgeslagen")
                continue
            }

            let sport = SportCategory.from(hkType: workout.workoutActivityType.rawValue)

            var avgHR: Double? = nil
            var maxHR: Double = 0
            var restHR: Double = 60 // Standaardwaarde als fallback

            do {
                // Haal de ruwe samples op voor deze workout (hergebruik van de functie uit HealthKitManager is hier niet direct beschikbaar via public scope, we doen de queries expliciet of we voegen een helper toe. Aangezien we de manager al hebben, kunnen we hem daar in theorie public maken of we herschrijven de call kort).
                // Om geen private methodes van de manager aan te roepen, gebruiken we een custom fetch
                let hrSamples = try await fetchHeartRateSamples(for: workout, quantityType: heartRateType)
                let heartRateData = hrSamples.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }

                if !heartRateData.isEmpty {
                    avgHR = heartRateData.reduce(0, +) / Double(heartRateData.count)
                    maxHR = heartRateData.max() ?? 0
                }

                // Rusthartslag ophalen op de dag van de workout (vereenvoudigde benadering)
                restHR = try await fetchRestingHeartRate(near: workout.startDate, quantityType: restingHeartRateType)
            } catch {
                AppLoggers.fitnessDataService.error("Kon geen HR data ophalen voor workout. Fout: \(error.localizedDescription, privacy: .public)")
            }

            // Bereken TRIMP (of gebruik nil als er geen hartslag is gemeten)
            let calcTSS = await physiologicalCalculator.calculateTSS(durationInSeconds: workout.duration, averageHeartRate: avgHR ?? 0, maxHeartRate: maxHR, restingHeartRate: restHR)
            let trimp = (avgHR != nil) ? calcTSS : nil

            // Map de HealthKit Workout naar onze ActivityRecord (SwiftData Model)
            // Gebruik de menselijke SportCategory-naam zodat de coach "wandeling" ziet, niet "HealthKit 52"
            // `sport` is al gedeclareerd op basis van workoutActivityType (Laag 1b hierboven)
            let recordName = sport.workoutName.prefix(1).uppercased() + sport.workoutName.dropFirst()

            // Epic 33 Story 33.1b: voorstel een sessionType op basis van avg HR + duur.
            // HealthKit-records hebben geen rijke titel — keyword-strategie levert hier
            // doorgaans niets op; de classifier valt automatisch terug op de avg-HR-route.
            // Bij latere DeepSync (samples) kan dit type opnieuw geclassificeerd worden;
            // voor 33.1b gebruiken we alleen het at-ingest signaal.
            let suggestedSessionType = sessionClassifier.classify(
                samples: nil,
                averageHeartRate: avgHR,
                durationSeconds: Int(workout.duration),
                title: nil
            )

            let record = ActivityRecord(
                id: workoutId,
                name: recordName,
                distance: workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0,
                movingTime: Int(workout.duration),
                averageHeartrate: avgHR,
                sportCategory: SportCategory.from(hkType: workout.workoutActivityType.rawValue),
                startDate: workout.startDate,
                trimp: trimp,
                sessionType: suggestedSessionType
            )

            // Epic 41.4: smart-insert beschermt tegen cross-source verarming.
            // Een Strava-record met deviceWatts dat al binnen ±5s in DB staat blijft
            // staan; een armer HK-record overschrijft dat niet meer.
            let result = try ActivityDeduplicator.smartInsert(record, into: context)
            switch result {
            case .skippedExistingRicher:
                AppLoggers.fitnessDataService.debug("Sync: HK-workout \(workoutId, privacy: .private) [\(sport.rawValue, privacy: .public)] overgeslagen — bestaand record is rijker (Epic 41.4)")
            case .replaced:
                AppLoggers.fitnessDataService.debug("Sync: bestaand armer record vervangen door HK-workout \(workoutId, privacy: .private)")
            case .inserted, .skippedSameSource:
                break
            }
        }

        try context.save()
        return workouts.count
    }

    // Hulpfunctie voor ruwe samples binnen dit actor domein
    private func fetchHeartRateSamples(for workout: HKWorkout, quantityType: HKQuantityType) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthKitManager.healthStore.execute(query)
        }
    }

    // Hulpfunctie voor rusthartslag
    private func fetchRestingHeartRate(near date: Date, quantityType: HKQuantityType) async throws -> Double {
        // Haal de RHR op in een venster van 30 dagen voorafgaand aan de activiteit
        guard let pastDate = Calendar.current.date(byAdding: .month, value: -1, to: date) else { return 60.0 }
        let predicate = HKQuery.predicateForSamples(withStart: pastDate, end: date, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let _ = error {
                    continuation.resume(returning: 60.0) // Fallback on error
                    return
                }

                guard let latestSample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: 60.0) // Fallback if no data
                    return
                }

                let restingBpm = latestSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: restingBpm)
            }
            healthKitManager.healthStore.execute(query)
        }
    }
}
