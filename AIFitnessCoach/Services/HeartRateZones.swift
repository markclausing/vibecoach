import Foundation

// MARK: - HeartRateZones
//
// Helper for deriving an estimate of the maximum heart rate based on
// age. Used by `SessionClassifier` for zone calculations when no
// measured max HR is available. Preference in production: dateOfBirth from HealthKit
// (Tanaka formula, more accurate than 220-age). On a missing birth date: 190 as a
// pragmatic adult default — not exact, but better than crashing.

enum HeartRateZones {

    /// Default fallback for a fully unknown age. Realistic adult-male default.
    /// Deliberately conservative — the lower bound of Tanaka for 25-year-olds (190 bpm).
    static let defaultMaxHeartRate: Double = 190

    /// Estimates max HR via the Tanaka formula: `208 - 0.7 × age`. More modern and
    /// accurate than the classic `220 - age` formula (especially for 40+ athletes,
    /// where 220-age systematically underestimates the max).
    /// - Parameters:
    ///   - birthDate: Birth date from the HealthKit `dateOfBirth` characteristic.
    ///   - now: Reference date for the age calculation (injectable for tests).
    /// - Returns: Estimated max HR. Returns `defaultMaxHeartRate` on invalid input.
    static func estimatedMaxHeartRate(birthDate: Date?, now: Date = Date()) -> Double {
        guard let birthDate else { return defaultMaxHeartRate }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: birthDate, to: now)
        guard let years = components.year, years > 0, years < 120 else {
            // No reasonable age can be determined — fallback.
            return defaultMaxHeartRate
        }

        // Tanaka: 208 − 0.7 × age
        return 208.0 - 0.7 * Double(years)
    }
}
