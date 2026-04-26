import Foundation

// MARK: - LastWorkoutContextFormatter
//
// Bouwt de prompt-string voor het 'laatste workout'-blok in de coach-context. Pure
// Swift, geen ChatViewModel-state — daardoor unit-testbaar zonder een echt model.
// Bij een aanwezig `sessionType` voegt de helper de fysiologische intentie toe zodat
// de coach feedback kan kalibreren ("goed hersteld" bij een Recovery-sessie met lage
// HR i.p.v. "je was te langzaam"). Dat is precies wat Epic 33 Story 33.1b oplost.

enum LastWorkoutContextFormatter {

    /// Formatteert het feedback-blok voor injectie in de Gemini system context.
    /// Retourneert een lege string als er onvoldoende data is (geen rpe of mood) —
    /// caller hoort die lege string te interpreteren als "geen blok in de prompt".
    /// - Parameters:
    ///   - rpe: RPE-score (1-10), optioneel.
    ///   - mood: Stemming-emoji of -woord, optioneel.
    ///   - workoutName: Naam van de workout, fallback "Training".
    ///   - trimp: TRIMP-score, optioneel ("onbekend" als nil).
    ///   - startDate: Datum van de workout, voor "[Type] van [Datum]"-format.
    ///   - sessionType: Optioneel — als aanwezig wordt het label + intent toegevoegd.
    static func format(rpe: Int?,
                       mood: String?,
                       workoutName: String?,
                       trimp: Double?,
                       startDate: Date?,
                       sessionType: SessionType?) -> String {
        guard let rpe, let mood else { return "" }

        let baseName = workoutName ?? "Training"
        let nameStr: String
        if let date = startDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.locale = Locale(identifier: "nl_NL")
            nameStr = "\(baseName) van \(formatter.string(from: date))"
        } else {
            nameStr = baseName
        }

        let trimpStr = trimp.map { String(format: "%.0f", $0) } ?? "onbekend"
        let rpeLabel: String
        switch rpe {
        case 1...3: rpeLabel = "licht (1-3)"
        case 4...6: rpeLabel = "matig (4-6)"
        case 7...8: rpeLabel = "zwaar (7-8)"
        default:    rpeLabel = "maximaal (9-10)"
        }

        var line = "Laatste workout: '\(nameStr)', TRIMP: \(trimpStr), RPE: \(rpe)/10 (\(rpeLabel)), Stemming: \(mood)."

        // Story 33.1b: voeg sessie-type + intent toe zodat de coach zijn toon kan
        // afstemmen. We geven de tekstuele intent mee — niet alleen het label —
        // omdat 'recovery' op zichzelf minder context biedt dan "actief herstel,
        // <65% HRmax". De architect-notitie hierop was expliciet.
        if let sessionType {
            let intent = sessionType.intent
            line += " Sessie-type: \(sessionType.displayName) — \(intent.coachingSummary)"
        }

        return line
    }
}
