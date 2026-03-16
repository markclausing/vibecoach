import Foundation

/// Representatie van de succesvolle JSON response na het vernieuwen van een Strava token (OAuth2).
struct StravaTokenResponse: Codable {
    let access_token: String
    let refresh_token: String
    let expires_at: Int
}
