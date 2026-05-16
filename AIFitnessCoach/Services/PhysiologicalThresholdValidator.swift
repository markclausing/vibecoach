import Foundation

/// Epic #51-C: pure-Swift validatie voor de vier persoonlijke trainingsdrempels
/// die de gebruiker handmatig kan invoeren in `TrainingThresholdsSettingsView`.
///
/// Twee soorten checks, beide gegrond in sport-fysiologie:
///
/// 1. **Range-checks** per individuele drempel — voorkomt typos en absurde
///    waarden (Max HR = 5, FTP = 5000W) die de zone-calculators zinloze zones
///    laten opleveren.
/// 2. **Cross-checks** over het hele profiel — fysiologische consistentie
///    (Max HR moet hoger zijn dan Rust HR, LTHR ligt tussen Rust en Max).
///    Zonder deze checks gaf `HeartRateZoneCalculator.karvonen()` stilletjes
///    een lege zone-array en zag de gebruiker enkel "—" in de zone-preview.
///
/// AppStorage-vrij — caller injecteert de invoer als parameters zodat tests
/// een fresh `UserDefaults(suiteName:)`-flow niet hoeven op te zetten
/// (CLAUDE.md §6).
enum PhysiologicalThresholdValidator {

    /// Geldige ranges per drempel — `closed range` waarin de waarde fysiologisch
    /// realistisch is. Buiten deze range is een **warning** (toch op te slaan
    /// met een waarschuwing), buiten de absolute grens (negatief, 0) is een
    /// **error** (geblokkeerd).
    enum Range {
        static let maxHR: ClosedRange<Double> = 120...230
        static let restingHR: ClosedRange<Double> = 30...100
        static let lthr: ClosedRange<Double> = 100...200
        static let ftp: ClosedRange<Double> = 75...600

        /// Absolute "absurde waarden"-grens — buiten deze range hard blokkeren
        /// omdat de zone-calculator dan onzin-zones produceert.
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

    /// Het hele profiel als input — alleen waarden die de gebruiker daadwerkelijk
    /// heeft ingevuld zijn `Double`, ontbrekende drempels blijven `nil`.
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

    // MARK: - Per-veld validatie

    /// Valideert één drempel onafhankelijk van de rest van het profiel.
    ///
    /// - `value == nil` → `.ok` (drempel niet ingesteld = ok, formule-default
    ///   wordt gebruikt door de zone-calculators)
    /// - `value <= 0` of buiten absolute range → `.error`
    /// - `value` buiten realistische range → `.warning`
    /// - anders → `.ok`
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

    // MARK: - Cross-validatie

    /// Valideert het volledige profiel op fysiologische consistentie. Specifiek:
    /// - Max HR moet > Rust HR zijn (anders levert de Karvonen-formule een
    ///   negatieve HRR op en faalt de zone-berekening stilletjes).
    /// - LTHR moet < Max HR (LTHR is per definitie sub-maximaal).
    /// - LTHR moet > Rust HR (anders is het geen threshold-effort).
    /// - FTP staat los — geen cross-relatie met HR-drempels.
    ///
    /// Returnt een lege array als alles ok is, anders één of meer `Issue`s.
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

    /// Convenience voor de UI: returnt `true` als het volledige profiel veilig
    /// op te slaan is (geen `.error`-issues). `.warning`-issues blokkeren niet.
    static func isSavable(_ profile: ProfileInput) -> Bool {
        validateProfile(profile).allSatisfy { $0.severity != .error }
    }

    // MARK: - Zone-card-uitleg (C4)

    /// Genereert een uitlegtekst voor de zones-preview-card wanneer de zones
    /// niet berekend kunnen worden. Voorkomt dat de gebruiker enkel een
    /// generieke "stel drempels in"-tekst ziet terwijl de echte oorzaak een
    /// fysiologisch inconsistente combinatie is.
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

    /// Uitlegtekst voor de FTP-zones wanneer die niet berekend kunnen worden.
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
