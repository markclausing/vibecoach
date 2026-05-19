import Foundation

/// Bevat alle verwachte fouten tijdens het ophalen van externe fitness data
enum FitnessDataError: Error, LocalizedError, Equatable {
    case missingToken
    case unauthorized // 401
    case rateLimited(retryAfter: Date) // 429 — Epic #51-F2
    case networkError(String)
    case decodingError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Geen Strava-token gevonden in Instellingen."
        case .unauthorized:
            return "Het Strava-token is ongeldig of verlopen (401 Unauthorized)."
        case .rateLimited(let retryAfter):
            let f = DateFormatter()
            f.locale = Locale(identifier: "nl_NL")
            f.dateFormat = "HH:mm"
            return "Strava-limiet bereikt — hervat om \(f.string(from: retryAfter))."
        case .networkError(let message):
            return "Netwerkfout: \(message)"
        case .decodingError(let message):
            return "Kon data niet verwerken: \(message)"
        case .invalidResponse:
            return "Ongeldig antwoord van de server."
        }
    }
}
