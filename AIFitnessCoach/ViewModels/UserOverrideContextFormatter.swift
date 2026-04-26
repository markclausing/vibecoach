import Foundation

// MARK: - UserOverrideContextFormatter
//
// Bouwt het `[USER_OVERRIDE]`-blok in de coach-context. Pure Swift, testbaar zonder
// ChatViewModel-state. Story 33.2a — als de gebruiker een sessie handmatig heeft
// verplaatst (`isSwapped == true`), moet de coach dat respecteren en niet bij de
// volgende suggestie de oorspronkelijke datum terug-forceren. Zonder dit blok zou
// het coach-gedrag haaks staan op de gebruiker-intentie en frustreert het de UX.

enum UserOverrideContextFormatter {

    /// Formatteert verplaatste workouts naar een prompt-blok. Retourneert lege string
    /// als geen workouts zijn verschoven (dan komt het blok ook niet in de prompt — de
    /// AI hoeft niet vermoedelijk-leeg te raden).
    /// - Parameters:
    ///   - workouts: Het volledige actieve plan (alle workouts; we filteren op `isSwapped`).
    static func format(workouts: [SuggestedWorkout]) -> String {
        let swapped = workouts.filter { $0.isSwapped }
        guard !swapped.isEmpty else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM"
        formatter.locale = Locale(identifier: "nl_NL")

        let lines = swapped.map { workout -> String in
            let dayLabel = formatter.string(from: workout.displayDate)
            let capitalized = dayLabel.prefix(1).uppercased() + dayLabel.dropFirst()
            return "- '\(workout.activityType)' staat nu op \(capitalized) (handmatig verplaatst door de gebruiker)"
        }.joined(separator: "\n")

        return """
        [USER_OVERRIDE — handmatige planning-aanpassingen:
        \(lines)

        KRITIEKE INSTRUCTIE: De gebruiker heeft deze sessies bewust naar een andere dag verplaatst. Verschuif ze NIET terug bij een volgende schema-suggestie. Respecteer de nieuwe planning als gegeven en pas je advies daarop aan.]


        """
    }
}
