import Foundation

// MARK: - Epic 44 Story 44.3: StravaAthlete
//
// Minimal DTO for the authenticated Strava athlete. We only need FTP
// to set in `UserPhysicalProfile.ftp` — other fields of the
// athlete profile (name, location, profile photo) are deliberately left out so we don't
// pull in extra PII we don't use.
//
// Strava API: `GET /api/v3/athlete` returns a `DetailedAthlete` with optional
// `ftp: Int?`. The field may be missing if the user has not set it,
// hence `decodeIfPresent` + an optional property.

struct StravaAthlete: Codable, Equatable {
    /// Functional Threshold Power in watts. `nil` when the user has not entered
    /// an FTP in their Strava profile.
    let ftp: Int?

    enum CodingKeys: String, CodingKey {
        case ftp
    }

    init(ftp: Int?) {
        self.ftp = ftp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ftp = try c.decodeIfPresent(Int.self, forKey: .ftp)
    }
}
