import Foundation

// MARK: - Injury Impact Matrix

/// Computes the extra physiological load based on active injury preferences and sport choice.
/// Used in the ACWR banner status on the dashboard and for AI-prompt injection.
struct InjuryImpactMatrix {

    /// Returns the penalty multiplier: how much harder the workout lands given the active injury/injuries.
    /// - Parameters:
    ///   - sport: The SportCategory of the last workout.
    ///   - preferences: Active user preferences (including injuries/complaints).
    /// - Returns: 1.0 = no impact, 1.4 = 40% extra physiological load.
    static func penaltyMultiplier(for sport: SportCategory, given preferences: [UserPreference]) -> Double {
        var maxMultiplier = 1.0
        for pref in preferences {
            let text = pref.preferenceText.lowercased()
            // Calf/shin: high impact when running (1.4x), slightly elevated when walking (1.1x)
            if text.contains("kuit") || text.contains("scheen") || text.contains("shin") {
                switch sport {
                case .running: maxMultiplier = max(maxMultiplier, 1.4)
                case .walking: maxMultiplier = max(maxMultiplier, 1.1)
                default: break
                }
            }
            // Back: moderate impact when running and strength training (1.2x), slight when cycling (1.1x)
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

    /// Returns a concise description of the injury relevant to the given sport.
    /// Used in the banner text to communicate contextually.
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
