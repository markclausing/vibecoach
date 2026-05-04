import Foundation

// MARK: - Epic 14: Readiness Score Algoritme

/// Berekent de dagelijkse Vibe/Readiness Score (0-100) op basis van slaap en HRV.
///
/// **Slaap (50% weging):**
/// - 8+ uur → 100 punten
/// - 5 uur of minder → 0 punten
/// - Lineair daartussen (bijv. 6.5 uur ≈ 50 punten)
///
/// **HRV (50% weging):**
/// - Gelijk aan of hoger dan 7-daagse baseline → 100 punten
/// - Meer dan 20% onder de baseline → 0 punten (rode vlag: overtraining / ziekte)
/// - Lineair daartussen
struct ReadinessCalculator {

    /// Bereken de Vibe Score.
    /// - Parameters:
    ///   - sleepHours: Daadwerkelijke slaaptijd afgelopen nacht in uren.
    ///   - hrv: Gemiddelde HRV van afgelopen nacht in ms.
    ///   - hrvBaseline: Gemiddelde HRV van de afgelopen 7 dagen (persoonlijke baseline) in ms.
    ///   - deepSleepRatio: Optioneel — verhouding diepe slaap t.o.v. totaal (0.0–1.0).
    ///     Nil = ouder device of geen stage-data → geen strafpunt toegepast.
    ///     < 0.10 → -15 punten | 0.10–0.15 → -8 punten | ≥ 0.15 → geen straf.
    /// - Returns: Score van 0 t/m 100.
    static func calculate(sleepHours: Double, hrv: Double, hrvBaseline: Double,
                          deepSleepRatio: Double? = nil) -> Int {
        // Slaapscore: lineair van 5 uur (0 punten) tot 8 uur (100 punten)
        let sleepScore = min(1.0, max(0.0, (sleepHours - 5.0) / 3.0)) * 100.0

        // HRV-score: vergelijken met persoonlijke baseline
        // Ondergrens = 80% van baseline (meer dan 20% onder = volledige rode vlag)
        let hrvLowerBound = hrvBaseline * 0.80
        let hrvScore: Double
        if hrv >= hrvBaseline {
            hrvScore = 100.0
        } else if hrv <= hrvLowerBound {
            hrvScore = 0.0
        } else {
            hrvScore = ((hrv - hrvLowerBound) / (hrvBaseline - hrvLowerBound)) * 100.0
        }

        var finalScore = (sleepScore + hrvScore) / 2.0

        // Strafpunt bij onvoldoende diepe slaap — herstel is minder effectief ondanks voldoende uren.
        // Alleen toegepast als er stage-specifieke data beschikbaar is.
        if let ratio = deepSleepRatio {
            if ratio < 0.10 {
                finalScore -= 15.0
            } else if ratio < 0.15 {
                finalScore -= 8.0
            }
        }

        return Int(min(100, max(0, finalScore)).rounded())
    }
}
