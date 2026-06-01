import Foundation

/// Epic #51-C: pure-Swift validation for the four personal training thresholds
/// the user can enter manually in `TrainingThresholdsSettingsView`.
///
/// Two kinds of checks, both grounded in sports physiology:
///
/// 1. **Range checks** per individual threshold — prevents typos and absurd
///    values (Max HR = 5, FTP = 5000W) that make the zone calculators produce
///    meaningless zones.
/// 2. **Cross checks** across the whole profile — physiological consistency
///    (Max HR must be higher than Resting HR, LTHR sits between Resting and Max).
///    Without these checks `HeartRateZoneCalculator.karvonen()` silently
///    returned an empty zone array and the user only saw "—" in the zone preview.
///
/// AppStorage-free — the caller injects the input as parameters so tests don't
/// have to set up a fresh `UserDefaults(suiteName:)` flow (CLAUDE.md §6).
enum PhysiologicalThresholdValidator {

    /// Valid ranges per threshold — `closed range` in which the value is
    /// physiologically realistic. Outside this range is a **warning** (still
    /// savable with a warning); outside the absolute bound (negative, 0) is an
    /// **error** (blocked).
    enum Range {
        static let maxHR: ClosedRange<Double> = 120...230
        static let restingHR: ClosedRange<Double> = 30...100
        static let lthr: ClosedRange<Double> = 100...200
        static let ftp: ClosedRange<Double> = 75...600

        /// Absolute "absurd values" bound — outside this range we hard-block
        /// because the zone calculator would otherwise produce nonsense zones.
        static let absoluteMaxHR: ClosedRange<Double> = 60...250
        static let absoluteRestingHR: ClosedRange<Double> = 20...120
        static let absoluteLTHR: ClosedRange<Double> = 80...220
        static let absoluteFTP: ClosedRange<Double> = 30...2000
    }

    enum Severity {
        case ok
        case warning
        case error
    }

    struct Issue: Equatable {
        let severity: Severity
        let message: String
    }

    /// The whole profile as input — only values the user actually entered are
    /// `Double`; missing thresholds stay `nil`.
    struct ProfileInput: Equatable {
        var maxHR: Double?
        var restingHR: Double?
        var lthr: Double?
        var ftp: Double?
    }

    enum Kind: String {
        case maxHR
        case restingHR
        case lthr
        case ftp

        fileprivate var label: String {
            switch self {
            case .maxHR: return "Max HR"
            case .restingHR: return "Rust HR"
            case .lthr: return "LTHR"
            case .ftp: return "FTP"
            }
        }

        fileprivate var unit: String {
            switch self {
            case .maxHR, .restingHR, .lthr: return "BPM"
            case .ftp: return "W"
            }
        }
    }

    // MARK: - Per-field validation

    /// Validates one threshold independently of the rest of the profile.
    ///
    /// - `value == nil` → `.ok` (threshold not set = ok, the zone calculators
    ///   use the formula default)
    /// - `value <= 0` or outside the absolute range → `.error`
    /// - `value` outside the realistic range → `.warning`
    /// - otherwise → `.ok`
    static func validateField(_ kind: Kind, value: Double?) -> Issue {
        guard let value else {
            return Issue(severity: .ok, message: "")
        }

        let (range, absolute) = ranges(for: kind)

        if !absolute.contains(value) {
            return Issue(
                severity: .error,
                message: "\(kind.label) buiten realistisch bereik (\(formatRange(absolute, unit: kind.unit)))."
            )
        }
        if !range.contains(value) {
            return Issue(
                severity: .warning,
                message: "Ongewone waarde voor \(kind.label). Typisch: \(formatRange(range, unit: kind.unit))."
            )
        }
        return Issue(severity: .ok, message: "")
    }

    // MARK: - Cross-validation

    /// Validates the full profile for physiological consistency. Specifically:
    /// - Max HR must be > Resting HR (otherwise the Karvonen formula yields a
    ///   negative HRR and the zone calculation fails silently).
    /// - LTHR must be < Max HR (LTHR is by definition sub-maximal).
    /// - LTHR must be > Resting HR (otherwise it isn't a threshold effort).
    /// - FTP stands alone — no cross relation with the HR thresholds.
    ///
    /// Returns an empty array if everything is ok, otherwise one or more `Issue`s.
    static func validateProfile(_ profile: ProfileInput) -> [Issue] {
        var issues: [Issue] = []

        if let max = profile.maxHR, let rest = profile.restingHR {
            if max <= rest {
                issues.append(Issue(
                    severity: .error,
                    message: "Max HR (\(Int(max))) moet hoger zijn dan Rust HR (\(Int(rest)))."
                ))
            }
        }

        if let lthr = profile.lthr, let max = profile.maxHR {
            if lthr >= max {
                issues.append(Issue(
                    severity: .error,
                    message: "LTHR (\(Int(lthr))) moet lager zijn dan Max HR (\(Int(max)))."
                ))
            }
        }

        if let lthr = profile.lthr, let rest = profile.restingHR {
            if lthr <= rest {
                issues.append(Issue(
                    severity: .error,
                    message: "LTHR (\(Int(lthr))) moet hoger zijn dan Rust HR (\(Int(rest)))."
                ))
            }
        }

        return issues
    }

    /// Convenience for the UI: returns `true` if the full profile is safe to
    /// save (no `.error` issues). `.warning` issues do not block.
    static func isSavable(_ profile: ProfileInput) -> Bool {
        validateProfile(profile).allSatisfy { $0.severity != .error }
    }

    // MARK: - Zone-card explanation (C4)

    /// Generates an explanation text for the zones preview card when the zones
    /// cannot be computed. Prevents the user from only seeing a generic
    /// "set thresholds" text while the real cause is a physiologically
    /// inconsistent combination.
    static func emptyHRZonesExplanation(for profile: ProfileInput) -> String {
        let cross = validateProfile(profile)
        if let firstError = cross.first(where: { $0.severity == .error }) {
            return firstError.message + " Corrigeer de waarden om HR-zones te zien."
        }

        let hasMax = (profile.maxHR ?? 0) > 0
        let hasRest = (profile.restingHR ?? 0) > 0
        let hasLTHR = (profile.lthr ?? 0) > 0

        switch (hasLTHR, hasMax, hasRest) {
        case (false, true, false):
            return "Vul Rust HR in om zones via Karvonen te berekenen, of gebruik LTHR voor de Friel-methode."
        case (false, false, true):
            return "Vul Max HR in om zones via Karvonen te berekenen, of gebruik LTHR voor de Friel-methode."
        case (false, false, false):
            return "Stel een Max HR + Rust HR in (Karvonen) of een LTHR (Friel) om HR-zones te zien."
        default:
            return "HR-zones kunnen niet berekend worden met de huidige waarden."
        }
    }

    /// Explanation text for the FTP zones when they cannot be computed.
    static func emptyPowerZonesExplanation(for profile: ProfileInput) -> String {
        if let ftp = profile.ftp, ftp > 0 {
            return "Power-zones kunnen niet berekend worden met de huidige FTP-waarde."
        }
        return "Stel een FTP in om power-zones te zien."
    }

    // MARK: - Private helpers

    private static func ranges(for kind: Kind) -> (range: ClosedRange<Double>, absolute: ClosedRange<Double>) {
        switch kind {
        case .maxHR:     return (Range.maxHR, Range.absoluteMaxHR)
        case .restingHR: return (Range.restingHR, Range.absoluteRestingHR)
        case .lthr:      return (Range.lthr, Range.absoluteLTHR)
        case .ftp:       return (Range.ftp, Range.absoluteFTP)
        }
    }

    private static func formatRange(_ range: ClosedRange<Double>, unit: String) -> String {
        "\(Int(range.lowerBound))–\(Int(range.upperBound)) \(unit)"
    }
}
