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
        if r.readinessScore >= 80 { label = "Optimaal Hersteld" } else if r.readinessScore >= 50 { label = "Matig Hersteld" } else { label = "Slecht Hersteld — Rust prioriteit" }

        let sleepH = Int(r.sleepHours)
        let sleepM = Int((r.sleepHours - Double(sleepH)) * 60)

        // Epic 21 Sprint 2: add sleep-stage quality if stage data is available
        var sleepQualityNote = ""
        let totalStageMins = r.deepSleepMinutes + r.remSleepMinutes + r.coreSleepMinutes
        if totalStageMins > 0 {
            let deepRatio = Double(r.deepSleepMinutes) / Double(totalStageMins)
            let qualLabel: String = {
                if deepRatio >= 0.20 { return "Uitstekend" }
                if deepRatio >= 0.15 { return "Goed" }
                if deepRatio >= 0.10 { return "Matig" }
                return "Onvoldoende"
            }()
            sleepQualityNote = " Slaapfases: diep \(r.deepSleepMinutes)m · REM \(r.remSleepMinutes)m · kern \(r.coreSleepMinutes)m (kwaliteit: \(qualLabel), \(String(format: "%.0f%%", deepRatio * 100)) diepe slaap)."

            // Give the coach an explicit instruction on poor deep sleep
            if deepRatio < 0.15 {
                sleepQualityNote += " INSTRUCTIE: Benoem de slaapkwaliteit expliciet in je Insight ('Je hebt \(sleepH)u \(sleepM)m geslapen maar de diepe slaap was maar \(String(format: "%.0f%%", deepRatio * 100)) — herstel is daardoor minder effectief'). Houd de intensiteit dienovereenkomstig lager."
            }
        }

        return "Vibe Score vandaag: \(r.readinessScore)/100 (\(label)). Slaap: \(sleepH)u \(sleepM)m. HRV: \(String(format: "%.1f", r.hrv)) ms.\(sleepQualityNote)"
    }
}
