import Foundation

// MARK: - PlanResetPromptBuilder
//
// Bouwt de Gemini-systeem-instructie voor Story 33.2b "Reset Schema". Pure Swift,
// testbaar zonder ChatViewModel-state.
//
// De prompt vraagt de coach om de overige dagen te plannen ROND de verplaatste
// sessies — die zijn heilig. App-side filtert `TrainingPlanManager.mergeReplannedPlan`
// alsnog AI-output uit die toch op gereserveerde dagen valt (defense in depth).

enum PlanResetPromptBuilder {

    /// Bouwt de system-prompt + bijbehorende user-facing tekst voor de plan-reset.
    /// - Parameters:
    ///   - swappedWorkouts: De handmatig verplaatste workouts uit het huidige plan.
    ///   - now: Referentiedatum voor "vanaf vandaag"-formulering (injecteerbaar voor tests).
    /// - Returns: Tuple van `systemText` (verborgen voor gebruiker) en `userText` (in chat zichtbaar).
    static func build(swappedWorkouts: [SuggestedWorkout], now: Date = Date()) -> (systemText: String, userText: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "nl_NL")
        dateFormatter.dateFormat = "EEEE d MMM"

        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"

        let todayLabel = dateFormatter.string(from: now).capitalized
        let todayIso = isoFormatter.string(from: now)

        var lines: [String] = [
            "PLAN-RESET CONTEXT — De gebruiker heeft één of meer sessies handmatig verplaatst en vraagt nu om de rest van de week opnieuw te plannen.",
            ""
        ]

        if swappedWorkouts.isEmpty {
            // Edge case: geen swaps → toch reset; we vragen een schoon 7-daags plan.
            lines.append("Er zijn geen handmatig verplaatste sessies. Bouw een schoon 7-daags plan vanaf \(todayLabel) (\(todayIso)).")
        } else {
            lines.append("Heilige verplaatste sessies (NIET aanraken — exact deze dag, exact deze sessie behouden):")
            for workout in swappedWorkouts {
                let dayLabel = dateFormatter.string(from: workout.displayDate).capitalized
                let dayIso = isoFormatter.string(from: workout.displayDate)
                let trimpStr = workout.targetTRIMP.map { " (TRIMP \($0))" } ?? ""
                lines.append("- \(dayLabel) (\(dayIso)): '\(workout.activityType)'\(trimpStr)")
            }
            lines.append("")
            lines.append("INSTRUCTIE: Plan de andere 6 dagen vanaf \(todayLabel) (\(todayIso)). De verplaatste sessies hierboven moeten EXACT op hun datum blijven staan met EXACT hun activityType. Verzin geen alternatieven, verschuif niet, vervang niet. Pas je weekvolume-target aan rond deze vaste sessies — je hebt minder vrije ruimte dan normaal.")
        }
        lines.append(contentsOf: [
            "",
            "BELANGRIJK:",
            "1. Retourneer het VOLLEDIGE 7-daagse schema in JSON-formaat (inclusief de heilige sessies — kopieer ze letterlijk uit de lijst hierboven).",
            "2. Gebruik ISO-datums (yyyy-MM-dd) in `dateOrDay` zodat de mapping eenduidig is, niet 'Maandag'.",
            "3. Respecteer de 10-15% progressieregel en de huidige TrainingPhase-target (zie eerdere context).",
            "4. App-side merge filtert alsnog elke sessie weg die toch op een heilige dag landt — dus liever te conservatief dan te creatief."
        ])

        let systemText = lines.joined(separator: "\n")

        let userText: String
        if swappedWorkouts.count == 1 {
            userText = "Herschrijf de rest van mijn week rondom de verplaatste sessie."
        } else if swappedWorkouts.isEmpty {
            userText = "Herschrijf mijn week vanaf vandaag."
        } else {
            userText = "Herschrijf de rest van mijn week rondom de \(swappedWorkouts.count) verplaatste sessies."
        }
        return (systemText, userText)
    }
}
