import Foundation
import SwiftData

// MARK: - Epic 18: Symptoom & Blessure Intelligentie

/// Lichaamsdelen waarvoor de gebruiker dagelijks een pijnscores kan invoeren.
enum BodyArea: String, CaseIterable, Codable {
    case calf      = "Kuit"
    case hand      = "Hand"
    case back      = "Rug"
    case knee      = "Knie"
    case shoulder  = "Schouder"
    case ankle     = "Enkel"

    /// Sleutelwoorden die in UserPreference-teksten duiden op een klacht in dit gebied.
    var injuryKeywords: [String] {
        switch self {
        case .calf:     return ["kuit", "scheen", "shin"]
        case .hand:     return ["hand", "pols", "vinger"]
        case .back:     return ["rug", "rugpijn", "back pain"]
        case .knee:     return ["knie"]
        case .shoulder: return ["schouder"]
        case .ankle:    return ["enkel"]
        }
    }

    var icon: String {
        switch self {
        case .calf:     return "figure.run"
        case .hand:     return "hand.raised.fill"
        case .back:     return "figure.stand"
        case .knee:     return "figure.walk"
        case .shoulder: return "figure.arms.open"
        case .ankle:    return "figure.run.circle"
        }
    }

    /// Geeft een leesbare ernst-omschrijving voor een gegeven score.
    static func severityLabel(_ score: Int) -> String {
        switch score {
        case 0:     return "Geen pijn"
        case 1...3: return "Licht"
        case 4...6: return "Matig"
        case 7...9: return "Zwaar"
        default:    return "Ernstig"
        }
    }
}

/// Dagelijkse pijnscore voor één lichaamsdeel. Eén record per gebied per dag (upsert-patroon).
///
/// **Schema V2 wijziging:** `bodyAreaRaw: String` → `bodyArea: BodyArea` (type-veilige enum).
/// `@Attribute(originalName:)` koppelt het aan de oude V1-kolom zodat SwiftData de bestaande
/// rawValue-strings ("Kuit", "Knie", …) onveranderd kan inlezen — `BodyArea` is `String`-backed
/// dus de onderliggende opslag blijft identiek.
@Model
final class Symptom {
    @Attribute(.unique) var id: UUID
    @Attribute(originalName: "bodyAreaRaw") var bodyArea: BodyArea
    var severity: Int            // 0 (geen pijn) t/m 10 (ernstig)
    var date: Date               // Genormaliseerd naar startOfDay

    init(bodyArea: BodyArea, severity: Int, date: Date = Date()) {
        self.id = UUID()
        self.bodyArea = bodyArea
        self.severity = min(10, max(0, severity))
        self.date = Calendar.current.startOfDay(for: date)
    }
}
