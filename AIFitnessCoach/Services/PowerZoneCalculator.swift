import Foundation

// MARK: - Epic 44 Story 44.1: PowerZoneCalculator
//
// Pure-Swift derivation of 7 power zones from FTP per Andy Coggan's
// classic 7-zone model (TrainingPeaks norm). FTP = Functional Threshold
// Power, the highest power a rider can sustain for ~1 hour.
//
// The model used by nearly all modern cycling-training apps (Zwift, TrainerRoad,
// Strava). Our `WorkoutPatternDetector` (44.5) uses this to classify
// power streams into zones — analogous to the HR zones.

struct PowerZone: Equatable {
    /// 1-based index, 1 = active recovery, 7 = neuromuscular.
    let index: Int
    /// Short English name — the UI may render localised labels.
    let name: String
    /// Lower and upper bound in watts. Z7 has no upper bound (sprint power is open-ended).
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
    ///   Z7 Neuromuscular Power 151%+ FTP (no upper bound)
    /// - Parameter ftp: Functional Threshold Power in watts.
    /// - Returns: Seven zones. Empty array for invalid FTP (≤ 0).
    static func coggan(ftp: Double) -> [PowerZone] {
        guard ftp > 0 else { return [] }
        // Coggan's percentages — lower and upper bound per zone. Below Z1 may fall to 0 W
        // (coasting/freewheel counts as active recovery / pure rest).
        let definitions: [(name: String, low: Double, high: Double?)] = [
            ("Active Recovery", 0.00, 0.55),
            ("Endurance", 0.56, 0.75),
            ("Tempo", 0.76, 0.90),
            ("Lactate Threshold", 0.91, 1.05),
            ("VO2max", 1.06, 1.20),
            ("Anaerobic Capacity", 1.21, 1.50),
            ("Neuromuscular Power", 1.51, nil)
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

    /// Returns the zone (1-7) a given watt value falls into based on
    /// an already-computed zone set. Below Z1 returns 0. Z7 is always the maximum
    /// because it has no upper bound.
    static func zoneIndex(for watts: Double, in zones: [PowerZone]) -> Int {
        guard !zones.isEmpty else { return 0 }
        if watts < Double(zones[0].lowerWatts) { return 0 }
        for zone in zones {
            if let upper = zone.upperWatts, watts <= Double(upper) {
                return zone.index
            }
            if zone.upperWatts == nil {
                // Top zone (Z7) — everything above `lowerWatts` falls here.
                return zone.index
            }
        }
        return zones.count
    }
}
