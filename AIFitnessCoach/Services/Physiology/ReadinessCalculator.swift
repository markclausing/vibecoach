import Foundation

// MARK: - Epic 14: Readiness Score Algorithm

/// Computes the daily Vibe/Readiness Score (0-100) based on sleep and HRV.
///
/// **Sleep (50% weight):**
/// - 8+ hours → 100 points
/// - 5 hours or fewer → 0 points
/// - Linear in between (e.g. 6.5 hours ≈ 50 points)
///
/// **HRV (50% weight):**
/// - Equal to or higher than the 7-day baseline → 100 points
/// - More than 20% below the baseline → 0 points (red flag: overtraining / illness)
/// - Linear in between
struct ReadinessCalculator {

    /// Compute the Vibe Score.
    /// - Parameters:
    ///   - sleepHours: Actual sleep time last night in hours.
    ///   - hrv: Average HRV of last night in ms.
    ///   - hrvBaseline: Average HRV over the past 7 days (personal baseline) in ms.
    ///   - deepSleepRatio: Optional — ratio of deep sleep to total (0.0–1.0).
    ///     Nil = older device or no stage data → no penalty applied.
    ///     < 0.10 → -15 points | 0.10–0.15 → -8 points | ≥ 0.15 → no penalty.
    /// - Returns: A score from 0 to 100.
    static func calculate(sleepHours: Double, hrv: Double, hrvBaseline: Double,
                          deepSleepRatio: Double? = nil) -> Int {
        // Sleep score: linear from 5 hours (0 points) to 8 hours (100 points)
        let sleepScore = min(1.0, max(0.0, (sleepHours - 5.0) / 3.0)) * 100.0

        // HRV score: compared with the personal baseline
        // Lower bound = 80% of baseline (more than 20% below = full red flag)
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

        // Penalty for insufficient deep sleep — recovery is less effective despite enough hours.
        // Only applied when stage-specific data is available.
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
