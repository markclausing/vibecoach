import Foundation
import os

/// Responsible for fetching sport and activity data from external APIs (e.g. Strava or Intervals.icu).
actor FitnessDataService {

    // The logger lives centrally in `AppLoggers.fitnessDataService` — use `.private`
    // for user tokens and sample values (HRV, TRIMP) so sysdiagnose logs in release
    // builds don't leak identifying data.

    private let tokenStore: TokenStore
    private let session: NetworkSession
    private let rateLimitStore: StravaRateLimitStore

    // Dependency injection for token storage, network sessions and the
    // rate-limit cooldown window (Epic #51-F2).
    init(tokenStore: TokenStore = KeychainService.shared,
         session: NetworkSession = URLSession.shared,
         rateLimitStore: StravaRateLimitStore = StravaRateLimitStore()) {
        self.tokenStore = tokenStore
        self.session = session
        self.rateLimitStore = rateLimitStore
    }

    /// Epic 41.3: ensures the caller gets a valid Strava access token.
    /// Calls `refreshTokenIfNeeded()` first so a (near-)expired token is refreshed
    /// before the API call, and throws `.missingToken` if no valid token comes from
    /// the store — this gives every API call one central guard against silent 401s.
    ///
    /// Epic #51-F2: before anything, the Strava rate-limit cooldown is checked.
    /// During an active cooldown no request goes out; this prevents a retry storm
    /// right after launch while the banner still says *"resumes at HH:MM"*.
    @discardableResult
    func ensureValidToken() async throws -> String {
        if let until = rateLimitStore.currentCooldown() {
            throw FitnessDataError.rateLimited(retryAfter: until)
        }
        try await refreshTokenIfNeeded()
        guard let token = try tokenStore.getToken(forService: "StravaToken"), !token.isEmpty else {
            throw FitnessDataError.missingToken
        }
        return token
    }

    /// Checks whether the Strava token has expired (or expires within 5 minutes) and refreshes it via the OAuth2 API.
    func refreshTokenIfNeeded() async throws {
        // Fetch current data
        guard let expiresAtStr = try tokenStore.getToken(forService: "StravaTokenExpiresAt"),
              let expiresAtUnix = Double(expiresAtStr),
              let currentRefreshToken = try tokenStore.getToken(forService: "StravaRefreshToken"), !currentRefreshToken.isEmpty else {
            // If there's no refresh token or expiresAt, we can't refresh. We do nothing and let the request possibly fail on auth.
            return
        }

        let expirationDate = Date(timeIntervalSince1970: expiresAtUnix)

        // Check whether the token expires within the next 5 minutes
        let fiveMinutesFromNow = Date().addingTimeInterval(5 * 60)

        if expirationDate < fiveMinutesFromNow {
            // Token is (near-)expired, refresh!
            AppLoggers.fitnessDataService.info("Strava-token is verlopen of verloopt binnenkort — vernieuwen via proxy")

            // C-01: refresh goes through the server-side proxy. The `client_secret`
            // is no longer present in the app.
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

            _ = try validateHTTPResponse(response)

            // Parse the response
            do {
                let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)

                // Store the new tokens in the Keychain
                try tokenStore.saveToken(tokenResponse.access_token, forService: "StravaToken")
                try tokenStore.saveToken(tokenResponse.refresh_token, forService: "StravaRefreshToken")
                try tokenStore.saveToken(String(tokenResponse.expires_at), forService: "StravaTokenExpiresAt")

                AppLoggers.fitnessDataService.info("Strava-token succesvol vernieuwd")
            } catch {
                throw FitnessDataError.decodingError("Fout bij parsen refresh token response: \(error.localizedDescription)")
            }
        }
    }

    /// Fetches the user's most recent activity via the Strava API.
    /// - Returns: The most recently completed `StravaActivity` object.
    /// - Throws: `FitnessDataError` if something goes wrong (e.g. no token, 401, or network issue).
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

        _ = try validateHTTPResponse(response)

        do {
            let decoder = JSONDecoder()
            let activities = try decoder.decode([StravaActivity].self, from: data)
            return activities.first
        } catch {
            throw FitnessDataError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches a specific activity via the Strava API based on the Activity ID.
    /// This is mainly used when a notification comes in with a specific ID.
    /// - Parameter id: The Strava Activity ID.
    /// - Returns: The corresponding `StravaActivity` object.
    /// - Throws: `FitnessDataError` if something goes wrong.
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

        _ = try validateHTTPResponse(response, statusOverrides: [
            404: .networkError("Activiteit met ID \(id) niet gevonden")
        ])

        do {
            let decoder = JSONDecoder()
            let activity = try decoder.decode(StravaActivity.self, from: data)
            return activity
        } catch {
            throw FitnessDataError.decodingError(error.localizedDescription)
        }
    }

    /// Epic 44 Story 44.3: fetches the FTP of the authenticated Strava athlete
    /// via `/api/v3/athlete`. Strava maintains FTP as part of the athlete profile;
    /// users who already calibrate their FTP there get it back via this endpoint
    /// without us having to estimate it ourselves.
    /// - Returns: FTP in watts, or `nil` if the user hasn't filled in an FTP in
    ///   their profile (Strava then returns either `null` or the missing field).
    /// - Throws: `FitnessDataError` on network, auth or decode error.
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

        _ = try validateHTTPResponse(response)

        do {
            let athlete = try JSONDecoder().decode(StravaAthlete.self, from: data)
            return athlete.ftp
        } catch {
            throw FitnessDataError.decodingError(error.localizedDescription)
        }
    }

    /// Epic 40: Fetches the fine-grained stream data for one Strava activity.
    /// Requests the streams `time`, `watts`, `cadence`, `heartrate` and `velocity_smooth`
    /// as a `key_by_type=true` dictionary. Not all streams are always present
    /// (e.g. `watts` is missing without a power meter) — the caller must handle
    /// optionals correctly via `StravaStreamSet`.
    /// - Parameter activityId: The Strava activity ID.
    /// - Returns: Full `StravaStreamSet` with the available streams.
    /// - Throws: `FitnessDataError` on network error, invalid token or decode failure.
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

        _ = try validateHTTPResponse(response, statusOverrides: [
            404: .networkError("Streams voor activiteit \(activityId) niet gevonden")
        ])

        do {
            return try JSONDecoder().decode(StravaStreamSet.self, from: data)
        } catch {
            throw FitnessDataError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches historical activities via the Strava API, with pagination support.
    /// This is used for computing the long-term athletic profile.
    /// - Parameter monthsBack: How many months we want to look back (e.g. 6).
    /// - Returns: A list of `StravaActivity` objects for the past days.
    /// - Throws: `FitnessDataError` if auth or the network fails.
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

            _ = try validateHTTPResponse(response)

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

    /// - Returns: A list of `StravaActivity` objects.
    /// - Throws: `FitnessDataError` if auth or the network fails.
    func fetchHistoricalActivities(monthsBack: Int) async throws -> [StravaActivity] {
        let stravaToken = try await ensureValidToken()

        // Compute the UNIX timestamps
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

        // Pagination loop (keep going until an empty page comes back)
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

            _ = try validateHTTPResponse(response)

            do {
                let pageActivities = try decoder.decode([StravaActivity].self, from: data)

                if pageActivities.isEmpty {
                    // No more results, we're done
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

    // MARK: - HTTP validation

    /// Central HTTP response validation for all Strava endpoints.
    /// - Detects 401 → `.unauthorized`
    /// - Detects 429 → `.rateLimited(retryAfter:)` + persists the cooldown
    ///   in `StravaRateLimitStore` so subsequent calls (also after app restart)
    ///   are caught immediately via `ensureValidToken()` (Epic #51-F2)
    /// - `statusOverrides` map specific status codes to a custom
    ///   `FitnessDataError` (e.g. 404 → `.networkError("...niet gevonden")`)
    /// - On a successful 2xx response `rateLimitStore` clears itself —
    ///   in combination with `currentCooldown()` the banner stays active exactly
    ///   as long as the server says
    /// - Returns: The `HTTPURLResponse` (for future header inspection)
    private func validateHTTPResponse(
        _ response: URLResponse,
        statusOverrides: [Int: FitnessDataError] = [:]
    ) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw FitnessDataError.invalidResponse
        }

        if http.statusCode == 401 {
            throw FitnessDataError.unauthorized
        }

        if http.statusCode == 429 {
            let retryAfter = StravaRateLimitParser.retryAfter(headers: http.allHeaderFields,
                                                              now: Date())
            rateLimitStore.record(until: retryAfter)
            AppLoggers.fitnessDataService.notice("Strava rate-limit bereikt — hervat om \(retryAfter, privacy: .public)")
            throw FitnessDataError.rateLimited(retryAfter: retryAfter)
        }

        if let override = statusOverrides[http.statusCode] {
            throw override
        }

        if !(200...299).contains(http.statusCode) {
            throw FitnessDataError.networkError("Onverwachte HTTP status code: \(http.statusCode)")
        }

        // Successful response — any earlier cooldown is over.
        rateLimitStore.clear()
        return http
    }
}
