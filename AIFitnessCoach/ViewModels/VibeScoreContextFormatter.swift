import Foundation

/// Pure-Swift formatter for the Vibe Score context injected into the coach prompt.
///
/// Called by `ChatViewModel.cacheVibeScore` and directly testable in tests without
/// an `@AppStorage` or `UserDefaults` fixture. Returns the formatted context string
/// stored in `vibecoach_todayVibeScoreContext`.
enum VibeScoreContextFormatter {

    /// Sentinel value indicating no Watch data was available today.
    /// Recognized in `buildContextPrefix` to give the coach the right instruction.
    static let noVibeDataSentinel = "GEEN_BIOMETRISCHE_DATA"

    /// Formats a `DailyReadiness` into a context string for the AI coach.
    /// Contains readinessScore + label, sleep hours, HRV, and — when available — sleep-stage
    /// quality with a coaching instruction on poor deep sleep.
    /// - Parameter readiness: Today's readiness record, or nil if there's no data.
    /// - Parameter previousValue: The current cache value. Used to prevent an
    ///   already-present `noVibeDataSentinel` from being accidentally overwritten with "".
    /// - Returns: The new cache value to write.
    static func format(readiness: DailyReadiness?, previousValue: String) -> String {
        guard let r = readiness else {
            // Don't overwrite if an 'unavailable' sentinel is already present —
            // it's more valuable than just empty.
            if previousValue == noVibeDataSentinel { return previousValue }
            return ""
        }

        let label: String
        if r.readinessScore >= 80 { label = "Optimally Recovered" } else if r.readinessScore >= 50 { label = "Moderately Recovered" } else { label = "Poorly Recovered — Rest priority" }

        let sleepH = Int(r.sleepHours)
        let sleepM = Int((r.sleepHours - Double(sleepH)) * 60)

        // Epic 21 Sprint 2: add sleep-stage quality if stage data is available
        var sleepQualityNote = ""
        let totalStageMins = r.deepSleepMinutes + r.remSleepMinutes + r.coreSleepMinutes
        if totalStageMins > 0 {
            let deepRatio = Double(r.deepSleepMinutes) / Double(totalStageMins)
            let qualLabel: String = {
                if deepRatio >= 0.20 { return "Excellent" }
                if deepRatio >= 0.15 { return "Good" }
                if deepRatio >= 0.10 { return "Moderate" }
                return "Insufficient"
            }()
            sleepQualityNote = " Sleep stages: deep \(r.deepSleepMinutes)m · REM \(r.remSleepMinutes)m · core \(r.coreSleepMinutes)m (quality: \(qualLabel), \(String(format: "%.0f%%", deepRatio * 100)) deep sleep)."

            // Give the coach an explicit instruction on poor deep sleep
            if deepRatio < 0.15 {
                sleepQualityNote += " INSTRUCTION: Mention sleep quality explicitly in your Insight ('You slept \(sleepH)h \(sleepM)m but deep sleep was only \(String(format: "%.0f%%", deepRatio * 100)) — recovery is therefore less effective'). Keep the intensity correspondingly lower."
            }
        }

        return "Vibe Score today: \(r.readinessScore)/100 (\(label)). Sleep: \(sleepH)h \(sleepM)m. HRV: \(String(format: "%.1f", r.hrv)) ms.\(sleepQualityNote)"
    }
}
