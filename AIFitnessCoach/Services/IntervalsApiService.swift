import Foundation

/// Service voor communicatie met de Intervals.icu API.
class IntervalsApiService {
    private let session: NetworkSession
    private let tokenStore: TokenStore

    init(session: NetworkSession = URLSession.shared, tokenStore: TokenStore = KeychainService.shared) {
        self.session = session
        self.tokenStore = tokenStore
    }

    /// Haalt diepgaande activiteitsdetails (zoals TSS en hartslagherstel) op via de Intervals.icu API.
    func fetchActivityDetails(athleteId: String, activityId: String) async throws -> IntervalsActivity {
        // Controleer op API token
        guard let token = try tokenStore.getToken(forService: "IntervalsToken"), !token.isEmpty else {
            throw FitnessDataError.missingToken
        }

        let urlString = "https://intervals.icu/api/v1/athlete/\(athleteId)/activities/\(activityId)"
        guard let url = URL(string: urlString) else {
            throw FitnessDataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Basic Authentication (Username is "API_KEY", Password is the token)
        let loginString = "API_KEY:\(token)"
        guard let loginData = loginString.data(using: .utf8) else {
            throw FitnessDataError.serverError("Kon authenticatiedata niet coderen")
        }
        let base64LoginString = loginData.base64EncodedString()
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")

        // Fetch data
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FitnessDataError.serverError("Ongeldige response van Intervals.icu server")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            // Token ongeldig of geen toegang
            try tokenStore.deleteToken(forService: "IntervalsToken")
            throw FitnessDataError.authFailed("Intervals.icu authenticatie mislukt. Controleer je API sleutel.")
        } else if httpResponse.statusCode == 404 {
             throw FitnessDataError.serverError("Activiteit niet gevonden op Intervals.icu.")
        } else if !(200...299).contains(httpResponse.statusCode) {
            throw FitnessDataError.serverError("Server retourneerde status code \(httpResponse.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            let activity = try decoder.decode(IntervalsActivity.self, from: data)
            return activity
        } catch {
            print("IntervalsApiService Decode Error: \(error)")
            throw FitnessDataError.decodeFailed
        }
    }
}
