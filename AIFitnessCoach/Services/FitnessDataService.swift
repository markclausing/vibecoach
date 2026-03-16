import Foundation

/// Verantwoordelijk voor het ophalen van sport- en activiteitsdata van externe API's (bijv. Strava of Intervals.icu).
actor FitnessDataService {

    private let tokenStore: TokenStore
    private let session: NetworkSession

    // Dependency Injection voor de opslag van tokens en netwerksessies
    init(tokenStore: TokenStore = KeychainService.shared, session: NetworkSession = URLSession.shared) {
        self.tokenStore = tokenStore
        self.session = session
    }

    /// Haalt de meest recente activiteit van de gebruiker op via de Strava API.
    /// - Returns: Het laatst voltooide `StravaActivity` object.
    /// - Throws: `FitnessDataError` als er iets misgaat (bijv. geen token, 401, of network issue).
    func fetchLatestActivity() async throws -> StravaActivity? {
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
}
