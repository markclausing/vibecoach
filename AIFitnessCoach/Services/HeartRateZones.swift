import Foundation

// MARK: - HeartRateZones
//
// Helper voor het afleiden van een schatting van de maximale hartslag op basis van
// leeftijd. Gebruikt door `SessionClassifier` voor zone-berekeningen wanneer er geen
// gemeten max-HR beschikbaar is. Voorkeur in productie: dateOfBirth uit HealthKit
// (Tanaka-formule, accurater dan 220-age). Bij ontbrekende geboortedatum: 190 als
// pragmatische volwassen-default — niet exact, maar beter dan crashen.

enum HeartRateZones {

    /// Default fallback bij volledig onbekende leeftijd. Realistische volwassen-mannen-default.
    /// Bewust conservatief gekozen — ondergrens van Tanaka voor 25-jarigen (190 bpm).
    static let defaultMaxHeartRate: Double = 190

    /// Schat de max-HR via de Tanaka-formule: `208 - 0.7 × leeftijd`. Moderner en
    /// accurater dan de klassieke `220 - leeftijd`-formule (vooral voor 40+ atleten,
    /// waar 220-age de max systematisch onderschat).
    /// - Parameters:
    ///   - birthDate: Geboortedatum uit HealthKit-`dateOfBirth`-characteristic.
    ///   - now: Referentiedatum voor leeftijdsberekening (injecteerbaar voor tests).
    /// - Returns: Geschatte max-HR. Geeft `defaultMaxHeartRate` terug bij ongeldige input.
    static func estimatedMaxHeartRate(birthDate: Date?, now: Date = Date()) -> Double {
        guard let birthDate else { return defaultMaxHeartRate }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: birthDate, to: now)
        guard let years = components.year, years > 0, years < 120 else {
            // Geen redelijke leeftijd te bepalen — fallback.
            return defaultMaxHeartRate
        }

        // Tanaka: 208 − 0.7 × age
        return 208.0 - 0.7 * Double(years)
    }
}
