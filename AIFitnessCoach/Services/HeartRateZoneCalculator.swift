import Foundation

// MARK: - Epic 44 Story 44.1: HeartRateZoneCalculator
//
// Pure-Swift derivation of 5 heart-rate zones from a few personal thresholds.
// Two strategies:
//   • **Karvonen** (HR-Reserve method): zones as a percentage of (max − rest) + rest.
//     Requires both max HR and resting HR.
//   • **Friel** (LTHR method): zones as a percentage of the lactate threshold HR.
//     Requires only LTHR — considered more accurate by many coaches
//     because LTHR is a functional measurement, while max HR is often estimated.
//
// Both return `[HeartRateZone]` with the same 5-zone naming. The UI and
// detector can choose which strategy to use based on what is
// available in the profile — Friel is preferred when LTHR is known.

struct HeartRateZone: Equatable {
    /// 1-based index, 1 = recovery, 5 = VO2max. Stable for UI bindings.
    let index: Int
    /// Short name (English — Swift convention). The UI may render in Dutch.
    let name: String
    /// Lower and upper bound in BPM (rounded to whole BPM).
    let lowerBPM: Int
    let upperBPM: Int
}

enum HeartRateZoneCalculator {

    /// Karvonen formula: `zoneBPM = restHR + (maxHR − restHR) × percentage`.
    /// Joe Friel / TrainingPeaks 5-zone percentages:
    ///   Z1 Recovery   50–60% HRR
    ///   Z2 Endurance  60–70% HRR
    ///   Z3 Tempo      70–80% HRR
    ///   Z4 Threshold  80–90% HRR
    ///   Z5 VO2max     90–100% HRR
    /// - Parameters:
    ///   - maxHR: Maximum heart rate in BPM. Must be > restHR or you get an empty array.
    ///   - restingHR: Resting heart rate in BPM. Must be >= 0 and < maxHR.
    /// - Returns: Five zones sorted low to high. Empty array on invalid input.
    static func karvonen(maxHR: Double, restingHR: Double) -> [HeartRateZone] {
        let hrr = maxHR - restingHR
        guard maxHR > 0, restingHR >= 0, hrr > 0 else { return [] }
        let percentages: [(name: String, low: Double, high: Double)] = [
            ("Recovery", 0.50, 0.60),
            ("Endurance", 0.60, 0.70),
            ("Tempo", 0.70, 0.80),
            ("Threshold", 0.80, 0.90),
            ("VO2max", 0.90, 1.00)
        ]
        return percentages.enumerated().map { (i, zone) in
            let lower = restingHR + hrr * zone.low
            let upper = restingHR + hrr * zone.high
            return HeartRateZone(
                index: i + 1,
                name: zone.name,
                lowerBPM: Int(lower.rounded()),
                upperBPM: Int(upper.rounded())
            )
        }
    }

    /// Friel-LTHR formula: zones as a percentage of the lactate threshold HR.
    /// Cycling variant (running zones differ slightly, but the difference is 1-2 BPM
    /// and is negligible for our pattern-detector calibration).
    ///   Z1 Recovery   <81% LTHR
    ///   Z2 Endurance  81–89% LTHR
    ///   Z3 Tempo      90–93% LTHR
    ///   Z4 Threshold  94–99% LTHR
    ///   Z5 VO2max     ≥100% LTHR (upper bound conservatively at 110% LTHR)
    /// - Parameter lactateThresholdHR: LTHR in BPM (typically 85–90% of maxHR).
    /// - Returns: Five zones. Empty array on invalid input.
    static func friel(lactateThresholdHR: Double) -> [HeartRateZone] {
        guard lactateThresholdHR > 0 else { return [] }
        // The bottom of Z1 must not drop below the typical resting HR (60); we start at 50%
        // of LTHR as a pragmatic lower bound. The UI can always override this with the
        // actual resting HR from the profile if known.
        let percentages: [(name: String, low: Double, high: Double)] = [
            ("Recovery", 0.50, 0.81),
            ("Endurance", 0.81, 0.90),
            ("Tempo", 0.90, 0.94),
            ("Threshold", 0.94, 1.00),
            ("VO2max", 1.00, 1.10)
        ]
        return percentages.enumerated().map { (i, zone) in
            let lower = lactateThresholdHR * zone.low
            let upper = lactateThresholdHR * zone.high
            return HeartRateZone(
                index: i + 1,
                name: zone.name,
                lowerBPM: Int(lower.rounded()),
                upperBPM: Int(upper.rounded())
            )
        }
    }

    /// Returns the zone (1-5) a given BPM value falls into based on
    /// an already-computed zone set. For BPM below Z1 returns 0; above Z5 returns 6.
    /// Handy for `WorkoutPatternDetector` gates ("only measure in Z2/Z3").
    static func zoneIndex(for bpm: Double, in zones: [HeartRateZone]) -> Int {
        guard !zones.isEmpty else { return 0 }
        if bpm < Double(zones[0].lowerBPM) { return 0 }
        for zone in zones where bpm <= Double(zone.upperBPM) {
            return zone.index
        }
        return zones.count + 1
    }
}
