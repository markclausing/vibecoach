import Foundation
import SwiftData

/// Verantwoordelijk voor het ophalen van sport- en activiteitsdata van externe API's (bijv. Strava of Intervals.icu).
actor FitnessDataService {

    private let tokenStore: TokenStore
    private let session: NetworkSession

    // Dependency Injection voor de opslag van tokens en netwerksessies
    init(tokenStore: TokenStore = KeychainService.shared, session: NetworkSession = URLSession.shared) {
        self.tokenStore = tokenStore
        self.session = session
    }

    /// Controleert of het Strava token is verlopen (of binnen 5 minuten verloopt) en ververst deze via de OAuth2 API.
    func refreshTokenIfNeeded() async throws {
        // Haal huidige gegevens op
        guard let expiresAtStr = try tokenStore.getToken(forService: "StravaTokenExpiresAt"),
              let expiresAtUnix = Double(expiresAtStr),
              let currentRefreshToken = try tokenStore.getToken(forService: "StravaRefreshToken"), !currentRefreshToken.isEmpty else {
            // Als er geen refresh token of expiresAt is, kunnen we niet refreshen. We doen niets en laten de request eventueel falen op auth.
            return
        }

        let expirationDate = Date(timeIntervalSince1970: expiresAtUnix)

        // Controleer of de token binnen nu en 5 minuten verloopt
        let fiveMinutesFromNow = Date().addingTimeInterval(5 * 60)

        if expirationDate < fiveMinutesFromNow {
            // Token is (bijna) verlopen, refresh!
            print("Strava Token is verlopen of verloopt binnenkort. Vernieuwen...")

            guard let url = URL(string: "https://www.strava.com/oauth/token") else {
                throw FitnessDataError.networkError("Ongeldige refresh URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"

            // Stel de POST body in
            let bodyParams = [
                "client_id": Secrets.stravaClientID,
                "client_secret": Secrets.stravaClientSecret,
                "grant_type": "refresh_token",
                "refresh_token": currentRefreshToken
            ]

            var components = URLComponents()
            components.queryItems = bodyParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = components.query?.data(using: .utf8)
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw FitnessDataError.networkError("Fout bij ophalen refresh token: \(error.localizedDescription)")
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FitnessDataError.invalidResponse
            }

            if !(200...299).contains(httpResponse.statusCode) {
                throw FitnessDataError.networkError("Refresh mislukt met status code: \(httpResponse.statusCode)")
            }

            // Parse the response
            do {
                let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)

                // Sla nieuwe tokens op in de Keychain
                try tokenStore.saveToken(tokenResponse.access_token, forService: "StravaToken")
                try tokenStore.saveToken(tokenResponse.refresh_token, forService: "StravaRefreshToken")
                try tokenStore.saveToken(String(tokenResponse.expires_at), forService: "StravaTokenExpiresAt")

                print("Strava Token succesvol vernieuwd!")
            } catch {
                throw FitnessDataError.decodingError("Fout bij parsen refresh token response: \(error.localizedDescription)")
            }
        }
    }

    /// Haalt de meest recente activiteit van de gebruiker op via de Strava API.
    /// - Returns: Het laatst voltooide `StravaActivity` object.
    /// - Throws: `FitnessDataError` als er iets misgaat (bijv. geen token, 401, of network issue).
    func fetchLatestActivity() async throws -> StravaActivity? {
        // Zorg dat het token geldig is voordat we de aanroep doen
        try await refreshTokenIfNeeded()

        guard let stravaToken = try tokenStore.getToken(forService: "StravaToken"), !stravaToken.isEmpty else {
            throw FitnessDataError.missingToken
        }

        guard let url = URL(string: "https://www.strava.com/api/v3/athlete/activities?per_page=1") else {
            throw FitnessDataError.networkError("Ongeldige URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(stravaToken)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FitnessDataError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FitnessDataError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw FitnessDataError.unauthorized
        } else if !(200...299).contains(httpResponse.statusCode) {
            throw FitnessDataError.networkError("Onverwachte HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            let activities = try decoder.decode([StravaActivity].self, from: data)
            return activities.first
        } catch {
            throw FitnessDataError.decodingError(error.localizedDescription)
        }
    }

    /// Haalt een specifieke activiteit op via de Strava API op basis van het Activity ID.
    /// Dit wordt voornamelijk gebruikt wanneer een notificatie binnenkomt met een specifiek ID.
    /// - Parameter id: Het Strava Activity ID.
    /// - Returns: Het bijbehorende `StravaActivity` object.
    /// - Throws: `FitnessDataError` als er iets misgaat.
    func fetchActivity(byId id: Int64) async throws -> StravaActivity {
        try await refreshTokenIfNeeded()

        guard let stravaToken = try tokenStore.getToken(forService: "StravaToken"), !stravaToken.isEmpty else {
            throw FitnessDataError.missingToken
        }

        guard let url = URL(string: "https://www.strava.com/api/v3/activities/\(id)") else {
            throw FitnessDataError.networkError("Ongeldige URL voor activiteit \(id)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(stravaToken)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FitnessDataError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FitnessDataError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw FitnessDataError.unauthorized
        } else if httpResponse.statusCode == 404 {
             throw FitnessDataError.networkError("Activiteit met ID \(id) niet gevonden")
        } else if !(200...299).contains(httpResponse.statusCode) {
            throw FitnessDataError.networkError("Onverwachte HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            let activity = try decoder.decode(StravaActivity.self, from: data)
            return activity
        } catch {
            throw FitnessDataError.decodingError(error.localizedDescription)
        }
    }

    /// Haalt historische activiteiten op via de Strava API, met ondersteuning voor paginatie.
    /// Dit wordt gebruikt voor het berekenen van het langetermijn atletisch profiel.
    /// - Parameter monthsBack: Hoeveel maanden we terug willen kijken (bijv. 6).
    /// - Returns: Een lijst van `StravaActivity` objecten voor de afgelopen dagen.
    /// - Throws: `FitnessDataError` als de auth of het netwerk faalt.
    func fetchRecentActivities(days: Int) async throws -> [StravaActivity] {
        try await refreshTokenIfNeeded()

        guard let stravaToken = try tokenStore.getToken(forService: "StravaToken"), !stravaToken.isEmpty else {
            throw FitnessDataError.missingToken
        }

        let now = Date()
        let beforeTime = Int(now.timeIntervalSince1970)

        let calendar = Calendar.current
        guard let pastDate = calendar.date(byAdding: .day, value: -days, to: now) else {
            throw FitnessDataError.networkError("Fout bij het berekenen van startdatum")
        }
        let afterTime = Int(pastDate.timeIntervalSince1970)

        var allActivities: [StravaActivity] = []
        var page = 1
        let perPage = 200

        let decoder = JSONDecoder()

        while true {
            guard let url = URL(string: "https://www.strava.com/api/v3/athlete/activities?before=\(beforeTime)&after=\(afterTime)&page=\(page)&per_page=\(perPage)") else {
                throw FitnessDataError.networkError("Ongeldige URL voor history fetch")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(stravaToken)", forHTTPHeaderField: "Authorization")

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw FitnessDataError.networkError(error.localizedDescription)
            }

            guard let httpResp = response as? HTTPURLResponse else {
                throw FitnessDataError.invalidResponse
            }

            if httpResp.statusCode == 401 {
                throw FitnessDataError.unauthorized
            }
            guard httpResp.statusCode == 200 else {
                throw FitnessDataError.invalidResponse
            }

            do {
                let batch = try decoder.decode([StravaActivity].self, from: data)
                if batch.isEmpty {
                    break
                }
                allActivities.append(contentsOf: batch)
                page += 1
            } catch {
                throw FitnessDataError.decodingError(error.localizedDescription)
            }
        }

        return allActivities
    }

    /// - Returns: Een lijst van `StravaActivity` objecten.
    /// - Throws: `FitnessDataError` als de auth of het netwerk faalt.
    func fetchHistoricalActivities(monthsBack: Int) async throws -> [StravaActivity] {
        try await refreshTokenIfNeeded()

        guard let stravaToken = try tokenStore.getToken(forService: "StravaToken"), !stravaToken.isEmpty else {
            throw FitnessDataError.missingToken
        }

        // Bereken de UNIX timestamps
        let now = Date()
        let beforeTime = Int(now.timeIntervalSince1970)

        let calendar = Calendar.current
        guard let pastDate = calendar.date(byAdding: .month, value: -monthsBack, to: now) else {
            throw FitnessDataError.networkError("Fout bij het berekenen van startdatum")
        }
        let afterTime = Int(pastDate.timeIntervalSince1970)

        var allActivities: [StravaActivity] = []
        var page = 1
        let perPage = 200

        let decoder = JSONDecoder()

        // Paginatie loop (blijf doorgaan tot er een lege pagina terugkomt)
        while true {
            guard let url = URL(string: "https://www.strava.com/api/v3/athlete/activities?before=\(beforeTime)&after=\(afterTime)&page=\(page)&per_page=\(perPage)") else {
                throw FitnessDataError.networkError("Ongeldige URL voor history fetch")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(stravaToken)", forHTTPHeaderField: "Authorization")

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw FitnessDataError.networkError(error.localizedDescription)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FitnessDataError.invalidResponse
            }

            if httpResponse.statusCode == 401 {
                throw FitnessDataError.unauthorized
            } else if !(200...299).contains(httpResponse.statusCode) {
                throw FitnessDataError.networkError("Onverwachte HTTP status code: \(httpResponse.statusCode)")
            }

            do {
                let pageActivities = try decoder.decode([StravaActivity].self, from: data)

                if pageActivities.isEmpty {
                    // Er zijn geen resultaten meer, we zijn klaar
                    break
                }

                allActivities.append(contentsOf: pageActivities)
                page += 1
            } catch {
                throw FitnessDataError.decodingError(error.localizedDescription)
            }
        }

        return allActivities
    }
}

/// Samenvatting van het berekende profiel
struct AthleticProfile {
    var peakDistanceInMeters: Double
    var peakDurationInSeconds: Int
    var averageWeeklyVolumeInSeconds: Int
    var daysSinceLastTraining: Int
    var isRecoveryNeeded: Bool // SPRINT 6.3 - Proactieve Waarschuwing status
}

/// Verantwoordelijk voor het berekenen van het atleetprofiel op basis van historische gegevens in SwiftData.
@MainActor
class AthleticProfileManager {

    /// Berekent het profiel op basis van de aanwezige `ActivityRecord` elementen.
    /// Inclusief de Overtraining logica (Sprint 6.3).
    /// - Parameter context: De `ModelContext` van de app om gegevens uit te lezen.
    /// - Returns: Een berekend `AthleticProfile` of nil als er onvoldoende data is.
    func calculateProfile(context: ModelContext) throws -> AthleticProfile? {
        let fetchDescriptor = FetchDescriptor<ActivityRecord>()
        let allActivities = try context.fetch(fetchDescriptor)

        guard !allActivities.isEmpty else {
            return nil
        }

        // 1. Piekprestatie
        let peakDistance = allActivities.max(by: { $0.distance < $1.distance })?.distance ?? 0.0
        let peakDuration = allActivities.max(by: { $0.movingTime < $1.movingTime })?.movingTime ?? 0

        // 2. Dagen sinds de laatste training
        let mostRecentActivity = allActivities.max(by: { $0.startDate < $1.startDate })
        let daysSinceLast: Int
        if let recentActivity = mostRecentActivity {
            let components = Calendar.current.dateComponents([.day], from: recentActivity.startDate, to: Date())
            daysSinceLast = components.day ?? 0
        } else {
            daysSinceLast = 0
        }

        // 3. Wekelijks gemiddeld volume van de afgelopen 4 weken
        let now = Date()
        guard let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: now) else {
            return AthleticProfile(peakDistanceInMeters: peakDistance,
                                   peakDurationInSeconds: peakDuration,
                                   averageWeeklyVolumeInSeconds: 0,
                                   daysSinceLastTraining: daysSinceLast,
                                   isRecoveryNeeded: false)
        }

        let recentActivities = allActivities.filter { $0.startDate >= fourWeeksAgo }
        let totalVolumeRecent = recentActivities.reduce(0) { $0 + $1.movingTime }
        let averageWeeklyVolume = totalVolumeRecent / 4

        // 4. SPRINT 6.3: Overtrainingslogica
        var needsRecovery = false

        // Bereken volume van *alleen* de afgelopen week
        guard let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) else {
            return AthleticProfile(peakDistanceInMeters: peakDistance,
                                   peakDurationInSeconds: peakDuration,
                                   averageWeeklyVolumeInSeconds: averageWeeklyVolume,
                                   daysSinceLastTraining: daysSinceLast,
                                   isRecoveryNeeded: false)
        }
        let thisWeekActivities = recentActivities.filter { $0.startDate >= oneWeekAgo }
        let thisWeekVolume = thisWeekActivities.reduce(0) { $0 + $1.movingTime }

        // Regel 1: Volume deze week is > 50% hoger dan het gemiddelde
        // Zorg dat we niet delen door 0, en stel een ondergrens (b.v. average minimaal 2 uur) om false positives bij beginners te voorkomen
        if averageWeeklyVolume > 7200 {
            let ratio = Double(thisWeekVolume) / Double(averageWeeklyVolume)
            if ratio > 1.5 {
                needsRecovery = true
            }
        }

        // Regel 2: Traint al 4 of meer dagen op rij
        // Voor een simpeler algoritme: als er 4 trainingen zijn in de afgelopen 4 dagen (we negeren multi-a-days voor deze simpele check)
        guard let fourDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: now) else {
            return AthleticProfile(peakDistanceInMeters: peakDistance, peakDurationInSeconds: peakDuration, averageWeeklyVolumeInSeconds: averageWeeklyVolume, daysSinceLastTraining: max(0, daysSinceLast), isRecoveryNeeded: needsRecovery)
        }
        let daysTrainedInLast4Days = Set(thisWeekActivities.filter { $0.startDate >= fourDaysAgo }.map { Calendar.current.startOfDay(for: $0.startDate) }).count

        if daysTrainedInLast4Days >= 4 {
            needsRecovery = true
        }

        return AthleticProfile(
            peakDistanceInMeters: peakDistance,
            peakDurationInSeconds: peakDuration,
            averageWeeklyVolumeInSeconds: averageWeeklyVolume,
            daysSinceLastTraining: max(0, daysSinceLast),
            isRecoveryNeeded: needsRecovery
        )
    }
}

import HealthKit

/// Beheert de Apple HealthKit integratie en permissies
final class HealthKitManager: @unchecked Sendable {
    let healthStore = HKHealthStore()

    /// Vraagt toestemming aan de gebruiker om benodigde gezondheidsdata (workouts, hartslag, VO2 Max) te lezen.
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, FitnessDataError.networkError("HealthKit is niet beschikbaar op dit apparaat."))
            return
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKQuantityType.quantityType(forIdentifier: .vo2Max)!
        ]

        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            completion(success, error)
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

                        let details = WorkoutDetails(
                            name: "HealthKit Training",
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

                            let details = WorkoutDetails(
                                name: "HealthKit Training",
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

protocol PhysiologicalCalculatorProtocol {
    /// Berekent de Training Stress Score (TRIMP methode) gebaseerd op Banister.
    /// - Parameters:
    ///   - durationInSeconds: Duur van de activiteit in seconden.
    ///   - averageHeartRate: Gemiddelde hartslag tijdens de activiteit.
    ///   - maxHeartRate: De maximale hartslag van de gebruiker.
    ///   - restingHeartRate: De rusthartslag van de gebruiker.
    /// - Returns: De berekende TRIMP score.
    func calculateTSS(durationInSeconds: Double, averageHeartRate: Double, maxHeartRate: Double, restingHeartRate: Double) -> Double

    /// Berekent de Cardiac Drift op basis van de eerste en tweede helft van de hartslagsamples.
    /// - Parameter samples: De ruwe hartslagsamples van de workout.
    /// - Returns: Het percentage drift, of nil als er onvoldoende data is.
    func calculateCardiacDrift(samples: [HeartRateSample]) -> Double?
}

class PhysiologicalCalculator: PhysiologicalCalculatorProtocol {

    func calculateTSS(durationInSeconds: Double, averageHeartRate: Double, maxHeartRate: Double, restingHeartRate: Double) -> Double {
        // Voorkom delen door nul of negatieve waarden indien parameters onjuist zijn ingevoerd
        let hrr = maxHeartRate - restingHeartRate
        guard hrr > 0 else { return 0.0 }

        let hrDelta = (averageHeartRate - restingHeartRate) / hrr

        // Formule: duration in minuten * hrDelta * 0.64 * e^(1.92 * hrDelta)
        let durationInMinutes = durationInSeconds / 60.0

        let trimp = durationInMinutes * hrDelta * 0.64 * exp(1.92 * hrDelta)

        // Zorg ervoor dat we geen NaN of infinity teruggeven bij vreemde waarden
        if trimp.isNaN || trimp.isInfinite || trimp < 0 {
            return 0.0
        }

        return trimp
    }

    func calculateCardiacDrift(samples: [HeartRateSample]) -> Double? {
        // Nog te implementeren (placeholder)
        return nil
    }
}

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
    @MainActor
    func syncHistoricalWorkouts(to context: ModelContext) async throws {
        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!

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
        for workout in workouts {
            // Uniek ID gebaseerd op de HealthKit UUID
            let workoutId = workout.uuid.uuidString

            // Duplicaten voorkomen: Check of dit ID al bestaat in SwiftData
            let descriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.id == workoutId })
            if let existing = try? context.fetch(descriptor), !existing.isEmpty {
                // Sla over als hij al gesynchroniseerd is
                continue
            }

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
                print("Kon geen HR data ophalen voor workout op \(workout.startDate). Fout: \(error)")
            }

            // Bereken TRIMP (of gebruik nil als er geen hartslag is gemeten)
            let calcTSS = await physiologicalCalculator.calculateTSS(durationInSeconds: workout.duration, averageHeartRate: avgHR ?? 0, maxHeartRate: maxHR, restingHeartRate: restHR)
            let trimp = (avgHR != nil) ? calcTSS : nil

            // Map de HealthKit Workout naar onze ActivityRecord (SwiftData Model)
            // type wordt als string opgeslagen (we gebruiken de naam van het HKWorkoutActivityType via een simpele string mapping voor de UI)
            let recordName = "HealthKit \(workout.workoutActivityType.rawValue)"

            let record = ActivityRecord(
                id: workoutId,
                name: recordName,
                distance: workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0,
                movingTime: Int(workout.duration),
                averageHeartrate: avgHR,
                type: "HealthKit",
                startDate: workout.startDate,
                trimp: trimp
            )

            context.insert(record)
        }

        try context.save()
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
