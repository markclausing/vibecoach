import Foundation

/// Pure-Swift formatter voor de Vibe Score-context die in de coach-prompt geïnjecteerd wordt.
///
/// Wordt aangeroepen door `ChatViewModel.cacheVibeScore` en in tests direct testbaar zonder
/// `@AppStorage` of `UserDefaults`-fixture. Returnt de geformatteerde context-string die in
/// `vibecoach_todayVibeScoreContext` opgeslagen wordt.
enum VibeScoreContextFormatter {

    /// Sentinel-waarde die aangeeft dat er vandaag geen Watch-data beschikbaar was.
    /// Wordt herkend in `buildContextPrefix` om de coach de juiste instructie te geven.
    static let noVibeDataSentinel = "GEEN_BIOMETRISCHE_DATA"

    /// Formatteert een `DailyReadiness` naar een context-string voor de AI-coach.
    /// Bevat readinessScore + label, slaapuren, HRV, en — indien beschikbaar — slaapfase-
    /// kwaliteit met een coaching-instructie bij slechte diepe slaap.
    /// - Parameter readiness: De readiness-record van vandaag, of nil als er geen data is.
    /// - Parameter previousValue: De huidige cache-waarde. Wordt gebruikt om te voorkomen
    ///   dat een al-aanwezige `noVibeDataSentinel` per ongeluk overschreven wordt met "".
    /// - Returns: De nieuw te schrijven cache-waarde.
    static func format(readiness: DailyReadiness?, previousValue: String) -> String {
        guard let r = readiness else {
            // Niet overschrijven als er al een 'unavailable' sentinel staat —
            // die is waardevoller dan gewoon leeg.
            if previousValue == noVibeDataSentinel { return previousValue }
            return ""
        }

        let label: String
        if r.readinessScore >= 80 { label = "Optimaal Hersteld" }
        else if r.readinessScore >= 50 { label = "Matig Hersteld" }
        else { label = "Slecht Hersteld — Rust prioriteit" }

        let sleepH = Int(r.sleepHours)
        let sleepM = Int((r.sleepHours - Double(sleepH)) * 60)

        // Epic 21 Sprint 2: voeg slaapfase-kwaliteit toe als stage-data beschikbaar is
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

            // Geef de coach een expliciete instructie bij slechte diepe slaap
            if deepRatio < 0.15 {
                sleepQualityNote += " INSTRUCTIE: Benoem de slaapkwaliteit expliciet in je Insight ('Je hebt \(sleepH)u \(sleepM)m geslapen maar de diepe slaap was maar \(String(format: "%.0f%%", deepRatio * 100)) — herstel is daardoor minder effectief'). Houd de intensiteit dienovereenkomstig lager."
            }
        }

        return "Vibe Score vandaag: \(r.readinessScore)/100 (\(label)). Slaap: \(sleepH)u \(sleepM)m. HRV: \(String(format: "%.1f", r.hrv)) ms.\(sleepQualityNote)"
    }
}
