import Foundation
import SwiftData

// MARK: - Epic 18: Symptom & Injury Intelligence

/// Body parts for which the user can enter a daily pain score.
enum BodyArea: String, CaseIterable, Codable {
    case calf      = "Kuit"
    case hand      = "Hand"
    case back      = "Rug"
    case knee      = "Knie"
    case shoulder  = "Schouder"
    case ankle     = "Enkel"

    /// Keywords in UserPreference texts that indicate a complaint in this area.
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

    /// Returns a readable severity description for a given score.
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

/// Daily pain score for one body part. One record per area per day (upsert pattern).
///
/// **Schema V2 change:** `bodyAreaRaw: String` → `bodyArea: BodyArea` (type-safe enum).
/// `@Attribute(originalName:)` links it to the old V1 column so SwiftData can read the existing
/// rawValue strings ("Kuit", "Knie", …) unchanged — `BodyArea` is `String`-backed
/// so the underlying storage stays identical.
@Model
final class Symptom {
    @Attribute(.unique) var id: UUID
    @Attribute(originalName: "bodyAreaRaw") var bodyArea: BodyArea
    var severity: Int            // 0 (no pain) to 10 (severe)
    var date: Date               // Normalised to startOfDay

    init(bodyArea: BodyArea, severity: Int, date: Date = Date()) {
        self.id = UUID()
        self.bodyArea = bodyArea
        self.severity = min(10, max(0, severity))
        self.date = Calendar.current.startOfDay(for: date)
    }
}
