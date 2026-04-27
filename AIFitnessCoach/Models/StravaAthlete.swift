import Foundation

// MARK: - Epic 44 Story 44.3: StravaAthlete
//
// Minimale DTO voor de geauthenticeerde Strava-atleet. We hebben alleen FTP
// nodig om in `UserPhysicalProfile.ftp` te zetten — andere velden van het
// athlete-profiel (naam, locatie, profielfoto) laten we expres weg om geen
// extra PII binnen te halen die we niet gebruiken.
//
// Strava-API: `GET /api/v3/athlete` returnt een `DetailedAthlete` met optioneel
// `ftp: Int?`. Het veld kan ontbreken als de gebruiker 'm niet heeft ingevuld,
// vandaar `decodeIfPresent` + optionele property.

struct StravaAthlete: Codable, Equatable {
    /// Functional Threshold Power in watt. `nil` wanneer de gebruiker geen FTP
    /// in z'n Strava-profiel heeft ingevoerd.
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
