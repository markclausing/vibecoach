import Foundation

/// Epic #35 — Fetches the catalog of supported Gemini models from the
/// Cloudflare Worker (`/ai/models`). Deliberately via the Worker and not directly to
/// `generativelanguage.googleapis.com` so that:
///  - we only show models we have validated in the UI;
///  - the user's BYOK key does not have to travel via a catalog call.
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

    /// Fetches the catalog. Lets the caller decide on caching/fallback
    /// (see `AIModelCatalog.builtInFallback`).
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
