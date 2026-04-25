import Foundation

// MARK: - Epic 32 Story 32.2: WorkoutAnalysisHelpers
//
// Pure-Swift helpers die `WorkoutAnalysisView` testbaar houden zonder SwiftUI/Charts in te trekken.

/// Welke metric in de onderste chart wordt getoond.
/// Cyclisten kijken vooral naar power; hardlopers naar snelheid.
enum SecondarySeries: Equatable {
    case speed
    case power
    case none
}

enum WorkoutAnalysisHelpers {

    /// Vindt de sample met de timestamp die het dichtst bij `targetDate` ligt.
    /// `samples` mag in willekeurige volgorde aangeleverd worden — we doen O(n) lineaire scan
    /// (voor ~720 samples per workout is dat ruim binnen één frame op 60fps).
    static func nearestSample<S>(at targetDate: Date,
                                 in samples: [S],
                                 timestamp: (S) -> Date) -> S? {
        guard let first = samples.first else { return nil }

        var best = first
        var bestDelta = abs(timestamp(first).timeIntervalSince(targetDate))

        for sample in samples.dropFirst() {
            let delta = abs(timestamp(sample).timeIntervalSince(targetDate))
            if delta < bestDelta {
                bestDelta = delta
                best = sample
            }
        }
        return best
    }

    /// Bepaalt welke metric de secondary chart toont op basis van sport-categorie en
    /// daadwerkelijk beschikbare meetdata. Voorkeur:
    ///   • Cycling + power-data → power
    ///   • Anders met speed-data → speed
    ///   • Anders met power-data → power
    ///   • Anders → none (chart wordt verborgen)
    static func chooseSecondarySeries(sportCategory: String?,
                                      hasSpeed: Bool,
                                      hasPower: Bool) -> SecondarySeries {
        if sportCategory == "cycling", hasPower {
            return .power
        }
        if hasSpeed {
            return .speed
        }
        if hasPower {
            return .power
        }
        return .none
    }
}
