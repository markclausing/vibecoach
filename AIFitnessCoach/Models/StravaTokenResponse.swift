import Foundation

/// Representation of the successful JSON response after refreshing a Strava token (OAuth2).
struct StravaTokenResponse: Codable {
    let access_token: String
    let refresh_token: String
    let expires_at: Int
}
