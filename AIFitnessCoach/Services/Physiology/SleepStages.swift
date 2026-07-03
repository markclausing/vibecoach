import Foundation

// MARK: - SleepStages

/// Epic 21 Sprint 2: detailed breakdown of the previous night's sleep stages.
/// Contains only stage-specific data (iOS 16+ Apple Watch). Nil = older device or Watch not worn.
struct SleepStages {
    let deepMinutes: Int
    let remMinutes: Int
    let coreMinutes: Int
    let totalMinutes: Int
    /// Exact start of the sleep session (earliest Core/Deep/REM sample).
    /// Passed to fetchRecentHRV() to bound the HRV window.
    let sessionStart: Date?
    /// Exact end of the sleep session (latest Core/Deep/REM sample).
    let sessionEnd: Date?

    /// Ratio of deep sleep to total sleep time (0.0–1.0).
    var deepRatio: Double {
        totalMinutes > 0 ? Double(deepMinutes) / Double(totalMinutes) : 0
    }

    /// Quality label based on the deep-sleep ratio.
    /// Science: a healthy adult has ~15–25% deep sleep.
    var qualityLabel: String {
        if deepRatio >= 0.20 { return "Uitstekend" }
        if deepRatio >= 0.15 { return "Goed" }
        if deepRatio >= 0.10 { return "Matig" }
        return "Onvoldoende"
    }

    /// SF Symbol matching the sleep quality.
    var qualityIcon: String {
        if deepRatio >= 0.15 { return "moon.stars.fill" }
        if deepRatio >= 0.10 { return "moon.fill" }
        return "moon.zzz.fill"
    }

    /// Helper formatter: "X u Y m" string.
    static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)u \(m)m" : "\(h)u"
    }
}
