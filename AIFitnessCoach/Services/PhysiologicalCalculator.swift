import Foundation

protocol PhysiologicalCalculatorProtocol {
    /// Computes the Training Stress Score (TRIMP method) based on Banister.
    /// - Parameters:
    ///   - durationInSeconds: Duration of the activity in seconds.
    ///   - averageHeartRate: Average heart rate during the activity.
    ///   - maxHeartRate: The user's maximum heart rate.
    ///   - restingHeartRate: The user's resting heart rate.
    /// - Returns: The computed TRIMP score.
    func calculateTSS(durationInSeconds: Double, averageHeartRate: Double, maxHeartRate: Double, restingHeartRate: Double) -> Double

    /// Computes the Cardiac Drift based on the first and second half of the heart-rate samples.
    /// - Parameter samples: The raw heart-rate samples of the workout.
    /// - Returns: The drift percentage, or nil if there is insufficient data.
    func calculateCardiacDrift(samples: [HeartRateSample]) -> Double?
}

class PhysiologicalCalculator: PhysiologicalCalculatorProtocol {

    func calculateTSS(durationInSeconds: Double, averageHeartRate: Double, maxHeartRate: Double, restingHeartRate: Double) -> Double {
        // Avoid dividing by zero or negative values if parameters were entered incorrectly
        let hrr = maxHeartRate - restingHeartRate
        guard hrr > 0 else { return 0.0 }

        let hrDelta = (averageHeartRate - restingHeartRate) / hrr

        // Formula: duration in minutes * hrDelta * 0.64 * e^(1.92 * hrDelta)
        let durationInMinutes = durationInSeconds / 60.0

        let trimp = Self.banisterTRIMP(durationMinutes: durationInMinutes, normalizedDelta: hrDelta)

        // Make sure we don't return NaN or infinity for odd values
        if trimp.isNaN || trimp.isInfinite || trimp < 0 {
            return 0.0
        }

        return trimp
    }

    func calculateCardiacDrift(samples: [HeartRateSample]) -> Double? {
        // Not yet implemented (placeholder)
        return nil
    }

    // MARK: - Banister TRIMP primitives (Epic 65.1: single home for the formula)

    /// Core Banister TRIMP kernel:
    /// `durationMinutes × normalizedDelta × 0.64 × e^(1.92 × normalizedDelta)`.
    /// This is the *single* site of the Banister coefficients — every TRIMP call
    /// site in the app now routes through here (Epic 65.1 centralisation of four
    /// previously duplicated inline copies). `normalizedDelta` is the heart-rate
    /// reserve fraction `(avgHR − restingHR) / (maxHR − restingHR)`, or a
    /// pre-normalised zone estimate for the explainer/simulation surfaces.
    static func banisterTRIMP(durationMinutes: Double, normalizedDelta: Double) -> Double {
        return durationMinutes * normalizedDelta * 0.64 * exp(1.92 * normalizedDelta)
    }

    /// Basic TRIMP fallback used during sync when only average HR is available (no
    /// full max/resting HR profile). With avgHR > 100 bpm: Banister with a fixed
    /// resting HR of 60 and max HR of 190. Otherwise a conservative Zone-2 estimate
    /// of 1.5 TRIMP per minute. Pure function — reproduces the inline fallbacks that
    /// previously lived in the HealthKit/Strava sync paths, byte-for-byte.
    static func basicFallbackTRIMP(durationSec: Double, avgHR: Double?) -> Double {
        let durationMinutes = durationSec / 60.0
        if let hr = avgHR, hr > 100 {
            let normalizedDelta = (hr - 60.0) / (190.0 - 60.0)
            return banisterTRIMP(durationMinutes: durationMinutes, normalizedDelta: normalizedDelta)
        }
        return durationMinutes * 1.5
    }
}
