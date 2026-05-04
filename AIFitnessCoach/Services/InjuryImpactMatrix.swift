import Foundation

// MARK: - Blessure-Impact Matrix

/// Berekent de extra fysiologische belasting op basis van actieve blessure-voorkeuren en sportkeuze.
/// Wordt gebruikt in de ACWR-bannerstatus op het dashboard en voor AI-prompt injectie.
struct InjuryImpactMatrix {

    /// Retourneert de penalty-multiplier: hoeveel zwaarder de workout aankomt gezien de actieve blessure(s).
    /// - Parameters:
    ///   - sport: De SportCategory van de laatste workout.
    ///   - preferences: Actieve gebruikersvoorkeuren (inclusief blessures/klachten).
    /// - Returns: 1.0 = geen impact, 1.4 = 40% extra fysiologische belasting.
    static func penaltyMultiplier(for sport: SportCategory, given preferences: [UserPreference]) -> Double {
        var maxMultiplier = 1.0
        for pref in preferences {
            let text = pref.preferenceText.lowercased()
            // Kuit/Scheen: hoge impact bij hardlopen (1.4x), licht verhoogd bij wandelen (1.1x)
            if text.contains("kuit") || text.contains("scheen") || text.contains("shin") {
                switch sport {
                case .running: maxMultiplier = max(maxMultiplier, 1.4)
                case .walking: maxMultiplier = max(maxMultiplier, 1.1)
                default: break
                }
            }
            // Rug: matige impact bij hardlopen en krachttraining (1.2x), licht bij fietsen (1.1x)
            if text.contains("rug") || text.contains("rugpijn") || text.contains("back pain") {
                switch sport {
                case .running, .strength: maxMultiplier = max(maxMultiplier, 1.2)
                case .cycling: maxMultiplier = max(maxMultiplier, 1.1)
                default: break
                }
            }
        }
        return maxMultiplier
    }

    /// Geeft een beknopte omschrijving van de blessure die relevant is voor de gegeven sport.
    /// Wordt gebruikt in de bannertekst om contextueel te communiceren.
    static func injuryDescription(for sport: SportCategory, given preferences: [UserPreference]) -> String? {
        for pref in preferences {
            let text = pref.preferenceText.lowercased()
            if (text.contains("kuit") || text.contains("scheen")) && (sport == .running || sport == .walking) {
                return "kuitklachten"
            }
            if (text.contains("rug") || text.contains("rugpijn")) && (sport == .running || sport == .cycling || sport == .strength) {
                return "rugklachten"
            }
        }
        return nil
    }
}
