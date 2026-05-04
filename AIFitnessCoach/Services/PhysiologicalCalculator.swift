import Foundation

protocol PhysiologicalCalculatorProtocol {
    /// Berekent de Training Stress Score (TRIMP methode) gebaseerd op Banister.
    /// - Parameters:
    ///   - durationInSeconds: Duur van de activiteit in seconden.
    ///   - averageHeartRate: Gemiddelde hartslag tijdens de activiteit.
    ///   - maxHeartRate: De maximale hartslag van de gebruiker.
    ///   - restingHeartRate: De rusthartslag van de gebruiker.
    /// - Returns: De berekende TRIMP score.
    func calculateTSS(durationInSeconds: Double, averageHeartRate: Double, maxHeartRate: Double, restingHeartRate: Double) -> Double

    /// Berekent de Cardiac Drift op basis van de eerste en tweede helft van de hartslagsamples.
    /// - Parameter samples: De ruwe hartslagsamples van de workout.
    /// - Returns: Het percentage drift, of nil als er onvoldoende data is.
    func calculateCardiacDrift(samples: [HeartRateSample]) -> Double?
}

class PhysiologicalCalculator: PhysiologicalCalculatorProtocol {

    func calculateTSS(durationInSeconds: Double, averageHeartRate: Double, maxHeartRate: Double, restingHeartRate: Double) -> Double {
        // Voorkom delen door nul of negatieve waarden indien parameters onjuist zijn ingevoerd
        let hrr = maxHeartRate - restingHeartRate
        guard hrr > 0 else { return 0.0 }

        let hrDelta = (averageHeartRate - restingHeartRate) / hrr

        // Formule: duration in minuten * hrDelta * 0.64 * e^(1.92 * hrDelta)
        let durationInMinutes = durationInSeconds / 60.0

        let trimp = durationInMinutes * hrDelta * 0.64 * exp(1.92 * hrDelta)

        // Zorg ervoor dat we geen NaN of infinity teruggeven bij vreemde waarden
        if trimp.isNaN || trimp.isInfinite || trimp < 0 {
            return 0.0
        }

        return trimp
    }

    func calculateCardiacDrift(samples: [HeartRateSample]) -> Double? {
        // Nog te implementeren (placeholder)
        return nil
    }
}
