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
