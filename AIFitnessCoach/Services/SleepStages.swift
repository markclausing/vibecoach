import Foundation

// MARK: - SleepStages

/// Epic 21 Sprint 2: Gedetailleerde uitsplitsing van slaapfases van de afgelopen nacht.
/// Bevat alleen stage-specifieke data (iOS 16+ Apple Watch). Nil = ouder device of Watch niet gedragen.
struct SleepStages {
    let deepMinutes:  Int
    let remMinutes:   Int
    let coreMinutes:  Int
    let totalMinutes: Int
    /// Exacte start van de slaapsessie (vroegste Core/Deep/REM sample).
    /// Wordt doorgegeven aan fetchRecentHRV() om het HRV-venster te begrenzen.
    let sessionStart: Date?
    /// Exacte eind van de slaapsessie (laatste Core/Deep/REM sample).
    let sessionEnd: Date?

    /// Verhouding diepe slaap t.o.v. totale slaaptijd (0.0–1.0).
    var deepRatio: Double {
        totalMinutes > 0 ? Double(deepMinutes) / Double(totalMinutes) : 0
    }

    /// Kwaliteitslabel op basis van de diepeslaap-ratio.
    /// Wetenschap: gezonde volwassen heeft ~15–25% diepe slaap.
    var qualityLabel: String {
        if deepRatio >= 0.20 { return "Uitstekend" }
        if deepRatio >= 0.15 { return "Goed" }
        if deepRatio >= 0.10 { return "Matig" }
        return "Onvoldoende"
    }

    /// SF Symbol passend bij de slaapkwaliteit.
    var qualityIcon: String {
        if deepRatio >= 0.15 { return "moon.stars.fill" }
        if deepRatio >= 0.10 { return "moon.fill" }
        return "moon.zzz.fill"
    }

    /// Helperformatter: X u Y m string.
    static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)u \(m)m" : "\(h)u"
    }
}
