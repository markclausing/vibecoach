import Foundation

/// Bevat alle verwachte fouten tijdens het ophalen van externe fitness data
enum FitnessDataError: Error, LocalizedError, Equatable {
    case missingToken
    case unauthorized // 401
    case networkError(String)
    case decodingError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Geen Strava-token gevonden in Instellingen."
        case .unauthorized:
            return "Het Strava-token is ongeldig of verlopen (401 Unauthorized)."
        case .networkError(let message):
            return "Netwerkfout: \(message)"
        case .decodingError(let message):
            return "Kon data niet verwerken: \(message)"
        case .invalidResponse:
            return "Ongeldig antwoord van de server."
        }
    }
}
