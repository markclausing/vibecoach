import Foundation
import SwiftData
import os

/// Verantwoordelijk voor het ophalen van sport- en activiteitsdata van externe API's (bijv. Strava of Intervals.icu).
actor FitnessDataService {

    /// Unified logger — gebruik `.private` voor user-tokens en sample-waardes (HRV, TRIMP)
    /// zodat sysdiagnose-logs in release-builds geen identificerende data lekken.
    static let logger = Logger(subsystem: "com.markclausing.aifitnesscoach", category: "FitnessDataService")

    private let tokenStore: TokenStore
    private let session: NetworkSession

    // Dependency Injection voor de opslag van tokens en netwerksessies
    init(tokenStore: TokenStore = KeychainService.shared, session: NetworkSession = URLSession.shared) {
        self.tokenStore = tokenStore
        self.session = session
    }

    /// Epic 41.3: zorgt dat de caller een geldig Strava access-token in handen krijgt.
    /// Roept eerst `refreshTokenIfNeeded()` aan zodat een (bijna) verlopen token nog
    /// vóór de API-call ververst wordt, en throwt `.missingToken` als er geen geldig
    /// token uit de store komt — dat geeft elke API-call één centrale guard tegen
    /// silent 401's.
    @discardableResult
    func ensureValidToken() async throws -> String {
        try await refreshTokenIfNeeded()
        guard let token = try tokenStore.getToken(forService: "StravaToken"), !token.isEmpty else {
            throw FitnessDataError.missingToken
        }
        return token
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
            Self.logger.info("Strava-token is verlopen of verloopt binnenkort — vernieuwen via proxy")

            // C-01: refresh loopt via de server-side proxy. Het `client_secret`
            // is niet meer in de app aanwezig.
            guard let url = URL(string: "\(Secrets.stravaProxyBaseURL)/oauth/strava/refresh") else {
                throw FitnessDataError.networkError("Ongeldige proxy URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(Secrets.stravaProxyToken, forHTTPHeaderField: "X-Client-Token")

            do {
                let body: [String: String] = ["refresh_token": currentRefreshToken]
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw FitnessDataError.networkError("Fout bij opbouwen refresh-request: \(error.localizedDescription)")
            }

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

                Self.logger.info("Strava-token succesvol vernieuwd")
            } catch {
                throw FitnessDataError.decodingError("Fout bij parsen refresh token response: \(error.localizedDescription)")
            }
        }
    }

    /// Haalt de meest recente activiteit van de gebruiker op via de Strava API.
    /// - Returns: Het laatst voltooide `StravaActivity` object.
    /// - Throws: `FitnessDataError` als er iets misgaat (bijv. geen token, 401, of network issue).
    func fetchLatestActivity() async throws -> StravaActivity? {
        let stravaToken = try await ensureValidToken()

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
        let stravaToken = try await ensureValidToken()

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

    /// Epic 44 Story 44.3: haalt de FTP van de geauthenticeerde Strava-atleet op
    /// via `/api/v3/athlete`. Strava onderhoudt FTP als onderdeel van het athlete-
    /// profiel; gebruikers die hun FTP daar al kalibreren krijgen 'm via deze
    /// endpoint terug zonder dat we 'm zelf hoeven te schatten.
    /// - Returns: FTP in watt, of `nil` als de gebruiker geen FTP in z'n profiel
    ///   heeft ingevuld (Strava returnt dan ofwel `null` ofwel het ontbrekende veld).
    /// - Throws: `FitnessDataError` bij netwerk-, auth- of decode-fout.
    func fetchAthleteFTP() async throws -> Int? {
        let stravaToken = try await ensureValidToken()

        guard let url = URL(string: "https://www.strava.com/api/v3/athlete") else {
            throw FitnessDataError.networkError("Ongeldige athlete-URL")
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
            let athlete = try JSONDecoder().decode(StravaAthlete.self, from: data)
            return athlete.ftp
        } catch {
            throw FitnessDataError.decodingError(error.localizedDescription)
        }
    }

    /// Epic 40: Haalt de fijngranulaire stream-data op voor één Strava-activity.
    /// Vraagt de stromen `time`, `watts`, `cadence`, `heartrate` en `velocity_smooth`
    /// op als `key_by_type=true`-dictionary. Niet alle streams zijn altijd aanwezig
    /// (bv. `watts` ontbreekt zonder powermeter) — caller moet optionals correct
    /// behandelen via `StravaStreamSet`.
    /// - Parameter activityId: De Strava-activity-ID.
    /// - Returns: Volledige `StravaStreamSet` met de beschikbare streams.
    /// - Throws: `FitnessDataError` bij netwerkfout, ongeldige token of decode-failure.
    func fetchActivityStreams(for activityId: Int64) async throws -> StravaStreamSet {
        let stravaToken = try await ensureValidToken()

        let keys = "time,watts,cadence,heartrate,velocity_smooth"
        let urlString = "https://www.strava.com/api/v3/activities/\(activityId)/streams?keys=\(keys)&key_by_type=true"
        guard let url = URL(string: urlString) else {
            throw FitnessDataError.networkError("Ongeldige URL voor streams van activiteit \(activityId)")
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
            throw FitnessDataError.networkError("Streams voor activiteit \(activityId) niet gevonden")
        } else if !(200...299).contains(httpResponse.statusCode) {
            throw FitnessDataError.networkError("Onverwachte HTTP status code: \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode(StravaStreamSet.self, from: data)
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
        let stravaToken = try await ensureValidToken()

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
        let stravaToken = try await ensureValidToken()

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
    var recoveryReason: String? // Reden voor het hersteladvies (welke regel heeft getriggerd)
    var averagePacePerKmInSeconds: Int? // SPRINT 9.3 - Gemiddeld hardlooptempo
}

/// Verantwoordelijk voor het berekenen van het atleetprofiel op basis van historische gegevens in SwiftData.
@MainActor
class AthleticProfileManager {

    // Epic 39 Story 39.1: logger leeft nu in `AppLoggers` — main-actor-isolation
    // op een `static let` veroorzaakte 70 Swift 6-warnings vanuit @Sendable
    // HealthKit-callbacks.

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
                                   isRecoveryNeeded: false,
                                   recoveryReason: nil,
                                   averagePacePerKmInSeconds: nil)
        }

        let recentActivities = allActivities.filter { $0.startDate >= fourWeeksAgo }
        let totalVolumeRecent = recentActivities.reduce(0) { $0 + $1.movingTime }
        let averageWeeklyVolume = totalVolumeRecent / 4

        // 4. SPRINT 6.3: Overtrainingslogica
        var needsRecovery = false
        var recoveryReason: String? = nil

        // Bereken volume van *alleen* de afgelopen week
        guard let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) else {
            return AthleticProfile(peakDistanceInMeters: peakDistance,
                                   peakDurationInSeconds: peakDuration,
                                   averageWeeklyVolumeInSeconds: averageWeeklyVolume,
                                   daysSinceLastTraining: daysSinceLast,
                                   isRecoveryNeeded: false,
                                   recoveryReason: nil,
                                   averagePacePerKmInSeconds: nil)
        }
        let thisWeekActivities = recentActivities.filter { $0.startDate >= oneWeekAgo }
        let thisWeekVolume = thisWeekActivities.reduce(0) { $0 + $1.movingTime }

        // Regel 1: Volume deze week is > 50% hoger dan het gemiddelde
        if averageWeeklyVolume > 7200 {
            let ratio = Double(thisWeekVolume) / Double(averageWeeklyVolume)
            if ratio > 1.5 {
                needsRecovery = true
                let pct = Int((ratio - 1.0) * 100)
                recoveryReason = "Volume deze week is \(pct)% boven je gemiddelde. Plan 1–2 rustdagen."
            }
        }

        // Regel 2: Traint al 4 of meer dagen op rij
        guard let fourDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: now) else {
            return AthleticProfile(peakDistanceInMeters: peakDistance, peakDurationInSeconds: peakDuration, averageWeeklyVolumeInSeconds: averageWeeklyVolume, daysSinceLastTraining: max(0, daysSinceLast), isRecoveryNeeded: needsRecovery, recoveryReason: recoveryReason, averagePacePerKmInSeconds: nil)
        }
        let daysTrainedInLast4Days = Set(thisWeekActivities.filter { $0.startDate >= fourDaysAgo }.map { Calendar.current.startOfDay(for: $0.startDate) }).count

        if daysTrainedInLast4Days >= 4 {
            needsRecovery = true
            recoveryReason = "\(daysTrainedInLast4Days) dagen op rij getraind. Neem vandaag rust."
        }

        // 5. SPRINT 9.3: Gemiddeld tempo berekenen (baseline pace)
        var averagePace: Int? = nil
        if let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) {
            let runningActivities = allActivities.filter {
                $0.startDate >= thirtyDaysAgo && $0.sportCategory == .running
            }

            let totalRunningDistance = runningActivities.reduce(0.0) { $0 + $1.distance }
            let totalRunningTime = runningActivities.reduce(0) { $0 + $1.movingTime }

            // Controleer op division by zero en zorg voor betrouwbare data (minimaal 1km gelopen)
            if totalRunningDistance > 1000.0 && totalRunningTime > 0 {
                // Pace = (tijd in seconden / afstand in meters) * 1000 = seconden per kilometer
                averagePace = Int((Double(totalRunningTime) / totalRunningDistance) * 1000.0)
            }
        }

        return AthleticProfile(
            peakDistanceInMeters: peakDistance,
            peakDurationInSeconds: peakDuration,
            averageWeeklyVolumeInSeconds: averageWeeklyVolume,
            daysSinceLastTraining: max(0, daysSinceLast),
            isRecoveryNeeded: needsRecovery,
            recoveryReason: recoveryReason,
            averagePacePerKmInSeconds: averagePace
        )
    }
}

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
            print("🔍 [HRV] Query gestart — gekoppeld aan slaapvenster: \(windowStart) → \(windowEnd)")
        } else {
            print("🔍 [HRV] Query gestart — standaard nachtvenster: gisteren 18:00 → vandaag 14:00")
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
            print("❌ [HRV-Baseline] HKQuantityType niet beschikbaar")
            return nil
        }

        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        print("🔍 [HRV-Baseline] Query gestart — venster: \(days) dagen")

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    print("❌ [HRV-Baseline] HealthKit fout: \(error.localizedDescription)")
                    continuation.resume(throwing: FitnessDataError.networkError("Fout bij ophalen HRV baseline: \(error.localizedDescription)"))
                    return
                }

                guard let hrvSamples = samples as? [HKQuantitySample], !hrvSamples.isEmpty else {
                    print("⚠️ [HRV-Baseline] Geen samples gevonden in afgelopen \(days) dagen")
                    continuation.resume(returning: nil)
                    return
                }

                let unit = HKUnit.secondUnit(with: .milli)
                let total = hrvSamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
                let average = total / Double(hrvSamples.count)

                print("✅ [HRV-Baseline] Data ontvangen: \(String(format: "%.1f", average)) ms (\(days) dagen, \(hrvSamples.count) meting(en))")
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

        print("🔍 [Slaap] Query gestart — venster: gisteren 18:00 → vandaag 14:00")

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
                    print("🔄 [Slaap] Geen stage-data — fallback naar generieke slaapwaarde")
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

        print("🔍 [Slaapfases] Query gestart — venster: gisteren 18:00 → vandaag 14:00")

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    AppLoggers.athleticProfileManager.error("[Slaapfases] HealthKit fout: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let sleepSamples = samples as? [HKCategorySample], !sleepSamples.isEmpty else {
                    print("⚠️ [Slaapfases] Geen samples gevonden")
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
                    print("⚠️ [Slaapfases] Geen stage-specifieke data — ouder device")
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

                print("🌙 [Slaapfases] Diep: \(stages.deepMinutes)m · REM: \(stages.remMinutes)m · Kern: \(stages.coreMinutes)m · Ratio diep: \(String(format: "%.0f%%", stages.deepRatio * 100))")
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

// MARK: - Epic 14: Readiness Score Algoritme

/// Berekent de dagelijkse Vibe/Readiness Score (0-100) op basis van slaap en HRV.
///
/// **Slaap (50% weging):**
/// - 8+ uur → 100 punten
/// - 5 uur of minder → 0 punten
/// - Lineair daartussen (bijv. 6.5 uur ≈ 50 punten)
///
/// **HRV (50% weging):**
/// - Gelijk aan of hoger dan 7-daagse baseline → 100 punten
/// - Meer dan 20% onder de baseline → 0 punten (rode vlag: overtraining / ziekte)
/// - Lineair daartussen
// MARK: - SleepStages

/// Epic 21 Sprint 2: Gedetailleerde uitsplitsing van slaapfases van de afgelopen nacht.
/// Bevat alleen stage-specifieke data (iOS 16+ Apple Watch). Nil = ouder device of Watch niet gedragen.
struct SleepStages {
    let deepMinutes:  Int
    let remMinutes:   Int
    let coreMinutes:  Int
    let totalMinutes: Int
    /// Exacte start van de slaapsessie (vroegste Core/Deep/REM sample).
    /// Wordt doorgegeven aan fetchRecentHRV() om het HRV-venster te begrenzen.
    let sessionStart: Date?
    /// Exacte eind van de slaapsessie (laatste Core/Deep/REM sample).
    let sessionEnd: Date?

    /// Verhouding diepe slaap t.o.v. totale slaaptijd (0.0–1.0).
    var deepRatio: Double {
        totalMinutes > 0 ? Double(deepMinutes) / Double(totalMinutes) : 0
    }

    /// Kwaliteitslabel op basis van de diepeslaap-ratio.
    /// Wetenschap: gezonde volwassen heeft ~15–25% diepe slaap.
    var qualityLabel: String {
        if deepRatio >= 0.20 { return "Uitstekend" }
        if deepRatio >= 0.15 { return "Goed" }
        if deepRatio >= 0.10 { return "Matig" }
        return "Onvoldoende"
    }

    /// SF Symbol passend bij de slaapkwaliteit.
    var qualityIcon: String {
        if deepRatio >= 0.15 { return "moon.stars.fill" }
        if deepRatio >= 0.10 { return "moon.fill" }
        return "moon.zzz.fill"
    }

    /// Helperformatter: X u Y m string.
    static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)u \(m)m" : "\(h)u"
    }
}

// MARK: - ReadinessCalculator

struct ReadinessCalculator {

    /// Bereken de Vibe Score.
    /// - Parameters:
    ///   - sleepHours: Daadwerkelijke slaaptijd afgelopen nacht in uren.
    ///   - hrv: Gemiddelde HRV van afgelopen nacht in ms.
    ///   - hrvBaseline: Gemiddelde HRV van de afgelopen 7 dagen (persoonlijke baseline) in ms.
    ///   - deepSleepRatio: Optioneel — verhouding diepe slaap t.o.v. totaal (0.0–1.0).
    ///     Nil = ouder device of geen stage-data → geen strafpunt toegepast.
    ///     < 0.10 → -15 punten | 0.10–0.15 → -8 punten | ≥ 0.15 → geen straf.
    /// - Returns: Score van 0 t/m 100.
    static func calculate(sleepHours: Double, hrv: Double, hrvBaseline: Double,
                          deepSleepRatio: Double? = nil) -> Int {
        // Slaapscore: lineair van 5 uur (0 punten) tot 8 uur (100 punten)
        let sleepScore = min(1.0, max(0.0, (sleepHours - 5.0) / 3.0)) * 100.0

        // HRV-score: vergelijken met persoonlijke baseline
        // Ondergrens = 80% van baseline (meer dan 20% onder = volledige rode vlag)
        let hrvLowerBound = hrvBaseline * 0.80
        let hrvScore: Double
        if hrv >= hrvBaseline {
            hrvScore = 100.0
        } else if hrv <= hrvLowerBound {
            hrvScore = 0.0
        } else {
            hrvScore = ((hrv - hrvLowerBound) / (hrvBaseline - hrvLowerBound)) * 100.0
        }

        var finalScore = (sleepScore + hrvScore) / 2.0

        // Strafpunt bij onvoldoende diepe slaap — herstel is minder effectief ondanks voldoende uren.
        // Alleen toegepast als er stage-specifieke data beschikbaar is.
        if let ratio = deepSleepRatio {
            if ratio < 0.10 {
                finalScore -= 15.0
            } else if ratio < 0.15 {
                finalScore -= 8.0
            }
        }

        return Int(min(100, max(0, finalScore)).rounded())
    }
}

// MARK: - Blessure-Impact Matrix

/// Berekent de extra fysiologische belasting op basis van actieve blessure-voorkeuren en sportkeuze.
/// Wordt gebruikt in de ACWR-bannerstatus op het dashboard en voor AI-prompt injectie.
struct InjuryImpactMatrix {

    /// Retourneert de penalty-multiplier: hoeveel zwaarder de workout aankomt gezien de actieve blessure(s).
    /// - Parameters:
    ///   - sport: De SportCategory van de laatste workout.
    ///   - preferences: Actieve gebruikersvoorkeuren (inclusief blessures/klachten).
    /// - Returns: 1.0 = geen impact, 1.4 = 40% extra fysiologische belasting.
    static func penaltyMultiplier(for sport: SportCategory, given preferences: [UserPreference]) -> Double {
        var maxMultiplier = 1.0
        for pref in preferences {
            let text = pref.preferenceText.lowercased()
            // Kuit/Scheen: hoge impact bij hardlopen (1.4x), licht verhoogd bij wandelen (1.1x)
            if text.contains("kuit") || text.contains("scheen") || text.contains("shin") {
                switch sport {
                case .running: maxMultiplier = max(maxMultiplier, 1.4)
                case .walking: maxMultiplier = max(maxMultiplier, 1.1)
                default: break
                }
            }
            // Rug: matige impact bij hardlopen en krachttraining (1.2x), licht bij fietsen (1.1x)
            if text.contains("rug") || text.contains("rugpijn") || text.contains("back pain") {
                switch sport {
                case .running, .strength: maxMultiplier = max(maxMultiplier, 1.2)
                case .cycling: maxMultiplier = max(maxMultiplier, 1.1)
                default: break
                }
            }
        }
        return maxMultiplier
    }

    /// Geeft een beknopte omschrijving van de blessure die relevant is voor de gegeven sport.
    /// Wordt gebruikt in de bannertekst om contextueel te communiceren.
    static func injuryDescription(for sport: SportCategory, given preferences: [UserPreference]) -> String? {
        for pref in preferences {
            let text = pref.preferenceText.lowercased()
            if (text.contains("kuit") || text.contains("scheen")) && (sport == .running || sport == .walking) {
                return "kuitklachten"
            }
            if (text.contains("rug") || text.contains("rugpijn")) && (sport == .running || sport == .cycling || sport == .strength) {
                return "rugklachten"
            }
        }
        return nil
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
                print("⚠️ Sync: HealthKit UUID \(workoutId) al verwerkt in deze batch — overgeslagen")
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
                print("Kon geen HR data ophalen voor workout op \(workout.startDate). Fout: \(error)")
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
                print("⚠️ Sync: HK-workout \(workoutId) [\(sport.rawValue)] overgeslagen — bestaand record is rijker (Epic 41.4)")
            case .replaced:
                print("ℹ️ Sync: bestaand armer record vervangen door HK-workout \(workoutId)")
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

// MARK: - Epic 17: BlueprintChecker

/// Vergelijkt de trainingshistorie van de gebruiker met sportwetenschappelijke harde regels
/// per doeltype. Retourneert een lijst van voldane en openstaande kritieke eisen (milestones).
struct BlueprintChecker {

    // MARK: - Hardcoded Blueprints

    /// Marathon Blueprint — sportwetenschappelijke regels voor 42.195 km race-voorbereiding.
    /// Bron: Daniels' Running Formula / Pfitzinger & Douglas periodiseringsmodel.
    static let marathonBlueprint = GoalBlueprint(
        goalType: .marathon,
        minLongRunDistance: 32_000,  // 32 km minimale piekduurloop
        taperPeriodWeeks: 3,
        weeklyTrimpTarget: 500,
        essentialWorkouts: [
            EssentialWorkout(
                id: "marathon_long_run_28",
                description: "28 km duurloop",
                minimumDistanceMeters: 28_000,
                requiredSportCategory: .running,
                mustCompleteByWeeksBefore: 6
            ),
            EssentialWorkout(
                id: "marathon_long_run_32",
                description: "32 km duurloop",
                minimumDistanceMeters: 32_000,
                requiredSportCategory: .running,
                mustCompleteByWeeksBefore: 3
            )
        ]
    )

    /// Halve Marathon Blueprint — sportwetenschappelijke regels voor 21.1 km race-voorbereiding.
    static let halfMarathonBlueprint = GoalBlueprint(
        goalType: .halfMarathon,
        minLongRunDistance: 18_000,  // 18 km minimale piekduurloop
        taperPeriodWeeks: 2,
        weeklyTrimpTarget: 350,
        essentialWorkouts: [
            EssentialWorkout(
                id: "half_marathon_long_run_16",
                description: "16 km duurloop",
                minimumDistanceMeters: 16_000,
                requiredSportCategory: .running,
                mustCompleteByWeeksBefore: 4
            ),
            EssentialWorkout(
                id: "half_marathon_long_run_18",
                description: "18 km duurloop",
                minimumDistanceMeters: 18_000,
                requiredSportCategory: .running,
                mustCompleteByWeeksBefore: 2
            )
        ]
    )

    /// Fietsdoel Blueprint — sportwetenschappelijke regels voor een meerdaagse fietstocht
    /// (bijv. Arnhem–Karlsruhe ±400 km over 4 dagen, ~100 km/dag gemiddeld).
    static let cyclingTourBlueprint = GoalBlueprint(
        goalType: .cyclingTour,
        minLongRunDistance: 100_000,  // 100 km minimale lange duurrit
        taperPeriodWeeks: 2,
        weeklyTrimpTarget: 400,
        essentialWorkouts: [
            EssentialWorkout(
                id: "cycling_medium_ride_60",
                description: "60 km duurrit",
                minimumDistanceMeters: 60_000,
                requiredSportCategory: .cycling,
                mustCompleteByWeeksBefore: 8
            ),
            EssentialWorkout(
                id: "cycling_long_ride_100",
                description: "100 km duurrit",
                minimumDistanceMeters: 100_000,
                requiredSportCategory: .cycling,
                mustCompleteByWeeksBefore: 4
            )
        ]
    )

    // MARK: - Blueprint detectie

    /// Detecteert het blueprint-type op basis van sleutelwoorden in de doeltitel.
    /// Valt terug op de SportCategory als er geen titelmatch is.
    static func detectBlueprintType(for goal: FitnessGoal) -> GoalBlueprintType? {
        let title = goal.title.lowercased()

        // Halve marathon vóór marathon checken — "marathon" zit ook in "halve marathon"
        for type in [GoalBlueprintType.halfMarathon, .marathon, .cyclingTour] {
            if type.detectionKeywords.contains(where: { title.contains($0) }) {
                return type
            }
        }

        // Fallback op SportCategory
        switch goal.sportCategory {
        case .running:  return .marathon
        case .cycling:  return .cyclingTour
        default:        return nil
        }
    }

    static func blueprint(for type: GoalBlueprintType) -> GoalBlueprint {
        switch type {
        case .marathon:     return marathonBlueprint
        case .halfMarathon: return halfMarathonBlueprint
        case .cyclingTour:  return cyclingTourBlueprint
        }
    }

    // MARK: - Milestone Check

    /// Vergelijkt de activiteitenhistorie met de kritieke eisen van het blueprint voor één doel.
    /// - Returns: BlueprintCheckResult met alle milestones, of nil als er geen blueprint van toepassing is.
    static func check(goal: FitnessGoal, activities: [ActivityRecord]) -> BlueprintCheckResult? {
        guard let blueprintType = detectBlueprintType(for: goal) else { return nil }
        let bp = blueprint(for: blueprintType)

        let milestones: [MilestoneStatus] = bp.essentialWorkouts.map { workout in
            // Deadline = targetDate minus N weken
            let deadline = Calendar.current.date(
                byAdding: .weekOfYear,
                value: -workout.mustCompleteByWeeksBefore,
                to: goal.targetDate
            ) ?? goal.targetDate

            // Zoek de vroegste activiteit die aan alle eisen voldoet (sport + afstand + vóór deadline)
            let satisfyingActivity = activities.first { record in
                guard record.sportCategory == workout.requiredSportCategory else { return false }
                guard record.startDate <= deadline else { return false }
                if let minDist = workout.minimumDistanceMeters {
                    return record.distance >= minDist
                }
                return true
            }

            return MilestoneStatus(
                id: workout.id,
                description: workout.description,
                isSatisfied: satisfyingActivity != nil,
                satisfiedByDate: satisfyingActivity?.startDate,
                deadline: deadline,
                weeksBefore: workout.mustCompleteByWeeksBefore
            )
        }

        return BlueprintCheckResult(blueprint: bp, goal: goal, milestones: milestones)
    }

    /// Controleert alle actieve doelen en retourneert resultaten gesorteerd op urgentie
    /// (doelen met openstaande milestones eerst).
    static func checkAllGoals(_ goals: [FitnessGoal], activities: [ActivityRecord]) -> [BlueprintCheckResult] {
        let now = Date()
        return goals
            .filter { !$0.isCompleted && now < $0.targetDate }
            .compactMap { check(goal: $0, activities: activities) }
            .sorted { !$0.isOnTrack && $1.isOnTrack }
    }
}

// MARK: - Epic 17.1: PeriodizationEngine

/// Berekent per actief doel de sportwetenschappelijke voortgang op basis van de huidige
/// trainingsfase en de bijbehorende succescriteria uit de GoalBlueprint.
///
/// Werkt samen met BlueprintChecker (kritieke milestone-checks) en TrainingPhase (fase-detectie)
/// om een volledig beeld te geven: "Wat moet ik NU doen om op schema te blijven?"
struct PeriodizationEngine {

    // MARK: - Evaluatie

    /// Evalueert één doel: detecteert de actieve blueprint, bepaalt de fase en toetst
    /// de recente activiteiten aan de fase-specifieke succescriteria.
    ///
    /// - Parameters:
    ///   - goal: Het te evalueren fitnessdoel.
    ///   - activities: Alle beschikbare activiteiten van de gebruiker.
    ///   - latestReadinessScore: Meest recente VibeScore (0–100). Nil = onbekend → neutraal gedrag.
    /// - Returns: `PeriodizationResult` met fase, criteria, langste sessie en TRIMP-check,
    ///   of `nil` als er geen blueprint van toepassing is of het doel al afgerond/verlopen is.
    static func evaluate(
        goal: FitnessGoal,
        activities: [ActivityRecord],
        latestReadinessScore: Int? = nil
    ) -> PeriodizationResult? {
        guard !goal.isCompleted, Date() < goal.targetDate else { return nil }
        guard let blueprintType = BlueprintChecker.detectBlueprintType(for: goal) else { return nil }

        let bp = BlueprintChecker.blueprint(for: blueprintType)
        let weeksRemaining = goal.targetDate.timeIntervalSince(Date()) / (7 * 86400)
        let phase = TrainingPhase.calculate(weeksRemaining: weeksRemaining)
        let criteria = phase.successCriteria

        // Bepaal het sport-type dat bij de blueprint past (hardlopen voor marathon, fietsen voor tour)
        let targetSport: SportCategory
        switch blueprintType {
        case .marathon, .halfMarathon: targetSport = .running
        case .cyclingTour:             targetSport = .cycling
        }

        // Langste sessie binnen het fase-specifieke terugkijkvenster
        let windowStart = Calendar.current.date(
            byAdding: .weekOfYear,
            value: -criteria.sessionWindowWeeks,
            to: Date()
        ) ?? Date()

        let longestSession = activities
            .filter { $0.sportCategory == targetSport && $0.startDate >= windowStart }
            .map { $0.distance }
            .max() ?? 0.0

        // Gemiddeld wekelijks TRIMP over de afgelopen 4 weken (breed venster voor stabiliteit)
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date()) ?? Date()
        let recentTRIMP = activities
            .filter { $0.startDate >= fourWeeksAgo }
            .compactMap { $0.trimp }
            .reduce(0, +)
        let avgWeeklyTrimp = recentTRIMP / 4.0

        // Epic Doel-Intenties: bouw de intentie-modifier op basis van format, intent en VibeScore
        let intentModifier = buildIntentModifier(goal: goal, phase: phase, readinessScore: latestReadinessScore)

        return PeriodizationResult(
            goal: goal,
            blueprint: bp,
            phase: phase,
            criteria: criteria,
            longestRecentSessionMeters: longestSession,
            currentWeeklyTrimp: avgWeeklyTrimp,
            intentModifier: intentModifier
        )
    }

    /// Evalueert alle actieve doelen en retourneert resultaten gesorteerd op urgentie
    /// (doelen die niet op schema zijn komen eerst).
    static func evaluateAllGoals(
        _ goals: [FitnessGoal],
        activities: [ActivityRecord],
        latestReadinessScore: Int? = nil
    ) -> [PeriodizationResult] {
        let now = Date()
        return goals
            .filter { !$0.isCompleted && now < $0.targetDate }
            .compactMap { evaluate(goal: $0, activities: activities, latestReadinessScore: latestReadinessScore) }
            .sorted { !$0.isOnTrack && $1.isOnTrack }
    }

    // MARK: - Intent Modifier Builder

    /// Bouwt een IntentModifier op basis van de intentie, het format en de actuele VibeScore van het doel.
    static func buildIntentModifier(
        goal: FitnessGoal,
        phase: TrainingPhase,
        readinessScore: Int?
    ) -> IntentModifier {
        let vibeScore = readinessScore ?? 70          // onbekend → neutraal
        let isHighReadiness = vibeScore > 65
        let isMultiDay      = goal.resolvedFormat == .multiDayStage

        // Completion-modus: aerobe basis, TENZIJ er een stretchGoalTime is én VibeScore hoog genoeg is.
        // Dan staat één temposessie per week toe — sporter wil finishen maar heeft ook een tijdsdoel.
        if goal.resolvedIntent == .completion {
            let hasStretchWithReadiness = goal.stretchGoalTime != nil && isHighReadiness
            return IntentModifier(
                weeklyTrimpMultiplier: 0.90,
                allowHighIntensity: hasStretchWithReadiness,
                backToBackEmphasis: isMultiDay,
                stretchPaceAllowed: hasStretchWithReadiness,
                coachingInstruction: completionInstruction(goal: goal, vibeScore: vibeScore, isMultiDay: isMultiDay, stretchAllowed: hasStretchWithReadiness)
            )
        }

        // Peak Performance-modus: intensiteit toegestaan als VibeScore hoog genoeg is
        let stretchPaceAllowed = isHighReadiness && goal.stretchGoalTime != nil && phase != .tapering
        let allowHighIntensity = isHighReadiness && phase != .tapering

        return IntentModifier(
            weeklyTrimpMultiplier: isMultiDay ? 0.95 : 1.0,
            allowHighIntensity: allowHighIntensity,
            backToBackEmphasis: isMultiDay,
            stretchPaceAllowed: stretchPaceAllowed,
            coachingInstruction: peakPerformanceInstruction(
                goal: goal, vibeScore: vibeScore,
                stretchPaceAllowed: stretchPaceAllowed,
                allowHighIntensity: allowHighIntensity,
                isMultiDay: isMultiDay
            )
        )
    }

    // MARK: - Coaching Instructie Builders

    private static func completionInstruction(goal: FitnessGoal, vibeScore: Int, isMultiDay: Bool, stretchAllowed: Bool) -> String {
        var lines = ["══ DOEL-INTENTIE: UITLOPEN / OVERLEVEN ══"]

        if stretchAllowed, let stretchTime = goal.stretchGoalTime {
            let totalSec = Int(stretchTime)
            let hours    = totalSec / 3600
            let minutes  = (totalSec % 3600) / 60
            let timeStr  = hours > 0 ? "\(hours)u\(String(format: "%02d", minutes))" : "\(minutes) min"
            lines.append("Primaire intentie: FINISHEN — maar er is een doeltijd van \(timeStr) ingesteld.")
            lines.append("VibeScore (\(vibeScore)) is hoog genoeg: Voeg maximaal 1 temposessie per week toe op doelpace. Basis blijft Zone 1-2; tempo is additioneel, niet leidend.")
        } else {
            lines.append("De gebruiker wil dit evenement uitlopen en veilig finishen — géén racestrategie.")
            lines.append("INSTRUCTIE: Prioriteer Zone 1-2 (aerobe basis). GEEN lactaat-intervallen of tempo-blokken.")
            lines.append("Schema-principe: duurvermogen > intensiteit. Lange, rustige trainingen staan centraal.")
        }

        if isMultiDay {
            lines.append("FORMAAT — MEERDAAGSE ETAPPERIT: Verspreid de belasting over opeenvolgende dagen (bijv. Za + Zo back-to-back duurtraining). Verminder hoge intensiteit verder — gewenning aan accumulatievermoeidheid is het primaire doel.")
        }
        if vibeScore < 65 {
            lines.append("⚠️ LAGE VIBE SCORE (\(vibeScore)): Herstel staat deze week voorop. Verlaag volume met 20% en schrap elke intensieve sessie — completion staat op het spel als de sporter uitgeput aan de start staat.")
        }
        return lines.joined(separator: "\n")
    }

    private static func peakPerformanceInstruction(
        goal: FitnessGoal,
        vibeScore: Int,
        stretchPaceAllowed: Bool,
        allowHighIntensity: Bool,
        isMultiDay: Bool
    ) -> String {
        var lines = ["══ DOEL-INTENTIE: MAXIMALE PRESTATIE ══"]

        if isMultiDay {
            lines.append("FORMAAT — MEERDAAGSE ETAPPERIT: Verspreid de zware belasting over opeenvolgende dagen (Za + Zo back-to-back). Verlaag het aantal lactaat-intervallen t.o.v. een eendaagse race — duurvermogen en herstelsnelheid zijn hier doorslaggevend.")
        }

        if !allowHighIntensity {
            lines.append("⚠️ VIBE SCORE (\(vibeScore)) TE LAAG voor hoge intensiteit: Schrap tempo-intervallen en prioriteer herstel deze week. De prestatie wordt gered door nu rust te nemen, niet door door te bijten.")
        }

        if stretchPaceAllowed, let stretchTime = goal.stretchGoalTime {
            let totalSec = Int(stretchTime)
            let hours    = totalSec / 3600
            let minutes  = (totalSec % 3600) / 60
            let timeStr  = hours > 0 ? "\(hours)u\(String(format: "%02d", minutes))" : "\(minutes) min"
            lines.append("✅ DOELTIJD \(timeStr) — VibeScore (\(vibeScore)) is hoog genoeg: Voeg 1 temposessie per week toe op doelsnelheid. Bereken de doelpace en benoem dit expliciet in het schema ('tempo-blok op doelsnelheid').")
        } else if let stretchTime = goal.stretchGoalTime {
            let totalSec = Int(stretchTime)
            let hours    = totalSec / 3600
            let minutes  = (totalSec % 3600) / 60
            let timeStr  = hours > 0 ? "\(hours)u\(String(format: "%02d", minutes))" : "\(minutes) min"
            lines.append("🔴 DOELTIJD \(timeStr) ingesteld maar VibeScore (\(vibeScore)) is te laag of taperfase actief: Val terug op PURE DUURTRAINING. Geen tempo-blokken op doelsnelheid — eerst herstellen, dan presteren.")
        }

        return lines.joined(separator: "\n")
    }
}
