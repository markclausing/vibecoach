import Foundation

// MARK: - Epic 44 Story 44.1: PowerZoneCalculator
//
// Pure-Swift afleiding van 7 vermogen-zones uit FTP volgens Andy Coggan's
// klassieke 7-zone model (TrainingPeaks-norm). FTP = Functional Threshold
// Power, het hoogste vermogen dat een rijder ~1 uur kan volhouden.
//
// Model gebruikt door bijna alle moderne fietstraining-apps (Zwift, TrainerRoad,
// Strava). Onze `WorkoutPatternDetector` (44.5) gaat dit gebruiken om
// power-streams in zones te classificeren — analoog aan de HR-zones.

struct PowerZone: Equatable {
    /// 1-based index, 1 = active recovery, 7 = neuromuscular.
    let index: Int
    /// Korte Engels naam — UI mag in Nederlandstalige labels renderen.
    let name: String
    /// Onder- en bovengrens in watt. Z7 heeft geen bovengrens (sprintvermogen is open-ended).
    let lowerWatts: Int
    let upperWatts: Int?
}

enum PowerZoneCalculator {

    /// Coggan/TrainingPeaks 7-zone model:
    ///   Z1 Active Recovery     <55% FTP
    ///   Z2 Endurance           56–75% FTP
    ///   Z3 Tempo               76–90% FTP
    ///   Z4 Lactate Threshold   91–105% FTP
    ///   Z5 VO2max              106–120% FTP
    ///   Z6 Anaerobic Capacity  121–150% FTP
    ///   Z7 Neuromuscular Power 151%+ FTP (geen bovengrens)
    /// - Parameter ftp: Functional Threshold Power in watt.
    /// - Returns: Zeven zones. Lege array bij ongeldige FTP (≤ 0).
    static func coggan(ftp: Double) -> [PowerZone] {
        guard ftp > 0 else { return [] }
        // Coggan's percentages — onder- en bovengrens per zone. Onder Z1 mag 0 W vallen
        // (coasting/freewheel telt als active recovery / pure rust).
        let definitions: [(name: String, low: Double, high: Double?)] = [
            ("Active Recovery",     0.00, 0.55),
            ("Endurance",           0.56, 0.75),
            ("Tempo",               0.76, 0.90),
            ("Lactate Threshold",   0.91, 1.05),
            ("VO2max",              1.06, 1.20),
            ("Anaerobic Capacity",  1.21, 1.50),
            ("Neuromuscular Power", 1.51, nil),
        ]
        return definitions.enumerated().map { (i, zone) in
            let lower = ftp * zone.low
            let upper = zone.high.map { ftp * $0 }
            return PowerZone(
                index: i + 1,
                name: zone.name,
                lowerWatts: Int(lower.rounded()),
                upperWatts: upper.map { Int($0.rounded()) }
            )
        }
    }

    /// Geeft de zone (1-7) terug waarin een gegeven watt-waarde valt op basis
    /// van een al-berekende zone-set. Onder Z1 returnt 0. Z7 is altijd het maximum
    /// omdat het geen bovengrens heeft.
    static func zoneIndex(for watts: Double, in zones: [PowerZone]) -> Int {
        guard !zones.isEmpty else { return 0 }
        if watts < Double(zones[0].lowerWatts) { return 0 }
        for zone in zones {
            if let upper = zone.upperWatts, watts <= Double(upper) {
                return zone.index
            }
            if zone.upperWatts == nil {
                // Top-zone (Z7) — alles boven `lowerWatts` valt hier.
                return zone.index
            }
        }
        return zones.count
    }
}
