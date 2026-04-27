import Foundation

// MARK: - Epic 44 Story 44.1: HeartRateZoneCalculator
//
// Pure-Swift afleiding van 5 hartslag-zones uit een paar persoonlijke drempels.
// Twee strategieën:
//   • **Karvonen** (HR-Reserve methode): zones als percentage van (max − rest) + rest.
//     Vereist max-HR én rust-HR.
//   • **Friel** (LTHR-methode): zones als percentage van de lactate threshold HR.
//     Vereist alleen LTHR — wordt door veel coaches als nauwkeuriger beschouwd
//     omdat LTHR een functioneel meetpunt is, terwijl max-HR vaak geschat is.
//
// Beide retourneren `[HeartRateZone]` met dezelfde 5-zone-naming. UI en
// detector kunnen kiezen welke strategie ze gebruiken op basis van wat in het
// profiel beschikbaar is — Friel heeft voorkeur als LTHR bekend is.

struct HeartRateZone: Equatable {
    /// 1-based index, 1 = recovery, 5 = VO2max. Stable voor UI-koppelingen.
    let index: Int
    /// Korte naam (Engels — Swift-conventie). UI mag in het Nederlands renderen.
    let name: String
    /// Onder- en bovengrens in BPM (afgerond op gehele BPM).
    let lowerBPM: Int
    let upperBPM: Int
}

enum HeartRateZoneCalculator {

    /// Karvonen-formule: `zoneBPM = restHR + (maxHR − restHR) × percentage`.
    /// Joe Friel / TrainingPeaks 5-zone percentages:
    ///   Z1 Recovery   50–60% HRR
    ///   Z2 Endurance  60–70% HRR
    ///   Z3 Tempo      70–80% HRR
    ///   Z4 Threshold  80–90% HRR
    ///   Z5 VO2max     90–100% HRR
    /// - Parameters:
    ///   - maxHR: Maximale hartslag in BPM. Moet > restHR zijn anders krijg je een lege array.
    ///   - restingHR: Rusthartslag in BPM. Moet >= 0 en < maxHR zijn.
    /// - Returns: Vijf zones gesorteerd van laag naar hoog. Lege array bij ongeldige input.
    static func karvonen(maxHR: Double, restingHR: Double) -> [HeartRateZone] {
        let hrr = maxHR - restingHR
        guard maxHR > 0, restingHR >= 0, hrr > 0 else { return [] }
        let percentages: [(name: String, low: Double, high: Double)] = [
            ("Recovery",   0.50, 0.60),
            ("Endurance",  0.60, 0.70),
            ("Tempo",      0.70, 0.80),
            ("Threshold",  0.80, 0.90),
            ("VO2max",     0.90, 1.00),
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

    /// Friel-LTHR-formule: zones als percentage van de lactate threshold HR.
    /// Cycling-variant (loop-zones zijn iets anders, maar verschil zit op 1-2 BPM
    /// en is voor onze pattern-detector kalibratie verwaarloosbaar).
    ///   Z1 Recovery   <81% LTHR
    ///   Z2 Endurance  81–89% LTHR
    ///   Z3 Tempo      90–93% LTHR
    ///   Z4 Threshold  94–99% LTHR
    ///   Z5 VO2max     ≥100% LTHR (bovengrens conservatief op 110% LTHR)
    /// - Parameter lactateThresholdHR: LTHR in BPM (typisch 85–90% van maxHR).
    /// - Returns: Vijf zones. Lege array bij ongeldige input.
    static func friel(lactateThresholdHR: Double) -> [HeartRateZone] {
        guard lactateThresholdHR > 0 else { return [] }
        // Onderkant Z1 mag niet onder de typische rust-HR (60) zakken; we beginnen bij 50%
        // van LTHR als pragmatische ondergrens. UI kan dit altijd overschrijven met de
        // werkelijke rust-HR uit het profiel als die bekend is.
        let percentages: [(name: String, low: Double, high: Double)] = [
            ("Recovery",   0.50, 0.81),
            ("Endurance",  0.81, 0.90),
            ("Tempo",      0.90, 0.94),
            ("Threshold",  0.94, 1.00),
            ("VO2max",     1.00, 1.10),
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

    /// Geeft de zone (1-5) terug waarin een gegeven BPM-waarde valt op basis
    /// van een al-berekende zone-set. Voor BPM onder Z1 returnt 0; boven Z5 returnt 6.
    /// Handig voor `WorkoutPatternDetector`-gates ("alleen meten in Z2/Z3").
    static func zoneIndex(for bpm: Double, in zones: [HeartRateZone]) -> Int {
        guard !zones.isEmpty else { return 0 }
        if bpm < Double(zones[0].lowerBPM) { return 0 }
        for zone in zones {
            if bpm <= Double(zone.upperBPM) { return zone.index }
        }
        return zones.count + 1
    }
}
