import Foundation

/// Epic #35 — Haalt de catalogus van ondersteunde Gemini-modellen op bij de
/// Cloudflare Worker (`/ai/models`). Bewust via de Worker en niet direct naar
/// `generativelanguage.googleapis.com` zodat:
///  - we alleen door ons gevalideerde modellen tonen in de UI;
///  - de BYOK-sleutel van de gebruiker niet via een catalogus-call hoeft te reizen.
enum AIModelCatalogError: LocalizedError {
    case invalidURL
    case transport(Error)
    case httpStatus(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ongeldige proxy-URL voor model-catalogus."
        case .transport(let error):
            return "Netwerkfout bij ophalen modellen: \(error.localizedDescription)"
        case .httpStatus(let code):
            return "Proxy gaf statuscode \(code) terug voor /ai/models."
        case .decoding(let error):
            return "Kon model-catalogus niet lezen: \(error.localizedDescription)"
        }
    }
}

final class AIModelCatalogService {
    private let session: NetworkSession
    private let baseURL: String
    private let clientToken: String

    init(
        session: NetworkSession = URLSession.shared,
        baseURL: String = Secrets.stravaProxyBaseURL,
        clientToken: String = Secrets.stravaProxyToken
    ) {
        self.session = session
        self.baseURL = baseURL
        self.clientToken = clientToken
    }

    /// Haalt de catalogus op. Laat de caller zelf beslissen over caching/fallback
    /// (zie `AIModelCatalog.builtInFallback`).
    func fetchCatalog() async throws -> AIModelCatalog {
        guard let url = URL(string: "\(baseURL)/ai/models") else {
            throw AIModelCatalogError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue(clientToken, forHTTPHeaderField: "X-Client-Token")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIModelCatalogError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIModelCatalogError.httpStatus(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(AIModelCatalog.self, from: data)
        } catch {
            throw AIModelCatalogError.decoding(error)
        }
    }
}
