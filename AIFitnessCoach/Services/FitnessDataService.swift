import Foundation
import os

/// Verantwoordelijk voor het ophalen van sport- en activiteitsdata van externe API's (bijv. Strava of Intervals.icu).
actor FitnessDataService {

    // Logger leeft centraal in `AppLoggers.fitnessDataService` — gebruik `.private`
    // voor user-tokens en sample-waardes (HRV, TRIMP) zodat sysdiagnose-logs in
    // release-builds geen identificerende data lekken.

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
            AppLoggers.fitnessDataService.info("Strava-token is verlopen of verloopt binnenkort — vernieuwen via proxy")

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

                AppLoggers.fitnessDataService.info("Strava-token succesvol vernieuwd")
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
