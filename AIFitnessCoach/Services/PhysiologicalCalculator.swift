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

        let trimp = durationInMinutes * hrDelta * 0.64 * exp(1.92 * hrDelta)

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
}
